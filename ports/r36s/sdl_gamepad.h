#pragma once
// R36S gamepad -> guest input, PlayStation 2 layout (by position: Cross = bottom, Circle = right,
// Square = left, Triangle = top; on the R36S those are the buttons labelled B, A, Y, X).
//
// Buttons always reach the game as its PC keyboard keys (the game's own default PC key bindings), never
// as joystick buttons: the game's joystick bindings do not include pause/reset, and sending both made
// every press arrive twice. The joystick only carries the analog steering (left stick X) while driving,
// so steering stays proportional. Keys are recomputed from the whole pad state on every event, so a
// button and the d-pad that both mean "left" never release each other.
//
// Driving (NFSU2 PS2 defaults): Cross accelerate, Square brake/reverse, Circle e-brake, Triangle camera,
//   R1 nitrous, L1 look back, R2/L2 shift up/down (manual gearbox), Start pause, Select reset car,
//   left stick steer. D-pad as on the consoles: Up engage event / enter shop (Enter), Down career status (1),
//   Left world map (M), Right SMS (Tab).
// Menus: d-pad / left stick move, Cross or Start accept, Circle or Triangle back, Square = Space.
#include <SDL.h>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <string>

class SdlGamepad {
public:
    enum Button : unsigned {A,B,X,Y,L1,R1,L2,R2,Start,Select,ThumbL,ThumbR,Up,Down,Left,Right,ButtonCount};

    static int buttonFor(uint8_t b) {
        switch (b) {
        case SDL_CONTROLLER_BUTTON_A: return A;            // south (R36S: physical B)
        case SDL_CONTROLLER_BUTTON_B: return B;            // east  (R36S: physical A)
        case SDL_CONTROLLER_BUTTON_X: return X;            // west  (R36S: physical Y)
        case SDL_CONTROLLER_BUTTON_Y: return Y;            // north (R36S: physical X)
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return L1;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return R1;
        case SDL_CONTROLLER_BUTTON_START: return Start;
        case SDL_CONTROLLER_BUTTON_BACK: return Select;
        case SDL_CONTROLLER_BUTTON_LEFTSTICK: return ThumbL;
        case SDL_CONTROLLER_BUTTON_RIGHTSTICK: return ThumbR;
        case SDL_CONTROLLER_BUTTON_DPAD_UP: return Up;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return Down;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return Left;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return Right;
        default: return -1;
        }
    }
    template<class SetKey> bool button(uint8_t sdlButton, bool down, bool driving, SetKey&& setKey) {
        const int b = buttonFor(sdlButton);
        if (b < 0) return false;
        buttons_[b] = down;
        apply(driving, setKey);
        return true;
    }
    template<class SetKey> void axis(uint8_t sdlAxis, int16_t raw, bool driving, SetKey&& setKey) {
        const float v = raw < 0 ? raw / 32768.0f : raw / 32767.0f;
        switch (sdlAxis) {
        case SDL_CONTROLLER_AXIS_LEFTX: stickX_ = dead(v); break;
        case SDL_CONTROLLER_AXIS_LEFTY: stickY_ = dead(v); break;
        case SDL_CONTROLLER_AXIS_RIGHTX: rightX_ = dead(v); break;
        case SDL_CONTROLLER_AXIS_RIGHTY: rightY_ = dead(v); break;
        // R36S L2/R2 are digital buttons that SDL reports as a trigger axis (0 or 32767).
        case SDL_CONTROLLER_AXIS_TRIGGERLEFT: leftTrigger_ = v > 0.05f ? v : 0.0f; break;
        case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: rightTrigger_ = v > 0.05f ? v : 0.0f; break;
        default: return;
        }
        apply(driving, setKey);
    }
    // Returns true when the driving/menu mode changed (the joystick state must be republished).
    template<class SetKey> bool refresh(bool driving, SetKey&& setKey) {
        if (driving == driving_) return false;
        apply(driving, setKey);
        return true;
    }
    template<class SetKey> void releaseAll(SetKey&& setKey) {
        buttons_.fill(false);
        stickX_ = stickY_ = rightX_ = rightY_ = leftTrigger_ = rightTrigger_ = 0;
        apply(driving_, setKey);
    }
    bool held(Button b) const { return buttons_[b]; }

    // The guest joystick: left stick X while driving (proportional steering), nothing else.
    void padState(float axes[6], uint32_t& buttons, int& hatX, int& hatY) const {
        for (int i = 0; i < 6; ++i) axes[i] = 0;
        axes[0] = driving_ ? stickX_ : 0.0f;
        buttons = 0;
        hatX = hatY = 0;
    }

private:
    std::array<bool, ButtonCount> buttons_{};
    float stickX_ = 0, stickY_ = 0, rightX_ = 0, rightY_ = 0, leftTrigger_ = 0, rightTrigger_ = 0;
    std::array<bool, 256> sent_{};
    bool driving_ = false;

    // Driving actions: a fixed PC scancode each (DirectInput DIK_*), and a configurable pad button
    // (NFSU1_CONTROLS). The shift-up/down keys differ between the games: NFSU1 uses Insert/Delete (0xd2/0xd3),
    // NFSU2 uses Left Shift/Left Ctrl (0x2a/0x1d). Manual transmission (or a drag race) must be on for the
    // gear keys to do anything in game.
    enum Action { Accelerate, Brake, Handbrake, Camera, Nitro, LookBack, GearUp, GearDown, ActionCount };
#if defined(NFS_GAME_U1)
    static constexpr uint8_t actionScan_[ActionCount] = {0xc8,0xd0,0x39,0x2e,0x38,0x30,0xd2,0xd3};
#else
    static constexpr uint8_t actionScan_[ActionCount] = {0xc8,0xd0,0x39,0x2e,0x38,0x30,0x2a,0x1d};
#endif
    unsigned actionButton_[ActionCount] = {A, X, B, Y, R1, L1, R2, L2};  // defaults = original layout
#if defined(NFS_GAME_U1)
    uint8_t selectScan_ = 0x0e;   // Select while driving: Backspace (0x0e), R reset (0x13) or off (0)
#else
    uint8_t selectScan_ = 0x13;
#endif
    bool controlsLoaded_ = false;

    static unsigned buttonByLabel(const std::string& s) {  // physical R36S labels -> enum
        if (s=="B") return A; if (s=="A") return B; if (s=="Y") return X; if (s=="X") return Y;
        if (s=="L1") return L1; if (s=="R1") return R1; if (s=="L2") return L2; if (s=="R2") return R2;
        if (s=="SELECT") return Select; if (s=="START") return Start;
        return ButtonCount;  // invalid: keep the default
    }
    void loadControls() {
        controlsLoaded_ = true;
        const char* path = std::getenv("NFSU1_CONTROLS");
        if (!path || !*path) return;
        std::FILE* f = std::fopen(path, "r");
        if (!f) return;
        char line[128];
        auto trim = [](std::string s) {
            size_t a = s.find_first_not_of(" \t\r\n"); if (a == std::string::npos) return std::string();
            size_t b = s.find_last_not_of(" \t\r\n"); return s.substr(a, b - a + 1);
        };
        while (std::fgets(line, sizeof line, f)) {
            if (char* h = std::strchr(line, '#')) *h = 0;
            char* eq = std::strchr(line, '='); if (!eq) continue; *eq = 0;
            std::string key = trim(line), val = trim(eq + 1);
            for (char& c : key) c = char(std::tolower((unsigned char)c));
            for (char& c : val) c = char(std::toupper((unsigned char)c));
            int a = key=="accelerate"?Accelerate:key=="brake"?Brake:key=="handbrake"?Handbrake:
                    key=="camera"?Camera:key=="nitro"?Nitro:key=="lookback"?LookBack:
                    key=="gearup"?GearUp:key=="geardown"?GearDown:-1;
            if (a >= 0) { unsigned b = buttonByLabel(val); if (b != ButtonCount) actionButton_[a] = b; }
            else if (key == "select") selectScan_ = val=="RESET"?0x13:val=="NONE"?0:0x0e;
        }
        std::fclose(f);
        std::printf("[NFSU1] controls loaded from %s (accel=%u brake=%u hbrake=%u cam=%u nitro=%u look=%u gup=%u gdn=%u select=0x%02x)\n",
                    path, actionButton_[0],actionButton_[1],actionButton_[2],actionButton_[3],
                    actionButton_[4],actionButton_[5],actionButton_[6],actionButton_[7], selectScan_);
    }

    static float dead(float v) { return std::fabs(v) < 0.10f ? 0.0f : v; }

    template<class SetKey> void apply(bool driving, SetKey& setKey) {
        std::array<bool, 256> want{};
        // Hysteresis keeps a stick resting near the threshold from chattering.
        auto past = [&](float value, unsigned scan) { return value > (sent_[scan] ? .25f : .4f); };
        if (driving) {
            // PC default keys: Up/Down throttle/brake, Space e-brake, Left Alt nitrous, C camera, B look back,
            // Left Shift / Left Ctrl shift up/down, Escape pause, R reset; free-roam actions Enter engage event
            // / shop, 1 career status, M world map, Tab SMS (on the d-pad, as on the consoles). The stick steers
            // through the joystick (proportional). Which pad button drives each action is configurable through
            // NFSU1_CONTROLS (the config menu writes it); the defaults below reproduce the original layout.
            if (!controlsLoaded_) loadControls();
            for (int a = 0; a < ActionCount; ++a) {
                const unsigned b = actionButton_[a]; const uint8_t scan = actionScan_[a];
                bool held = buttons_[b];
                if (b == R2) held = held || past(rightTrigger_, scan);
                if (b == L2) held = held || past(leftTrigger_, scan);
                want[scan] = held;
            }
            want[0x1c] = buttons_[Up];
            want[0x02] = buttons_[Down];
            want[0x32] = buttons_[Left];
            want[0x0f] = buttons_[Right];
            want[0x01] = buttons_[Start];
            if (selectScan_) want[selectScan_] = buttons_[Select];
        } else {
            want[0xcb] = buttons_[Left] || past(-stickX_, 0xcb); want[0xcd] = buttons_[Right] || past(stickX_, 0xcd);
            want[0xc8] = buttons_[Up] || past(-stickY_, 0xc8); want[0xd0] = buttons_[Down] || past(stickY_, 0xd0);
            want[0x1c] = buttons_[A] || buttons_[Start];
            want[0x01] = buttons_[B] || buttons_[Y];
            want[0x39] = buttons_[X];
#if defined(NFS_GAME_U1)
            want[0x0e] = buttons_[Select];
#endif
        }
        driving_ = driving;
        for (unsigned scan = 0; scan < 256; ++scan)
            if (want[scan] != sent_[scan]) { sent_[scan] = want[scan]; setKey(scan, want[scan]); }
    }
};
