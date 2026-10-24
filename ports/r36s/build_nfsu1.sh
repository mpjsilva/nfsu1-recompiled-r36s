#!/bin/bash
# Cross build of nfsu1.aarch64 (NFS Underground, SPEED.EXE) on an x86_64 box, inside an Ubuntu 22.04
# container with g++-aarch64-linux-gnu (same glibc/libstdc++ as the VM build of nfsu2.aarch64).
#   ROOT      this checkout (nfsu1 branch)
#   PCRECOMP  pcrecomp with patches/pcrecomp applied and the recomp32/win32hle headers of ports/r36s/sdk
#   GEN       lifted C of SPEED.EXE (run_lift.py lift output)
#   OUT       build directory (objects are reused while their source is unchanged)
# Differences from build_guest_vm.sh + build_vm.sh: no *_orig wrappers and none of the SPEED2-specific
# runtime files (fx_cache, hud_half, world_cull, native_math, native_scene), no NFS_X87_LW tables; the
# device libraries (SDL2, GLESv2, EGL) are linked as stubs carrying their sonames.
set -e
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PCRECOMP="${PCRECOMP:-$ROOT/../pcrecomp}"
GEN="${GEN:-$ROOT/src/recomp/gen}"
OUT="${OUT:-$ROOT/build/nfsu1}"
JOBS="${JOBS:-$(nproc)}"
CROSS="${CROSS:-aarch64-linux-gnu-}"
CC="${CROSS}gcc"; CXX="${CROSS}g++"
SDK="$ROOT/ports/r36s/sdk/include"
mkdir -p "$OUT/guest" "$OUT/split" "$OUT/obj" "$OUT/stub" "$OUT/sdk"

if [ ! -f "$OUT/sdk/SDL2/SDL_config.h" ]; then
  cp -r "$SDK/SDL2" "$OUT/sdk/"
  sed -i -E '/#define HAVE_(IMMINTRIN|MMINTRIN|XMMINTRIN|EMMINTRIN|PMMINTRIN)_H/d' "$OUT/sdk/SDL2/SDL_config.h"
fi

# ---- guest: the lifted game code ----
GUEST_CFLAGS="${GUEST_CFLAGS:--O2 -mcpu=cortex-a35 -fno-pie -DNFS_FIXED_GUEST_BASE=0x1000000000ULL -DRECOMP_TLS=__thread -DRECOMP_TLS_STRUCT -ftls-model=local-exec -fno-math-errno -fno-stack-clash-protection -fno-stack-protector -DNFS_X87_LOCAL}"
GFLAGS="$GUEST_CFLAGS -DNFS_GAME_U1 -w -fwrapv -fno-strict-aliasing -fexceptions -ffp-contract=off -g0 -fvisibility=hidden \
 -include $ROOT/android/app/src/main/cpp/arm64_guest.h -DRECOMP_STRICT_ICALL -DRECOMP_LOCAL_REGS -DRECOMP_X87_WINDOW \
 -DRECOMP_MEM_QUAL= -I$PCRECOMP/runtime/recomp32 -I$GEN"
STAMP="$OUT/guest/.flags"
if [ "$(cat "$STAMP" 2>/dev/null)" != "$GFLAGS" ]; then rm -f "$OUT"/guest/*.o; echo "$GFLAGS" > "$STAMP"; fi
SRCS=()
for f in "$GEN"/recomp_*.c; do
  if [ "$(stat -c %s "$f")" -gt 8000000 ]; then
    stem=$(basename "$f" .c)
    if [ ! -f "$OUT/split/$stem.done" ] || [ "$f" -nt "$OUT/split/$stem.done" ]; then
      rm -f "$OUT/split/${stem}"_part_*.c
      python3 "$ROOT/scripts/split_android_sources.py" "$f" "$OUT/split" --max-bytes 6000000 > /dev/null
      touch "$OUT/split/$stem.done"
    fi
    for p in "$OUT/split/${stem}"_part_*.c; do SRCS+=("$p"); done
  else
    SRCS+=("$f")
  fi
done
HDR="$ROOT/android/app/src/main/cpp/arm64_guest.h"
TODO="$OUT/guest/.todo"; : > "$TODO"
for src in "${SRCS[@]}"; do
  obj="$OUT/guest/$(basename "$src" .c).o"
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ] || [ "$HDR" -nt "$obj" ]; then echo "$src" >> "$TODO"; fi
done
for o in "$OUT"/guest/*.o; do   # objects of sources that no longer exist must not be linked
  [ -e "$o" ] || continue; n=$(basename "$o" .o); keep=0
  for src in "${SRCS[@]}"; do [ "$(basename "$src" .c)" = "$n" ] && { keep=1; break; }; done
  [ $keep = 1 ] || rm -f "$o"
done
echo "guest: $(wc -l < "$TODO") of ${#SRCS[@]} sources to compile"
export CC GFLAGS OUT
xargs -a "$TODO" -r -P "$JOBS" -I{} sh -c 'o="$OUT/guest/$(basename "{}" .c).o"; $CC -c "{}" -o "$o.tmp" $GFLAGS && mv "$o.tmp" "$o" && echo "  CC $(basename "{}")"'
for src in "${SRCS[@]}"; do [ -f "$OUT/guest/$(basename "$src" .c).o" ] || { echo "ERROR: guest object missing for $src"; exit 1; }; done

# ---- host: runtime, D3D9 -> GLES, MojoShader ----
DXVK="$SDK/dxvk/native"
MOJO="$ROOT/third_party/mojoshader"
SDLI="-I$OUT/sdk -I$OUT/sdk/SDL2"
MOJODEF="-DSUPPORT_PROFILE_ARB1=0 -DSUPPORT_PROFILE_ARB1_NV=0 -DSUPPORT_PROFILE_HLSL=0 -DSUPPORT_PROFILE_METAL=0 -DSUPPORT_PROFILE_D3D=0 -DSUPPORT_PROFILE_BYTECODE=0 -DSUPPORT_PROFILE_SPIRV=0 -DSUPPORT_PROFILE_GLSPIRV=0 -DMOJOSHADER_DEPTH_CLIPPING -DMOJOSHADER_FLIP_RENDERTARGET"
GLESINC="-I$ROOT/ports/r36s/d3d9_gles -I$MOJO -I$SDK -I$DXVK -I$DXVK/windows -I$DXVK/directx $SDLI"
APPINC="-I$SDK/dxvk -I$ROOT/ports/r36s -I$ROOT/ports/r36s/d3d9_gles -I$ROOT/android/app/src/main/cpp -I$ROOT/src/runtime -I$ROOT/src/platform -I$PCRECOMP/runtime/recomp32 -I$PCRECOMP/runtime/win32hle -I$SDK $SDLI -isystem $DXVK -isystem $DXVK/windows -isystem $DXVK/directx"
APPDEF="-DNFS_GAME_U1 -DRECOMP_TLS=__thread -DRECOMP_TLS_STRUCT -DNFS_PARALLEL_GUEST -DNFS_FIXED_GUEST_BASE=0x1000000000ULL -DNFS_R36S -DNFS_GLES -DNFS_D3D9_BACKEND -DNFS_SDL_AUDIO -DRECOMP_STRICT_ICALL -DRECOMP_X87_WINDOW $MOJODEF"
OPT="-O2 -g -DNDEBUG -fno-strict-aliasing -ffp-contract=off -mcpu=cortex-a35"
compile() { # src obj cmd...
  local src="$1" obj="$2"; shift 2
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ] || [ -n "$FORCE" ] || \
     [ -n "$(find "$ROOT/ports/r36s" "$ROOT/android/app/src/main/cpp" "$ROOT/src/runtime" \( -name '*.h' -o -name '*.inc' \) -newer "$obj" | head -1)" ]; then
    echo "  CC $(basename "$src")"; "$@" -c "$src" -o "$obj"
  fi
}
pids=()
compile "$ROOT/ports/r36s/d3d9_gles/d3d9_gles.cpp" "$OUT/obj/d3d9_gles.o" $CXX -std=c++17 $OPT $MOJODEF -DNFS_GAME_U1 -DNFS_R36S -DNFS_GLES $GLESINC & pids+=($!)
for c in mojoshader.c mojoshader_common.c profiles/mojoshader_profile_common.c profiles/mojoshader_profile_glsl.c; do
  compile "$MOJO/$c" "$OUT/obj/$(basename "$c" .c).o" $CC $OPT $MOJODEF -DNFS_R36S -DNFS_GLES -I"$MOJO" & pids+=($!)
done
compile "$ROOT/ports/r36s/main.cpp" "$OUT/obj/main.o" $CXX -std=c++17 $OPT $APPDEF $APPINC & pids+=($!)
compile "$ROOT/ports/r36s/music_player.cpp" "$OUT/obj/music_player.o" $CXX -std=c++17 $OPT $APPDEF $APPINC -w & pids+=($!)
compile "$ROOT/android/app/src/main/cpp/guest_runtime.cpp" "$OUT/obj/guest_runtime.o" $CXX -std=c++17 $OPT $APPDEF $APPINC & pids+=($!)
compile "$ROOT/android/app/src/main/cpp/d3d9_bridge.cpp" "$OUT/obj/d3d9_bridge.o" $CXX -std=c++17 $OPT $APPDEF $APPINC & pids+=($!)
compile "$ROOT/src/runtime/overrides.c" "$OUT/obj/overrides.o" $CC $OPT $APPDEF $APPINC & pids+=($!)
compile "$ROOT/src/runtime/widescreen.c" "$OUT/obj/widescreen.o" $CC $OPT $APPDEF $APPINC & pids+=($!)
for extra in src/runtime/nfsu1_stubs.c $NFSU1_EXTRA_SOURCES; do
  compile "$ROOT/$extra" "$OUT/obj/$(basename "$extra" .c).o" $CC $OPT $APPDEF $APPINC & pids+=($!)
done
fail=0; for p in "${pids[@]}"; do wait "$p" || fail=1; done
[ "$fail" = 0 ] || { echo "compile failed"; exit 1; }

# ---- device library stubs: the binary only needs the symbols and the sonames to link ----
${CROSS}nm -u "$OUT"/obj/*.o | awk '{print $2}' | sort -u > "$OUT/stub/undefined.txt"
mkstub() { # pattern soname file
  grep -E "$1" "$OUT/stub/undefined.txt" | sed 's/.*/void &(void){}/' > "$OUT/stub/$3.c"
  $CC -shared -fPIC -o "$OUT/stub/$3" -Wl,-soname,"$2" "$OUT/stub/$3.c"
}
mkstub '^SDL_' libSDL2-2.0.so.0 libSDL2.so
mkstub '^gl[A-Z]' libGLESv2.so.2 libGLESv2.so
mkstub '^egl[A-Z]' libEGL.so.1 libEGL.so

# ---- glibc compatibility (as build_vm.sh): must start on ArkOS/dArkOS glibc ~2.28-2.30 ----
LINKCOMPAT=""
if [ "${GLIBC_COMPAT:-1}" = 1 ]; then
  CDIR="$OUT/compat"; mkdir -p "$CDIR"
  $CC -O2 -fno-builtin -fno-stack-protector -c "$ROOT/ports/r36s/compat/glibc_compat.c" -o "$CDIR/glibc_compat.o"
  $CC -c "$ROOT/ports/r36s/compat/compat_start.S" -o "$CDIR/compat_start.o"
  $CC -dumpspecs | awk '/^\*startfile:/{f=1;print;next} /^\*/{f=0} f&&NF' \
    | sed -E "s#([[:space:]]):crt1.o%s#\1:$CDIR/compat_start.o#" > "$CDIR/compat.specs"
  grep -q "compat_start.o" "$CDIR/compat.specs" || { echo "ERROR: could not build compat.specs"; exit 1; }
  LINKCOMPAT="-specs=$CDIR/compat.specs -static-libstdc++ -static-libgcc $CDIR/glibc_compat.o -Wl,--push-state,--no-as-needed -l:libpthread.so.0 -l:libdl.so.2 -l:librt.so.1 -Wl,--pop-state"
fi

echo "  LD nfsu1.aarch64"
$CXX -o "$OUT/nfsu1.aarch64.debug" "$OUT"/obj/*.o "$OUT"/guest/*.o -L"$OUT/stub" -lSDL2 -lGLESv2 -lpthread -ldl -lm -rdynamic -no-pie $LINKCOMPAT $LDEXTRA
cp "$OUT/nfsu1.aarch64.debug" "$OUT/nfsu1.aarch64"
${CROSS}strip --strip-debug "$OUT/nfsu1.aarch64"
${CROSS}objdump -p "$OUT/nfsu1.aarch64" | grep NEEDED
if [ "${GLIBC_COMPAT:-1}" = 1 ]; then
  BADV=$(${CROSS}readelf --dyn-syms -W "$OUT/nfsu1.aarch64" | awk '$7=="UND"{print $8}' | grep -oE '@(GLIBC_2\.(29|[3-9][0-9])|GLIBCXX|CXXABI)[A-Za-z0-9_.]*' | sort -u | tr '\n' ' ')
  [ -z "$BADV" ] || { echo "ERROR: imports too-new symbol versions: $BADV"; exit 1; }
fi
echo "built $OUT/nfsu1.aarch64"
