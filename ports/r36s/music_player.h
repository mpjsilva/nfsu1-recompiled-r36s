#pragma once
// Host music player (NFSU1 build): the user's OGG/MP3 files from music/menu and music/race. See music_player.cpp.
#include <string>

void musicStart(const std::string& gameDir);
void musicStop();
void musicSetRace(bool race);   // every frame: whether the game is in a race
void musicNext();               // skip to the next track of the playing list
extern "C" void nfsHostMusicMix(float* out, unsigned frames, unsigned rate);
