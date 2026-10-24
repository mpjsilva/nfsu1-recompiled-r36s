# Need for Speed: Underground (NFSU1) — R36S port

A static recompilation of **Need for Speed: Underground** (PC, `SPEED.EXE`, 2003) for the **R36S** and other
RK3326 handhelds. It runs on this repository's NFSU2 runtime: the game code is lifted from NFSU1's own
executable, and the Direct3D 9 → OpenGL ES 2.0 layer, input, audio and Windows API layer are shared with the
NFSU2 port. Build switch: `NFS_GAME_U1`.

Português: [LEIAME.md](LEIAME.md).

## Status

Playable end to end on an R36S: title, profile creation, menus, Quick Race (tested with Circuit), car and
track selection, and races with HUD, rivals and analog steering.

| | |
|---|---|
| Menus | 30 FPS (frame cap) |
| Races | about 15–19 FPS; the NFSU2 performance modules are not ported to NFSU1 yet |
| Sound effects | working (engine, tyres, menus) |
| Music | **through the port's own player** (your OGG/MP3 files, see below) |
| Ambient sound and speech | **missing**: the game's stream player never starts (open issue) |
| Picture | 4:3 only (no widescreen yet) |

Internal resolution: the menus render at 800×600 and are scaled to the 640×480 screen; when a race starts the
game resets the device to 640×480, drawn 1:1.

## What you need

No game files are included. Use your own PC copy of NFSU1.

* `SPEED.EXE`: 3,178,496 bytes, SHA-256
  `35654f401383be9af0dbff0d11a92220a17579a01030005de6943e63e03f460f`
  (MD5 `22c731fe0c0c41fe14ce80b728b6cbe0`). Other versions have their code at other addresses and will not run.
  If your copy names it `speed2.exe`, the launcher copies it to `speed.exe` on the first start.
* The game folders: `Global`, `Cars`, `Tracks`, `FrontEnd`, `Sound`, `SNDSTREAMS`, `SpeechStreams`,
  `Languages`, `Movies`, `fx`.

## Installation

```text
roms/ports/
├── NFSU1.sh                 launcher
└── nfsu1/
    ├── nfsu1.aarch64        the game (built with ports/r36s/build_nfsu1.sh)
    ├── nfsu1.cfg            settings
    ├── port.json            PortMaster metadata
    ├── music/
    │   ├── menu/            your music for the menus (.ogg / .mp3)
    │   └── race/            your music for races
    └── gamedata/            YOUR PC GAME FILES (SPEED.EXE, Global/, Cars/, Tracks/ …)
        └── NFS Underground/ save games (created by the game)
```

Installer leftovers (`setup/`, `AutoRun/`, `3DSetup/`, `SECDRV.SYS`, `DrvMgt.dll`, `nfscres.*` …) are not
used and can be deleted. Start the game from **Ports** in EmulationStation.

## Controls

Button names are the labels printed on the R36S. The pad sends the game's PC keyboard keys; steering is
analog through the left stick.

| Button | Race | Menus |
|---|---|---|
| Left stick | Steer (analog) | Navigate |
| D-pad | Enter / 1 / M / Tab keys | Navigate |
| **B** (bottom) | Accelerate | Confirm (Enter) |
| **Y** (left) | Brake / reverse | Space |
| **A** (right) | Handbrake | Back (Esc) |
| **X** (top) | Camera | Back (Esc) |
| **R1** | Nitrous | — |
| **L1** | Look back | — |
| **R2 / L2** | Shift up / down | — |
| **Start** | Pause | Confirm (Enter) |
| **Select** | Backspace | Backspace (Quit item; deletes a letter while typing) |
| **R3** | On-screen keyboard | On-screen keyboard (profile name) |
| **Select + R1** | Next music track | Next music track |
| **Select + R3** | Frame counter on/off | Frame counter on/off |
| **Select + Start** | Quit to the system menu | Quit to the system menu |

Select is sent when it is released, and not at all when it was part of a combo.

## Music

This port plays your own music, because the game's stream player does not work here yet (and many copies of
NFSU1 ship without the EA Trax streams). Put `.ogg` or `.mp3` files (any sample rate, mono or stereo) in:

* `nfsu1/music/menu/` — played in the menus;
* `nfsu1/music/race/` — played in races.

The list switches a few seconds after a race starts or ends (a pause menu does not switch it), with a short
fade-in, and each list continues where it stopped. When one folder is empty the other list is used.
**Select + R1** skips to the next track.

## Settings (`nfsu1/nfsu1.cfg`)

| Setting | Effect |
|---|---|
| `NFSU1_FPS=30` | Frame cap: 30 or 60 |
| `NFSU1_LANG=English` | English, Spanish, French, German, Italian, Dutch, Swedish |
| `NFSU1_MUSIC_VOLUME=70` | Music volume 0–100; 0 turns the player off |
| `NFSU1_MUSIC_SHUFFLE=1` | 1 random order, 0 by file name |
| `NFSU2_SHOW_FPS=1` | Frame counter from the start |

Graphics options are in the game's own Options menu (they are stored in the save profile).

## Troubleshooting

`nfsu1/log.txt` is the log of the last run, and `nfsu1/launcher.log` is the launcher's. The music player writes
`[NFSU1 MUSIC]` lines (tracks opened and, every 10 s, how much played); messages from the game's EA
audio/file library appear as `[NFSU1 EA]`.

## Building

The lift inputs for NFSU1 live in [`nfsu1/`](../../../nfsu1) at the repository root (seeds, `config/`, and the
`run_lift.py` that reads them); the build script is [`ports/r36s/build_nfsu1.sh`](../build_nfsu1.sh).

1. pcrecomp: [sp00nznet/pcrecomp](https://github.com/sp00nznet/pcrecomp) at `35548b8` with
   `patches/pcrecomp/*.patch` applied (`git am`).
2. Lift `SPEED.EXE` (Python 3, pcrecomp's tools):
   ```sh
   export PCRECOMP=/path/to/pcrecomp
   python3 nfsu1/scripts/run_lift.py catalog SPEED.EXE nfsu1/seeds.json catalog.json
   python3 nfsu1/scripts/run_lift.py lift SPEED.EXE catalog.json gen
   ```
3. A compile tree: a copy of the patched pcrecomp whose `runtime/recomp32` and `runtime/win32hle` are replaced
   by `ports/r36s/sdk/include/recomp32` and `ports/r36s/sdk/include/win32hle`.
4. Cross-build in an Ubuntu 22.04 container with `g++-aarch64-linux-gnu` and `python3`:
   ```sh
   ROOT=$PWD PCRECOMP=/path/to/compile-tree GEN=/path/to/gen OUT=/path/to/out \
     bash ports/r36s/build_nfsu1.sh
   ```
   The result is `out/nfsu1.aarch64` (and `nfsu1.aarch64.debug` with symbols). A full build takes a few
   minutes on a many-core x86_64 machine; the lifted code is about 22,000 functions.

The music player uses [stb_vorbis](https://github.com/nothings/stb) 1.22 and
[dr_mp3](https://github.com/mackron/dr_libs) 0.7.3 (public domain / MIT-0), in `ports/r36s/third_party/`.
