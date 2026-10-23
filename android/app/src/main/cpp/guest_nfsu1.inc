// Imports only NFSU1's SPEED.EXE has (34 that SPEED2.EXE does not import). Each answers the way the game
// needs on a handheld with one fullscreen window: no console, no other desktop windows, no CD drive.
void charUpper(){
    uint32_t value=arg(0);
    if(value<=0xffff){ret(uint32_t(std::toupper(int(value&0xff))),1);return;}   // a single character
    for(uint32_t at=value;;++at){char* c=static_cast<char*>(ptr(at,1));if(!*c)break;*c=char(std::toupper(static_cast<unsigned char>(*c)));}
    ret(value,1);
}
void adjustWindowRectEx(){if(!arg(0)){lastError=87;ret(0,4);return;}ret(1,4);}   // borderless fullscreen: unchanged
void callNextHook(){ret(0,4);}
void clientToScreen(){ret(windows.count(arg(0))?1:0,2);}   // the window covers the screen at 0,0
void asyncKeyState(){ret(0,1);}
void keyState(){ret(0,1);}
void registerClassA(){
    // WNDCLASSA is WNDCLASSEXA without cbSize and hIconSm: style 0, proc 4, cbWndExtra 12, hInstance 16, name 36.
    uint32_t value=arg(0);if(!value){lastError=87;ret(0,1);return;}
    auto name=guestString(read32(value+36));uint32_t procedure=read32(value+4);
    if(name.empty()||!recomp_lookup(procedure)){lastError=87;ret(0,1);return;}
    if(windowClasses.count(name)){lastError=1410;ret(0,1);return;}
    GuestWindowClass record{nextClassAtom++,procedure,read32(value+16),read32(value),read32(value+12),name};
    uint32_t atom=record.atom;windowClasses.emplace(name,std::move(record));ret(atom,1);
}
void sendNotifyMessage(){   // same thread: a SendMessage whose result is only success
    if(!windows.count(arg(0))){lastError=1400;ret(0,4);return;}
    windowMessage(arg(0),arg(1),arg(2),arg(3));ret(1,4);
}
void setCursorPos(){ret(1,2);}
void setWindowsHook(){ret(0xf0070001u,4);}   // the hook is never called: there is no other input source
void unhookWindowsHook(){ret(1,1);}
void systemParametersInfo(){
    // SPI_GET*: BOOL/UINT answers 0; the accessibility structures (sticky/toggle/filter keys) keep their
    // cbSize and read as "off". SPI_SET*: accepted and ignored.
    uint32_t action=arg(0),value=arg(2);
    if(value&&memory->writable(value,4)){
        switch(action){
        case 0x0010: case 0x0002: case 0x0005: write32(value,0);break;      // screensaver active, beep, border
        case 0x0034: case 0x003a: if(memory->writable(value,8))write32(value+4,0);break;  // toggle/sticky keys flags
        case 0x0032: if(memory->writable(value,8))write32(value+4,0);break;   // filter keys flags
        default: break;
        }
    }
    ret(1,4);
}
void keyboardEvent(){ret(0,4);}
void stockObject(){ret(0xf0080000u+(arg(0)&0xff),1);}
void formatMessage(){lastError=317;ret(0,7);}   // ERROR_MR_MID_NOT_FOUND: no message tables
void localFree(){ret(0,1);}
void formatClock(bool date){
    uint32_t out=arg(4),capacity=arg(5);
    std::time_t now=std::time(nullptr);std::tm local{};localtime_r(&now,&local);
    if(uint32_t st=arg(2);st&&memory->readable(st,16)){   // a given SYSTEMTIME
        auto w=static_cast<const uint16_t*>(ptr(st,16));
        local.tm_year=w[0]-1900;local.tm_mon=w[1]-1;local.tm_mday=w[3];local.tm_hour=w[4];local.tm_min=w[5];local.tm_sec=w[6];
    }
    char text[32];std::strftime(text,sizeof text,date?"%m/%d/%y":"%H:%M:%S",&local);
    uint32_t need=uint32_t(std::strlen(text))+1;
    if(!capacity){ret(need,6);return;}
    if(capacity<need){lastError=122;ret(0,6);return;}
    std::memcpy(ptr(out,need),text,need);ret(need,6);
}
void dateFormat(){formatClock(true);}
void timeFormat(){formatClock(false);}
void logicalDriveStrings(){   // only C:\ (the game folder); no CD drive to search
    static const char drives[]="C:\\\0";const uint32_t need=sizeof drives;   // "C:\" NUL NUL
    if(arg(0)<need-1){ret(need,2);return;}std::memcpy(ptr(arg(1),need),drives,need);ret(need-1,2);
}
void volumeInformation(){
    uint32_t label=arg(1),labelSize=arg(2),serial=arg(3),maxName=arg(4),flags=arg(5),fs=arg(6),fsSize=arg(7);
    if(label&&labelSize)*static_cast<char*>(ptr(label,1))=0;
    if(serial)write32(serial,0x4e465355u);if(maxName)write32(maxName,255);if(flags)write32(flags,0x3);
    if(fs&&fsSize>=5)std::memcpy(ptr(fs,5),"NTFS",5);
    ret(1,8);
}
void consoleEvents(){if(arg(1))write32(arg(1),0);lastError=6;ret(0,2);}
void consoleInput(){if(arg(3))write32(arg(3),0);lastError=6;ret(0,4);}
void setConsoleMode(){lastError=6;ret(0,2);}
void directInputCreateA(){   // DirectInput 7: only DirectInput8Create is provided
    if(arg(2))write32(arg(2),0);ret(0x80004001u,4);   // E_NOTIMPL
}
const std::map<std::string,recomp_func_t> nfsu1Functions={
    {"user32.dll!CharUpperA",charUpper},{"user32.dll!AdjustWindowRectEx",adjustWindowRectEx},
    {"user32.dll!CallNextHookEx",callNextHook},{"user32.dll!ClientToScreen",clientToScreen},
    {"user32.dll!GetAsyncKeyState",asyncKeyState},{"user32.dll!GetKeyState",keyState},
    {"user32.dll!RegisterClassA",registerClassA},{"user32.dll!SendNotifyMessageA",sendNotifyMessage},
    {"user32.dll!SetCursorPos",setCursorPos},{"user32.dll!SetWindowsHookExA",setWindowsHook},
    {"user32.dll!UnhookWindowsHookEx",unhookWindowsHook},{"user32.dll!SystemParametersInfoA",systemParametersInfo},
    {"user32.dll!keybd_event",keyboardEvent},{"gdi32.dll!GetStockObject",stockObject},
    {"kernel32.dll!FormatMessageA",formatMessage},{"kernel32.dll!LocalFree",localFree},
    {"kernel32.dll!GetDateFormatA",dateFormat},{"kernel32.dll!GetTimeFormatA",timeFormat},
    {"kernel32.dll!GetLogicalDriveStringsA",logicalDriveStrings},{"kernel32.dll!GetVolumeInformationA",volumeInformation},
    {"kernel32.dll!GetNumberOfConsoleInputEvents",consoleEvents},{"kernel32.dll!PeekConsoleInputA",consoleInput},
    {"kernel32.dll!ReadConsoleInputA",consoleInput},{"kernel32.dll!SetConsoleMode",setConsoleMode},
    {"dinput.dll!DirectInputCreateA",directInputCreateA},
};
