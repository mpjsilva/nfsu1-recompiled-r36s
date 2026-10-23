// Which game the lifted code is: SPEED2.EXE (Underground 2, default) or SPEED.EXE (Underground, NFS_GAME_U1).
// The guest still sees its install folder as C:\\nfsu2 in both cases; only names the game itself checks differ.
#pragma once
#if defined(NFS_GAME_U1)
#define NFS_GUEST_EXE "SPEED.EXE"
#define NFS_GUEST_EXE_LOWER "speed.exe"
#define NFS_PORT_DIR "nfsu1"
#define NFS_GAME_TITLE "Need for Speed: Underground"
#define NFS_REGISTRY_KEY_A "software\\ea games\\need for speed underground"
#define NFS_REGISTRY_KEY_B "software\\ea games\\nfs underground"
#else
#define NFS_GUEST_EXE "SPEED2.EXE"
#define NFS_GUEST_EXE_LOWER "speed2.exe"
#define NFS_PORT_DIR "nfsu2"
#define NFS_GAME_TITLE "Need for Speed: Underground 2"
#define NFS_REGISTRY_KEY_A "software\\ea games\\need for speed underground 2"
#define NFS_REGISTRY_KEY_B "software\\electronic arts\\ea games\\need for speed underground 2"
#endif
