#!/bin/bash
# PortMaster Launch Script for Need for Speed: Underground (NFSU1, Recompiled)
# Built from the NFSU2 port: same runtime, lifted from NFSU1's own SPEED.EXE (nfsu1.aarch64).
# Target Devices: R36S, RG351MP, RGB20S, RK2020 (Rockchip RK3326 ARM64)
# Supported OS: ArkOS, AmberELEC, ROCKNIX, TheRA

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

# PortMaster is optional: a fresh dArkOS has it only after Tools > Install.PortMaster. Without it the
# game still starts (the binary reads the pad through SDL itself; nothing here needs gptokeyb).
if [ -f "$controlfolder/control.txt" ]; then
  source "$controlfolder/control.txt"
  [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
  get_controls
fi
ESUDO="${ESUDO:-sudo}"

CURR_TTY="/dev/tty1"
exec < "$CURR_TTY"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -n "$directory" ] && [ -d "/$directory/ports/nfsu1" ]; then
  GAMEDIR="/$directory/ports/nfsu1"
else
  GAMEDIR="$SCRIPT_DIR/nfsu1"
fi
cd "$GAMEDIR"

# Per-run diagnostics: timestamped logs/ folder, console tee, kernel log and exit code on exit.
[ -f "$GAMEDIR/port-diagnostics.sh" ] && source "$GAMEDIR/port-diagnostics.sh"

# Binary update delivered in parts (the build host can only write files of up to 30 MB to the card): join
# nfsu1.aarch64.partNN, check the result against nfsu1.aarch64.update.sha1, then replace the binary. On a
# checksum failure the parts are kept and the old binary runs. The result goes to update.log.
if [ -f nfsu1.aarch64.update.sha1 ] && ls nfsu1.aarch64.part* >/dev/null 2>&1; then
  cat nfsu1.aarch64.part* > nfsu1.aarch64.new
  if [ "$(sha1sum nfsu1.aarch64.new | cut -d' ' -f1)" = "$(tr -d ' \n\r' < nfsu1.aarch64.update.sha1)" ]; then
    chmod 755 nfsu1.aarch64.new; mv -f nfsu1.aarch64.new nfsu1.aarch64
    rm -f nfsu1.aarch64.part* nfsu1.aarch64.update.sha1 ._nfsu1.aarch64.part* ._nfsu1.aarch64.update.sha1
    echo "updated nfsu1.aarch64 ($(date)): $(sha1sum nfsu1.aarch64)" > update.log
  else
    rm -f nfsu1.aarch64.new
    echo "update parts failed the checksum ($(date)); kept the old binary" > update.log
  fi
  sync
fi

export DEVICE_ARCH="aarch64"
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
[ -n "$sdl_controllerconfig" ] && export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# R36S Mali-G31 ArkOS driver bindings
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export ALSOFT_DRIVERS=alsa
export SDL_VIDEO_GL_DRIVER=libGLESv2.so
export SDL_VIDEO_EGL_DRIVER=libEGL.so
export MESA_GL_VERSION_OVERRIDE=2.1
export MESA_GLES_VERSION_OVERRIDE=2.0
export MALLOC_CHECK_=0

# Clocks: CPU, GPU (Mali) and memory controller (DMC) at their top step while the game runs. The RK3326
# devfreq governors otherwise keep the GPU and DRAM clocks low, and this game is bound by CPU and memory.
# The previous governors are restored on exit.
SUDO="${ESUDO:-sudo}"
CLOCK_STATE=""
for gov in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor \
           /sys/class/devfreq/*/governor; do
  [ -f "$gov" ] || continue
  old=$(cat "$gov" 2>/dev/null)
  echo performance | $SUDO tee "$gov" > /dev/null 2>&1 && CLOCK_STATE="$CLOCK_STATE $gov=$old"
done
restore_clocks() {
  for entry in $CLOCK_STATE; do
    echo "${entry#*=}" | $SUDO tee "${entry%%=*}" > /dev/null 2>&1 || true
  done
}
trap 'PORT_EXIT=$?; restore_clocks; command -v port_collect_exit >/dev/null 2>&1 && port_collect_exit "$PORT_EXIT"' EXIT

# R36S 1GB RAM Protection:
# Free reclaimable page caches to maximize contiguous memory before launching
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

# Ensure safety swapfile to prevent OOM Killer from terminating the game during high texture loads
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
if [ -z "$SWAP_TOTAL" ] || [ "$SWAP_TOTAL" -lt 256 ]; then
  echo "[PortMaster] Ensuring 512MB safety swap on SD card..."
  if [ ! -f "$GAMEDIR/.swapfile" ]; then
    dd if=/dev/zero of="$GAMEDIR/.swapfile" bs=1M count=512 status=none
    mkswap "$GAMEDIR/.swapfile" >/dev/null 2>&1
  fi
  sudo swapon "$GAMEDIR/.swapfile" >/dev/null 2>&1
fi

# Verify game assets presence. NFSU1's executable is SPEED.EXE; some repacks rename it speed2.exe, so a
# copy under the right name is made once (the binary checks the PE layout, so another game's exe is refused).
if [ ! -f "$GAMEDIR/gamedata/SPEED.EXE" ] && [ ! -f "$GAMEDIR/gamedata/speed.exe" ]; then
  for alt in speed2.exe SPEED2.EXE; do
    [ -f "$GAMEDIR/gamedata/$alt" ] && { cp "$GAMEDIR/gamedata/$alt" "$GAMEDIR/gamedata/speed.exe"; sync; break; }
  done
fi
if [ ! -f "$GAMEDIR/gamedata/SPEED.EXE" ] && [ ! -f "$GAMEDIR/gamedata/speed.exe" ]; then
  printf "\033c" > "$CURR_TTY"
  printf "======================================================================\n" > "$CURR_TTY"
  printf " ERROR: Game assets not found!\n" > "$CURR_TTY"
  printf " Please copy your PC Need for Speed Underground files into:\n" > "$CURR_TTY"
  printf "   %s/gamedata/\n" "$GAMEDIR" > "$CURR_TTY"
  printf " Required files: SPEED.EXE, Global/, Cars/, Tracks/, FrontEnd/, Sound/, etc.\n" > "$CURR_TTY"
  printf "======================================================================\n" > "$CURR_TTY"
  sleep 5
  exit 1
fi

# Unbind vtconsole to allow KMSDRM full access to DRM primary plane
printf "\033c" > "$CURR_TTY" 2>/dev/null || true
printf "\e[?25l" > "$CURR_TTY" 2>/dev/null || true
echo 0 | sudo tee /sys/class/vtconsole/vtcon0/bind > /dev/null 2>&1 || true
echo 0 | sudo tee /sys/class/vtconsole/vtcon1/bind > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Settings, overridable in "$GAMEDIR/nfsu1.cfg":
#   NFSU1_FPS=30|60       frame cap
#   NFSU1_LANG=English    English | Spanish | French | German | Italian | Dutch | Swedish
#   NFSU2_SHOW_FPS=1      frame counter on from the start (Select + R3 toggles it in game)
#   NFSU1_MUSIC_VOLUME=70 music player volume 0-100 (0 = off); Select + R1 skips the track
#   NFSU1_MUSIC_SHUFFLE=1 1 random order, 0 by file name
# NFSU1 keeps its graphics options in the save profile (in-game Options menu), not in the registry, so
# there is no graphics profile here. Widescreen is not ported to NFSU1 yet: the game always renders 4:3.
# ---------------------------------------------------------------------------
NFSU1_FPS=30
NFSU1_LANG=English
NFSU1_MUSIC_VOLUME=70
NFSU1_MUSIC_SHUFFLE=1
[ -f "$GAMEDIR/nfsu1.cfg" ] && . "$GAMEDIR/nfsu1.cfg"
# The port's own music player: OGG/MP3 files in music/menu (front end) and music/race (races).
mkdir -p "$GAMEDIR/music/menu" "$GAMEDIR/music/race"
export NFSU1_MUSIC_DIR="$GAMEDIR/music" NFSU1_MUSIC_VOLUME NFSU1_MUSIC_SHUFFLE
export NFSU2_ASPECT=4:3
[ -n "${NFSU2_SHOW_FPS:-}" ] && export NFSU2_SHOW_FPS
CAP_ARG="--cap60"; [ "$NFSU1_FPS" = "30" ] && CAP_ARG="--cap30"

# Record the clocks actually in effect (launcher.log next to log.txt)
{
  echo "[launcher] nfsu1 fps=$NFSU1_FPS lang=$NFSU1_LANG"
  # What this kernel offers for GPU load (read by the binary for its [NFSU2 GPU] log line)
  for d in /sys/class/devfreq/*; do [ -d "$d" ] && echo "[launcher] devfreq $d: $(ls "$d" 2>/dev/null | tr '\n' ' ')"; done
  for f in /sys/devices/platform/*gpu*/utilisation /sys/class/misc/mali0/device/utilisation; do
    [ -f "$f" ] && echo "[launcher] $f = $(cat "$f" 2>/dev/null)"
  done
  ls -d /sys/devices/platform/*gpu* 2>/dev/null | sed 's/^/[launcher] gpu device /'
  for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq /sys/class/devfreq/*/cur_freq; do
    [ -f "$f" ] && echo "[launcher] $f = $(cat "$f" 2>/dev/null) ($(cat "$(dirname "$f")/governor" 2>/dev/null || cat "$(dirname "$f")/scaling_governor" 2>/dev/null))"
  done
  free -m
  uname -a
  for f in /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/defrag /sys/kernel/mm/transparent_hugepage/hpage_pmd_size; do
    [ -f "$f" ] && echo "[launcher] $f = $(cat "$f" 2>/dev/null)"
  done
  grep -i huge /proc/meminfo
} > "$GAMEDIR/launcher.log" 2>&1

# Keep the previous run's log (a crash on one run is otherwise overwritten by the next launch)
[ -f "$GAMEDIR/log.txt" ] && mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt"

# GPTOKEYB: START + SELECT exit shortcut; no custom nfsu1.gptk mapping.
if [ -n "${GPTOKEYB:-}" ]; then
  $GPTOKEYB "nfsu1.aarch64" -k &
fi

# Native crash reporter (LD_PRELOAD): writes signal, PC and a backtrace to log.txt and nfs-crash.log.
export NFS_CRASH_DIR="$GAMEDIR"
CRASH_PRELOAD=""
[ -f "$GAMEDIR/libnfs-crash.so" ] && CRASH_PRELOAD="$GAMEDIR/libnfs-crash.so"

# Launch game: GLES 2.0 at the screen's native resolution (see Display above)
LANG_ARG="--lang=$NFSU1_LANG"
LD_PRELOAD="${CRASH_PRELOAD}${CRASH_PRELOAD:+${LD_PRELOAD:+:}}${LD_PRELOAD}" \
  ./nfsu1.aarch64 "$GAMEDIR/gamedata" $CAP_ARG $LANG_ARG > "$GAMEDIR/log.txt" 2>&1
EXIT_CODE=$?

# Restore console and services on exit
echo 1 | sudo tee /sys/class/vtconsole/vtcon0/bind > /dev/null 2>&1 || true
echo 1 | sudo tee /sys/class/vtconsole/vtcon1/bind > /dev/null 2>&1 || true
$ESUDO systemctl restart oga_events >/dev/null 2>&1 &
printf "\033c" > "$CURR_TTY" 2>/dev/null || true
printf "\e[?25h" > "$CURR_TTY" 2>/dev/null || true
exit $EXIT_CODE
