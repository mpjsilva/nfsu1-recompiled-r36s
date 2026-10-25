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

# ---------------------------------------------------------------------------
# Pre-game menu (one script, like the Daytona port): remap the driving controls, back up / restore the save
# to this folder, or change settings, then start the game. It runs on the console (tty1) with the pad acting
# as the keyboard through gptokeyb, as the dArkOS tools do (A = choose, B = back). The controls go to
# controls.cfg (the binary reads it through NFSU1_CONTROLS) and the settings to nfsu1.cfg (sourced below).
# NFSU1_NO_MENU=1 skips the menu and starts the game with the last choices.
# ---------------------------------------------------------------------------
SAVEDIR="$GAMEDIR/gamedata/NFS Underground"
CFG="$GAMEDIR/nfsu1.cfg"
CONTROLS="$GAMEDIR/controls.cfg"

dlg() { dialog --clear --colors --no-collapse --backtitle "NFS Underground - R36S" "$@" 2>&1 >"$CURR_TTY" <"$CURR_TTY"; }

# The menu drives dialog with the pad as a keyboard through gptokeyb (A = enter, B = esc). Capturing a raw
# button needs the pad free, so these start / stop gptokeyb around a capture.
MENU_KEYS=/tmp/nfsu1-keys.gptk
MENU_GPTK=""
menu_pad_on() {
  [ -x /opt/inttools/gptokeyb ] && [ -f /opt/inttools/keys.gptk ] || return 0
  cp /opt/inttools/keys.gptk "$MENU_KEYS"; sed -i 's/^a = .*/a = enter/; s/^b = .*/b = esc/' "$MENU_KEYS"
  pkill -9 -f gptokeyb 2>/dev/null
  SDL_GAMECONTROLLERCONFIG_FILE=/opt/inttools/gamecontrollerdb.txt /opt/inttools/gptokeyb -1 "dialog" -c "$MENU_KEYS" >/dev/null 2>&1 &
  MENU_GPTK=$!
}
menu_pad_off() {
  [ -n "$MENU_GPTK" ] && { kill -9 "$MENU_GPTK" 2>/dev/null; wait "$MENU_GPTK" 2>/dev/null; MENU_GPTK=""; }
  pkill -9 -f gptokeyb 2>/dev/null
}
# A stored button label shown as its position, so it reads the same whatever the A/B letters are swapped to.
btn_face() {
  case "$1" in
    B) echo "baixo" ;; A) echo "direita" ;; Y) echo "esquerda" ;; X) echo "cima" ;;
    *) echo "$1" ;;
  esac
}

# controls.cfg: action=BUTTON lines, physical R36S labels (absent = original layout).
ctl_get() { local v=""; [ -f "$CONTROLS" ] && v=$(grep -iE "^$1=" "$CONTROLS" | tail -1 | cut -d= -f2 | tr -d ' \r'); echo "${v:-$2}"; }
ctl_set() { touch "$CONTROLS"; grep -ivE "^$1=" "$CONTROLS" > "$CONTROLS.tmp" 2>/dev/null; mv "$CONTROLS.tmp" "$CONTROLS"; echo "$1=$2" >> "$CONTROLS"; }

pick_button() {  # action label current
  # Capture the physical button the player presses, read through the game's own SDL layer (./nfsu1.aarch64
  # --read-button). The menu's gptokeyb must release the pad first, then it is restored.
  local got
  menu_pad_off
  # infobox without --clear so the prompt stays on screen during the 15 s capture window.
  dialog --colors --no-collapse --backtitle "NFS Underground - R36S" --title " $2 " \
    --infobox "\nAperte agora o botao para:\n\n   $2\n\n(atual: $(btn_face "$3"))\n\nAguardando o botao..." 11 48 >"$CURR_TTY" <"$CURR_TTY"
  got=$(cd "$GAMEDIR" && ./nfsu1.aarch64 --read-button 2>/dev/null | sed -n 's/^BUTTON=//p' | tail -1)
  menu_pad_on
  case "$got" in
    A|B|X|Y|L1|R1|L2|R2) ctl_set "$1" "$got"; dlg --title " $2 " --msgbox "\n$2 = botao $(btn_face "$got")" 7 44 ;;
    *) dlg --title " $2 " --msgbox "\nNenhum botao detectado (tempo esgotado).\nMantido: $(btn_face "$3")" 8 48 ;;
  esac
}

controls_menu() {
  local a b h cam n l gu gd sel C s
  while true; do
    a=$(ctl_get accelerate B); b=$(ctl_get brake Y); h=$(ctl_get handbrake A); cam=$(ctl_get camera X)
    n=$(ctl_get nitro R1); l=$(ctl_get lookback L1); gu=$(ctl_get gearup R2); gd=$(ctl_get geardown L2)
    sel=$(ctl_get select BACKSPACE)
    C=$(dlg --title " Controles (corrida) " --ok-label "Editar" --cancel-label "Voltar" --default-item "${CITEM:-1}" \
        --menu "\nA: editar   B: voltar   (direcao = analogico esquerdo)" 20 54 10 \
        1 "Acelerar .......... $(btn_face "$a")" 2 "Frear / re ........ $(btn_face "$b")" 3 "Freio de mao ...... $(btn_face "$h")" \
        4 "Camera ............ $(btn_face "$cam")" 5 "Nitro ............. $(btn_face "$n")" 6 "Olhar para tras ... $(btn_face "$l")" \
        7 "Subir marcha ...... $(btn_face "$gu")" 8 "Descer marcha ..... $(btn_face "$gd")" 9 "Select = $sel" \
        0 "Restaurar padrao") || break
    CITEM="$C"
    case "$C" in
      1) pick_button accelerate "Acelerar" "$a" ;;
      2) pick_button brake "Frear / re" "$b" ;;
      3) pick_button handbrake "Freio de mao" "$h" ;;
      4) pick_button camera "Camera" "$cam" ;;
      5) pick_button nitro "Nitro" "$n" ;;
      6) pick_button lookback "Olhar para tras" "$l" ;;
      7) pick_button gearup "Subir marcha" "$gu" ;;
      8) pick_button geardown "Descer marcha" "$gd" ;;
      9) s=$(dlg --title " Select " --ok-label "OK" --cancel-label "Voltar" --menu "\nO botao Select na corrida:" 12 46 3 \
            BACKSPACE "Backspace (abandonar)" RESET "Resetar carro (R)" NONE "Nada") && ctl_set select "$s" ;;
      0) rm -f "$CONTROLS"; dlg --title " Controles " --msgbox "\nLayout padrao restaurado." 7 40 ;;
    esac
  done
}

export_save() {
  if [ ! -d "$SAVEDIR" ]; then dlg --title " Exportar save " --msgbox "\nNenhum save ainda.\n(Jogue uma vez para criar o perfil.)" 8 46; return; fi
  local zip="$GAMEDIR/NFSU1-save-$(date +%Y%m%d-%H%M%S).zip"
  ( cd "$GAMEDIR/gamedata" && zip -r -q "$zip" "NFS Underground" ) \
    && dlg --title " Exportar save " --msgbox "\nSave exportado para a pasta do port:\n\n$(basename "$zip")" 9 54 \
    || dlg --title " Exportar save " --msgbox "\nFalha ao exportar o save." 7 40
}

import_save() {
  local zip
  zip=$(ls -1t "$GAMEDIR"/NFSU1-save-*.zip 2>/dev/null | head -1)
  if [ -z "$zip" ]; then dlg --title " Importar save " --msgbox "\nNenhum NFSU1-save-*.zip nesta pasta para importar." 8 50; return; fi
  dlg --title " Importar save " --defaultno --yesno "\nRestaurar o save a partir de:\n$(basename "$zip")\n\nIsto substitui o save atual. Continuar?" 11 54 || return
  rm -rf "$SAVEDIR"
  ( cd "$GAMEDIR/gamedata" && unzip -o -q "$zip" ) \
    && dlg --title " Importar save " --msgbox "\nSave restaurado." 7 40 \
    || dlg --title " Importar save " --msgbox "\nFalha ao importar o save." 7 40
}

# nfsu1.cfg: shell assignments, sourced by this launcher below.
cfg_get() { local v=""; [ -f "$CFG" ] && v=$(grep -iE "^$1=" "$CFG" | tail -1 | cut -d= -f2 | tr -d ' \r'); echo "${v:-$2}"; }
cfg_set() { touch "$CFG"; grep -ivE "^$1=" "$CFG" > "$CFG.tmp" 2>/dev/null; mv "$CFG.tmp" "$CFG"; echo "$1=$2" >> "$CFG"; }

settings_menu() {
  local fps lang vol shuf shuflbl C g v
  while true; do
    fps=$(cfg_get NFSU1_FPS 30); lang=$(cfg_get NFSU1_LANG English); vol=$(cfg_get NFSU1_MUSIC_VOLUME 70)
    shuf=$(cfg_get NFSU1_MUSIC_SHUFFLE 1); [ "$shuf" = 0 ] && shuflbl="em ordem" || shuflbl="aleatoria"
    C=$(dlg --title " Configuracoes " --ok-label "Alterar" --cancel-label "Voltar" --default-item "${SITEM:-1}" \
        --menu "\nA: alterar   B: voltar" 14 54 5 \
        1 "Limite de FPS ...... $fps" 2 "Idioma ............. $lang" 3 "Volume da musica ... $vol" \
        4 "Ordem das musicas .. $shuflbl") || break
    SITEM="$C"
    case "$C" in
      1) [ "$fps" = 30 ] && cfg_set NFSU1_FPS 60 || cfg_set NFSU1_FPS 30 ;;
      2) g=$(dlg --title " Idioma " --menu "" 15 40 7 English English Spanish Spanish French French German German Italian Italian Dutch Dutch Swedish Swedish) && cfg_set NFSU1_LANG "$g" ;;
      3) v=$(dlg --title " Volume da musica " --menu "\n0 desliga o player" 14 40 6 0 "0%" 30 "30%" 50 "50%" 70 "70%" 85 "85%" 100 "100%") && cfg_set NFSU1_MUSIC_VOLUME "$v" ;;
      4) [ "$shuf" = 0 ] && cfg_set NFSU1_MUSIC_SHUFFLE 1 || cfg_set NFSU1_MUSIC_SHUFFLE 0 ;;
    esac
  done
}

# Credits: everyone this port is built on. Shown in a scrollable box (d-pad scrolls, A/B closes).
credits_screen() {
  local f=/tmp/nfsu1-credits.txt
  cat > "$f" <<'EOF'
Need for Speed: Underground - port para R36S

Port do NFSU1 e este launcher:
  mpjsilva
  github.com/mpjsilva/nfsu1-recompiled-r36s

Runtime e recompilacao do NFSU2 (a base deste port):
  manuelpllull
  github.com/manuelpllull/nfsu2-recompiled-r36s

Recompilador estatico pcrecomp:
  sp00nznet
  github.com/sp00nznet/pcrecomp

Port NFSU1 independente do fera89 - o soundtrack
completo (EA Trax) e a documentacao de controles
ajudaram nas correcoes deste port:
  fera89
  github.com/fera89/nfsu1-recompiled-r36s

Bibliotecas:
  stb_vorbis - Sean Barrett (nothings/stb)
  dr_mp3 - David Reid (mackron/dr_libs)
  MojoShader - Ryan C. Gordon
  fonte DejaVu (bitmap do overlay/teclado)

Need for Speed: Underground (c) Electronic Arts.
Port feito por fas; use a sua propria copia do jogo.

Obrigado a todos que tornaram este port possivel!
EOF
  dialog --colors --no-collapse --backtitle "NFS Underground - R36S" --title " Creditos " \
    --exit-label "Voltar" --textbox "$f" 20 56 >"$CURR_TTY" <"$CURR_TTY"
  rm -f "$f"
}

# The menu itself: sets up the console + pad, loops, and cleans up. Returns 0 to start the game, 1 to quit.
pre_menu() {
  local C RC START=0
  [ -e "$CURR_TTY" ] || return 0
  sudo chmod 666 "$CURR_TTY" /dev/uinput 2>/dev/null
  export TERM=linux LANG=en_US.UTF-8
  sudo setfont /usr/share/consolefonts/Lat15-TerminusBold22x11.psf.gz 2>/dev/null
  printf '\033%%G\033[?25l\033[H\033[2J' > "$CURR_TTY"
  [ -f /opt/inttools/noshadows.dialogrc ] && export DIALOGRC=/opt/inttools/noshadows.dialogrc
  menu_pad_on
  while true; do
    C=$(dlg --title " NFS Underground " --ok-label "OK" --cancel-label "Sair" --default-item "${MITEM:-1}" \
        --menu "\nA: escolher   B: sair" 16 52 6 \
        1 "Iniciar o jogo" 2 "Controles" 3 "Exportar save (backup)" \
        4 "Importar save (restaurar)" 5 "Configuracoes" 6 "Creditos"); RC=$?
    [ $RC -ne 0 ] && break
    MITEM="$C"
    case "$C" in
      1) START=1; break ;;
      2) controls_menu ;;
      3) export_save ;;
      4) import_save ;;
      5) settings_menu ;;
      6) credits_screen ;;
    esac
  done
  menu_pad_off
  rm -f "$MENU_KEYS"
  printf '\033[H\033[2J\033[?25h' > "$CURR_TTY"
  [ "$START" = 1 ] || return 1
  return 0
}

if [ -z "${NFSU1_NO_MENU:-}" ]; then
  pre_menu || exit 0
fi

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
# Gamepad button -> action remap written by "NFSU1 Config" (absent = original layout).
[ -f "$GAMEDIR/controls.cfg" ] && export NFSU1_CONTROLS="$GAMEDIR/controls.cfg"
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

# Return to the EmulationStation ports menu. The front end launches this script and waits, but the game
# held the display through KMSDRM, so on some firmware it comes back to a blank console instead of redrawing
# its menu. Restarting the front end guarantees the ports list is shown. The restart runs in its own
# transient scope (systemd-run) so it survives the front end's process group being torn down, and the short
# delay lets this script exit first; the plain restart is a fallback when systemd-run is unavailable.
if systemctl list-unit-files emulationstation.service >/dev/null 2>&1; then
  if command -v systemd-run >/dev/null 2>&1; then
    sudo systemd-run --collect --quiet --unit="nfsu1-return-$$" \
      /bin/sh -c 'sleep 1; systemctl restart emulationstation' >/dev/null 2>&1 \
      || ( sleep 1; sudo systemctl restart emulationstation >/dev/null 2>&1 & )
  else
    ( sleep 1; sudo systemctl restart emulationstation >/dev/null 2>&1 & )
  fi
fi
exit $EXIT_CODE
