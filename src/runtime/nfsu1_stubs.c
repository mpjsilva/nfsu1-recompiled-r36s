/*
 * nfsu1_stubs.c - NFSU1 (SPEED.EXE) build: the runtime pieces tuned to SPEED2.EXE addresses are left out
 * (fx_cache.c, hud_half.c, world_cull.c, native_math.c, native_scene.c). The renderer's fast paths still
 * test whether an effect capture is open; with no effect cache none ever is.
 */
#include <stdint.h>

int nfs_fx_cap_depth;
void nfs_fx_capture(uint32_t token, const uint32_t* args, uint32_t count, int deferred) {
    (void)token; (void)args; (void)count; (void)deferred;
}
