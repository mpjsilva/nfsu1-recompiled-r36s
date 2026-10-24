// Host music player for the NFSU1 build: plays the user's own OGG/MP3 files next to the game's sound effects.
// This copy of NFSU1 has no usable EA Trax stream and the game's stream player never starts (see HANDOFF), so the
// music comes from two folders instead: music/menu (front end) and music/race (in a race, decided by the game's
// driving key map, held for a few seconds so a pause menu does not swap the list). Each list keeps its place
// when the other one plays.
//
// A decoder thread fills a ring of stereo float frames at the device rate; the SDL audio callback adds the ring
// to the game's mix (nfsHostMusicMix, called from guest_audio.inc). Settings from the environment (NFSU1.sh):
//   NFSU1_MUSIC_DIR     folder holding menu/ and race/ (default: <game folder>/../music)
//   NFSU1_MUSIC_VOLUME  0-100, 0 turns the player off (default 70)
//   NFSU1_MUSIC_SHUFFLE 1 random order (default), 0 by file name
#include "music_player.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#define STB_VORBIS_NO_PUSHDATA_API
#include "third_party/stb_vorbis.c"
#undef L
#undef C
#undef R
#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO_WIDE
#include "third_party/dr_mp3.h"

namespace {

// One open file, decoded to interleaved stereo float at its own rate.
struct Decoder {
    stb_vorbis* ogg = nullptr;
    drmp3 mp3{};
    bool mp3Open = false;
    unsigned rate = 0, channels = 0;
    std::vector<float> scratch;

    bool open(const std::filesystem::path& path) {
        close();
        std::string ext = path.extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return char(std::tolower(c)); });
        if (ext == ".ogg") {
            int error = 0;
            ogg = stb_vorbis_open_filename(path.c_str(), &error, nullptr);
            if (!ogg) return false;
            const stb_vorbis_info info = stb_vorbis_get_info(ogg);
            rate = info.sample_rate; channels = unsigned(info.channels);
        } else {
            if (!drmp3_init_file(&mp3, path.c_str(), nullptr)) return false;
            mp3Open = true; rate = mp3.sampleRate; channels = mp3.channels;
        }
        if (!rate || !channels) { close(); return false; }
        return true;
    }
    void close() {
        if (ogg) stb_vorbis_close(ogg);
        if (mp3Open) drmp3_uninit(&mp3);
        ogg = nullptr; mp3Open = false; rate = channels = 0;
    }
    // Up to `frames` stereo frames into out; 0 at the end of the file.
    unsigned read(float* out, unsigned frames) {
        if (ogg) return unsigned(stb_vorbis_get_samples_float_interleaved(ogg, 2, out, int(frames * 2)));
        if (!mp3Open) return 0;
        scratch.resize(size_t(frames) * channels);
        const unsigned got = unsigned(drmp3_read_pcm_frames_f32(&mp3, frames, scratch.data()));
        for (unsigned i = 0; i < got; ++i) {
            const float l = scratch[size_t(i) * channels], r = channels > 1 ? scratch[size_t(i) * channels + 1] : l;
            out[2 * i] = l; out[2 * i + 1] = r;
        }
        return got;
    }
};

struct Playlist {
    const char* name;
    std::vector<std::filesystem::path> files;
    std::vector<size_t> order;
    size_t position = 0;
    Decoder decoder;
    bool playing = false;   // decoder holds the current track
    bool started = false;   // a track was opened before: the next open advances
    // Linear resampler state (source frames between the last two read).
    float prev[2] = {0, 0}, next[2] = {0, 0};
    double phase = 1.0;
    std::vector<float> chunk;
    unsigned chunkPos = 0, chunkLen = 0;
};

constexpr unsigned kRingFrames = 1 << 16;         // ~1.5 s at 44.1 kHz
std::vector<float> g_ring(size_t(kRingFrames) * 2);
std::atomic<uint64_t> g_write{0}, g_read{0};      // frame counters
std::atomic<unsigned> g_rate{0};                  // device rate, known from the first callback
std::atomic<bool> g_flush{false};                 // consumer drops what is buffered (list switch / skip)
std::atomic<bool> g_wantRace{false}, g_skip{false}, g_stop{false};
std::atomic<float> g_volume{0.7f};
float g_fade = 1.0f;                              // callback only
std::atomic<uint64_t> g_mixed{0}, g_starved{0};   // frames added / frames the ring could not supply
std::atomic<float> g_peak{0};
std::thread g_thread;
bool g_shuffle = true;
std::mt19937 g_rng{std::random_device{}()};
Playlist g_lists[2] = {{"menu"}, {"race"}};

void reorder(Playlist& list) {
    list.order.resize(list.files.size());
    for (size_t i = 0; i < list.order.size(); ++i) list.order[i] = i;
    if (g_shuffle) std::shuffle(list.order.begin(), list.order.end(), g_rng);
    list.position = 0;
}

std::vector<std::filesystem::path> scan(const std::filesystem::path& dir) {
    std::vector<std::filesystem::path> files;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(dir, error)) {
        if (!entry.is_regular_file(error)) continue;
        std::string ext = entry.path().extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return char(std::tolower(c)); });
        if (ext == ".ogg" || ext == ".mp3") files.push_back(entry.path());
    }
    std::sort(files.begin(), files.end());
    return files;
}

// Opens the list's next track that decodes; false when none does.
bool openNext(Playlist& list, bool advance) {
    for (size_t tries = 0; tries < list.files.size(); ++tries) {
        if (advance && ++list.position >= list.order.size()) reorder(list);
        advance = true;
        const auto& path = list.files[list.order[list.position]];
        if (list.decoder.open(path)) {
            std::printf("[NFSU1 MUSIC] %s %zu/%zu: %s (%u Hz, %u ch)\n", list.name, list.position + 1, list.files.size(),
                        path.filename().c_str(), list.decoder.rate, list.decoder.channels);
            list.playing = list.started = true; list.phase = 1.0; list.chunkPos = list.chunkLen = 0;
            return true;
        }
        std::printf("[NFSU1 MUSIC] cannot decode %s, skipped\n", path.c_str());
    }
    list.playing = false;
    return false;
}

// One source frame of the list into f[2]; false when the list has nothing playable.
bool sourceFrame(Playlist& list, float f[2]) {
    for (int attempt = 0; attempt < 3; ++attempt) {
        if (!list.playing && !openNext(list, list.started)) return false;
        if (list.chunkPos < list.chunkLen) { f[0] = list.chunk[2 * list.chunkPos]; f[1] = list.chunk[2 * list.chunkPos + 1]; ++list.chunkPos; return true; }
        list.chunk.resize(2048 * 2);
        list.chunkLen = list.decoder.read(list.chunk.data(), 2048);
        list.chunkPos = 0;
        if (!list.chunkLen) { list.decoder.close(); list.playing = false; }  // end of track: the next one opens
    }
    return false;
}

Playlist* activeList() {
    Playlist& wanted = g_lists[g_wantRace.load() ? 1 : 0];
    if (!wanted.files.empty()) return &wanted;
    Playlist& other = g_lists[g_wantRace.load() ? 0 : 1];   // an empty list borrows the other one
    return other.files.empty() ? nullptr : &other;
}

void decoderThread() {
    Playlist* current = nullptr;
    while (!g_stop.load()) {
        const unsigned rate = g_rate.load();
        Playlist* list = activeList();
        if (list != current || g_skip.exchange(false)) {
            if (list == current && list) { list->decoder.close(); list->playing = false; }
            current = list;
            g_flush = true;
            while (g_flush.load() && !g_stop.load()) std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        const uint64_t w = g_write.load(), r = g_read.load();
        if (!rate || !list || w - r > kRingFrames / 2) { std::this_thread::sleep_for(std::chrono::milliseconds(20)); continue; }
        // Fill up to 4096 frames, resampled from the track rate to the device rate.
        unsigned produced = 0;
        while (produced < 4096 && g_write.load() - g_read.load() < kRingFrames - 1) {
            const double step = double(list->decoder.rate ? list->decoder.rate : rate) / rate;
            while (list->phase >= 1.0) {
                list->prev[0] = list->next[0]; list->prev[1] = list->next[1];
                if (!sourceFrame(*list, list->next)) { list = nullptr; break; }
                list->phase -= 1.0;
            }
            if (!list) break;
            const float t = float(list->phase);
            const uint64_t at = g_write.load() % kRingFrames;
            g_ring[2 * at] = list->prev[0] + (list->next[0] - list->prev[0]) * t;
            g_ring[2 * at + 1] = list->prev[1] + (list->next[1] - list->prev[1]) * t;
            g_write.fetch_add(1);
            list->phase += step;
            ++produced;
        }
        if (!produced) std::this_thread::sleep_for(std::chrono::milliseconds(20));   // nothing decodable
    }
}

}  // namespace

void musicStart(const std::string& gameDir) {
    const char* volume = std::getenv("NFSU1_MUSIC_VOLUME");
    const int percent = volume ? std::atoi(volume) : 70;
    if (percent <= 0) { std::printf("[NFSU1 MUSIC] off (NFSU1_MUSIC_VOLUME=0)\n"); return; }
    g_volume = std::min(percent, 100) / 100.0f;
    const char* shuffle = std::getenv("NFSU1_MUSIC_SHUFFLE");
    g_shuffle = !shuffle || std::atoi(shuffle) != 0;
    const char* dirEnv = std::getenv("NFSU1_MUSIC_DIR");
    const std::filesystem::path dir = dirEnv && *dirEnv ? std::filesystem::path(dirEnv) : std::filesystem::path(gameDir) / ".." / "music";
    for (auto& list : g_lists) { list.files = scan(dir / list.name); reorder(list); }
    std::printf("[NFSU1 MUSIC] %s: %zu menu, %zu race tracks, volume %d%%, %s\n", dir.lexically_normal().c_str(),
                g_lists[0].files.size(), g_lists[1].files.size(), percent, g_shuffle ? "shuffle" : "in order");
    if (g_lists[0].files.empty() && g_lists[1].files.empty()) return;
    g_thread = std::thread(decoderThread);
}

void musicStop() {
    if (!g_thread.joinable()) return;
    g_stop = true;
    g_thread.join();
}

void musicSetRace(bool race) {
    // The driving key map also drops during a race's pause menu; switch lists only once it has held for 3 s.
    static bool pending = false;
    static std::chrono::steady_clock::time_point since;
    const auto now = std::chrono::steady_clock::now();
    static auto lastReport = now;
    if (g_thread.joinable() && now - lastReport >= std::chrono::seconds(10)) {   // what reached the output
        lastReport = now;
        std::printf("[NFSU1 MUSIC] last 10 s: %.1f s played, %.2f s starved, peak %.3f\n", g_mixed.exchange(0) / double(g_rate.load() ? g_rate.load() : 1),
                    g_starved.exchange(0) / double(g_rate.load() ? g_rate.load() : 1), double(g_peak.exchange(0)));
    }
    if (race == g_wantRace.load()) { pending = false; return; }
    if (!pending) { pending = true; since = now; }
    if (now - since >= std::chrono::seconds(3)) {
        pending = false;
        g_wantRace = race;
        std::printf("[NFSU1 MUSIC] %s list\n", race ? "race" : "menu");
    }
}

void musicNext() {
    if (g_thread.joinable()) g_skip = true;
}

extern "C" void nfsHostMusicMix(float* out, unsigned frames, unsigned rate) {
    if (!g_thread.joinable()) return;
    g_rate = rate;
    if (g_flush.load()) { g_read = g_write.load(); g_fade = 0.0f; g_flush = false; }
    const float volume = g_volume.load();
    const float fadeStep = 1.0f / (0.25f * float(rate));   // quarter-second fade-in after a switch
    uint64_t r = g_read.load();
    const uint64_t available = g_write.load() - r;
    const unsigned n = unsigned(std::min<uint64_t>(available, frames));
    float peak = 0;
    for (unsigned i = 0; i < n; ++i, ++r) {
        const uint64_t at = r % kRingFrames;
        g_fade = std::min(1.0f, g_fade + fadeStep);
        const float gain = volume * g_fade, l = g_ring[2 * at] * gain, rr = g_ring[2 * at + 1] * gain;
        out[2 * i] += l;
        out[2 * i + 1] += rr;
        peak = std::max(peak, std::max(std::fabs(l), std::fabs(rr)));
    }
    g_read = r;
    g_mixed += n;
    g_starved += frames - n;
    if (peak > g_peak.load()) g_peak = peak;
}
