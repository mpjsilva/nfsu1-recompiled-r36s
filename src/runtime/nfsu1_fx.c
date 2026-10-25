/*
 * nfsu1_fx.c - NFSU1 (SPEED.EXE): native application of the simple D3DX effect states.
 *
 * NFSU1 links the D3DX of the first DirectX 9 SDK. ID3DXEffect::Pass (0x005D01EC) walks the states of the
 * pass (0xAC-byte records) and, for each, evaluates it (0x005CDCA7) and applies it to the device with
 * sub_005C97CB(this = effect in ecx, state, index) (thiscall, ret 8). The game calls Pass once per drawn
 * object; on the R36S this application was the hottest lifted function in a race (22% of the game thread's
 * samples with it innermost, plus the device calls under it).
 *
 * Layout (as read from the lifted code):
 *   index == -1 -> [state+4];  [state+0] == -1 -> the state is the one at [state+0x64]
 *   descriptor = [0x006DC274 + [state+0] * 0x1C]: type in the top byte, D3D state number in the low 24 bits
 *   value = [state+0x68];  device = [effect+8]
 *   type 1: SetRenderState(device, number, value)              (IDirect3DDevice9 method 57)
 *   type 2: SetTextureStageState(device, index, number, value) (method 67)
 *   type 8: SetSamplerState(device, index, number, value)      (method 69)
 *   result: a failed HRESULT is returned only when [effect+0x84] != 1, otherwise 0.
 * Those three types are exactly one device call from the stored value, so they are issued here through the
 * render thread's queue (nfsD3dDeviceCall); every other type (transforms, lights, materials, textures and
 * shaders from parameters, constants) runs the lifted original.
 *
 * NFSU1_FX_NATIVE=0 runs the original for every state; NFSU1_FX_STATS=1 logs the states applied per frame
 * by type.
 */
#include "recomp_types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void sub_005C97CB_orig(void);
extern int nfsD3dDeviceCall(uint32_t method, const uint32_t* args, uint32_t* result);
extern uint32_t getD3D9PresentCount(void);

static int g_mode = -1, g_stats = -1;
static uint32_t g_count[2][16], g_frame, g_frames;

static void stats(uint32_t type, int native) {
    ++g_count[native][type & 15];
    const uint32_t now = getD3D9PresentCount();
    if (now == g_frame) return;
    g_frame = now;
    if (++g_frames % 240) return;
    printf("[NFSU1 FX] states applied per frame by type (native/lifted):");
    for (int t = 0; t < 16; ++t)
        if (g_count[0][t] || g_count[1][t]) printf(" t%d=%u/%u", t, g_count[1][t] / 240, g_count[0][t] / 240);
    printf("\n");
    for (int t = 0; t < 16; ++t) g_count[0][t] = g_count[1][t] = 0;
}

void sub_005C97CB(void) {
    if (__builtin_expect(g_mode < 0, 0)) {
        const char* e = getenv("NFSU1_FX_NATIVE"); g_mode = e ? atoi(e) : 1;
        e = getenv("NFSU1_FX_STATS"); g_stats = e && atoi(e) != 0;
    }
    const uint32_t effect = g_ecx;
    uint32_t state = MEM32(g_esp + 4), index = MEM32(g_esp + 8);
    if (index == 0xffffffffu) index = MEM32(state + 4);
    if (MEM32(state) == 0xffffffffu) state = MEM32(state + 0x64);
    const uint32_t desc = MEM32(0x006DC274u + MEM32(state) * 0x1Cu), type = desc >> 24;
    uint32_t method = 0;
    switch (type) {
    case 1: method = 57; break;
    case 2: method = 67; break;
    case 8: method = 69; break;
    default: break;
    }
    if (g_mode && method) {
        const uint32_t device = MEM32(effect + 8), number = desc & 0xFFFFFFu, value = MEM32(state + 0x68);
        uint32_t args[4], result = 0;
        if (type == 1) { args[0] = device; args[1] = number; args[2] = value; args[3] = 0; }
        else { args[0] = device; args[1] = index; args[2] = number; args[3] = value; }
        if (nfsD3dDeviceCall(method, args, &result)) {
            g_eax = ((int32_t)result < 0 && MEM32(effect + 0x84) != 1) ? result : 0;
            g_esp += 12;  /* ret 8 */
            if (g_stats) stats(type, 1);
            return;
        }
    }
    if (g_stats) stats(type, 0);
    sub_005C97CB_orig();
}

/*
 * ---- Parameter change propagation (sub_005D02D7) ----
 *
 * Every ID3DXEffect::Set* method (SetMatrix 0x005D362C, SetValue, SetFloat, SetVector, ... 20 of them) stores
 * the value and then calls sub_005D02D7(this = effect, desc) (thiscall, ret 4), which re-evaluates every state
 * expression that reads the parameter (sub_005CF304) and, inside a pass, applies the results to the device.
 * desc: [desc+4] parameter index into [effect+0x8C]; type record = [param+0x24] + [desc+8] + base, data =
 * [param+0x28] + [desc+0xC] + base, base = [effect+0x2C], or [[effect+0xC]+8] for a shared ([param+0x38])
 * parameter. Type record: [+0] type (1 bool, 2 int, 3 float), [+0x10] elements (0 = not an array),
 * [+0x14] rows, [+0x18] columns.
 * NFSU1_FX_SETS=1 counts the propagations whose parameter bytes equal those of the previous propagation of the
 * same parameter (what a skip would save); the original always runs.
 */
extern void sub_005D02D7_orig(void);
#define PSETS 4096
typedef struct { uint32_t key, size; uint8_t data[64]; } SetSnap;
static SetSnap g_snap[PSETS];
static uint32_t g_setFrame, g_setFrames, g_sets, g_same, g_big, g_inPass, g_samePass;
static int g_setMode = -1;

void sub_005D02D7(void) {
    if (__builtin_expect(g_setMode < 0, 0)) { const char* e = getenv("NFSU1_FX_SETS"); g_setMode = e ? atoi(e) : 0; }
    if (!g_setMode) { sub_005D02D7_orig(); return; }
    const uint32_t effect = g_ecx, desc = MEM32(g_esp + 4);
    const uint32_t param = MEM32(MEM32(effect + 0x8C) + MEM32(desc + 4) * 4);
    const uint32_t base = MEM32(param + 0x38) ? MEM32(MEM32(effect + 0xC) + 8) : MEM32(effect + 0x2C);
    const uint32_t type = MEM32(param + 0x24) + MEM32(desc + 8) + base, data = MEM32(param + 0x28) + MEM32(desc + 0xC) + base;
    const uint32_t kind = MEM32(type), elements = MEM32(type + 0x10), rows = MEM32(type + 0x14), cols = MEM32(type + 0x18);
    uint32_t size = (kind >= 1 && kind <= 3 && rows <= 4 && cols <= 4) ? rows * cols * 4 * (elements ? elements : 1) : 0;
    const int inPass = MEM32(effect + 0x84) == 3;
    ++g_sets; if (inPass) ++g_inPass;
    SetSnap* sn = &g_snap[(desc >> 2) & (PSETS - 1)];
    if (!size || size > 64) ++g_big;
    else {
        const int same = sn->key == desc && sn->size == size && !memcmp(sn->data, (const void*)ADDR(data), size);
        if (same) { ++g_same; if (inPass) ++g_samePass; }
    }
    sub_005D02D7_orig();
    if (size && size <= 64) { sn->key = desc; sn->size = size; memcpy(sn->data, (const void*)ADDR(data), size); }
    const uint32_t now = getD3D9PresentCount();
    if (now != g_setFrame) {
        g_setFrame = now;
        if (++g_setFrames % 240 == 0) {
            printf("[NFSU1 FX] parameter sets/frame %u: same bytes as last time %u (in a pass %u of %u), not compared %u\n",
                   g_sets / 240, g_same / 240, g_samePass / 240, g_inPass / 240, g_big / 240);
            g_sets = g_same = g_big = g_inPass = g_samePass = 0;
        }
    }
}
