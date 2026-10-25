// nfs_crash_preload.cpp - small LD_PRELOAD crash reporter for the handheld ports.
//
// The recompiled game is one big native binary; when it takes a fatal signal the launcher only sees a
// non-zero exit and the game's own log stops mid-line. This preload installs handlers for the fatal
// signals on an alternate stack and, before the process dies, writes the signal, the faulting address,
// the program counter and a backtrace to stderr (which the launcher captures into log.txt) and to
// nfs-crash.log next to the binary. It then restores the default handler and re-raises, so the process
// still dies with the real signal and the launcher's exit code is unchanged.
//
// Built as a standalone shared object (see build_nfsu1.sh); nothing in the game links against it.
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <ucontext.h>
#include <unistd.h>

namespace {

char g_logPath[1024];

void writeAll(int fd, const char* s) { if (fd >= 0) { size_t n = std::strlen(s); while (n) { ssize_t w = write(fd, s, n); if (w <= 0) break; s += w; n -= (size_t)w; } } }

// Signal handlers must stay async-signal-safe: no malloc, no stdio. backtrace() and writing to a raw fd
// are safe; backtrace_symbols() allocates, so we use backtrace_symbols_fd straight to the files instead.
void report(int fd, int sig, siginfo_t* info, void* uc) {
    char line[256];
    const char* name = strsignal(sig);
    std::snprintf(line, sizeof line, "\n[NATIVE_CRASH] signal=%d (%s) fault_addr=%p\n", sig, name ? name : "?", info ? info->si_addr : nullptr);
    writeAll(fd, line);
#if defined(__aarch64__)
    if (uc) {
        auto* c = &static_cast<ucontext_t*>(uc)->uc_mcontext;
        std::snprintf(line, sizeof line, "[NATIVE_CRASH] pc=%#llx sp=%#llx lr=%#llx\n",
                      (unsigned long long)c->pc, (unsigned long long)c->sp, (unsigned long long)c->regs[30]);
        writeAll(fd, line);
    }
#else
    (void)uc;
#endif
    void* frames[64];
    int n = backtrace(frames, 64);
    writeAll(fd, "[NATIVE_CRASH] backtrace:\n");
    backtrace_symbols_fd(frames, n, fd);
    // Memory map, so an address in the backtrace can be placed in the binary or a library.
    writeAll(fd, "[NATIVE_CRASH] memory maps:\n");
    int maps = open("/proc/self/maps", O_RDONLY);
    if (maps >= 0) { char buf[4096]; ssize_t r; while ((r = read(maps, buf, sizeof buf)) > 0) { ssize_t o = 0; while (o < r) { ssize_t w = write(fd, buf + o, (size_t)(r - o)); if (w <= 0) { o = r; break; } o += w; } } close(maps); }
}

void handler(int sig, siginfo_t* info, void* uc) {
    report(STDERR_FILENO, sig, info, uc);
    int fd = open(g_logPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { report(fd, sig, info, uc); fsync(fd); close(fd); }
    // Restore the default disposition and re-raise, so the process dies for real with this signal.
    signal(sig, SIG_DFL);
    raise(sig);
}

struct Install {
    Install() {
        const char* dir = std::getenv("NFS_CRASH_DIR");
        std::snprintf(g_logPath, sizeof g_logPath, "%s/nfs-crash.log", dir && dir[0] ? dir : ".");
        static std::array<char, 1 << 16> stackMem;
        stack_t ss{}; ss.ss_sp = stackMem.data(); ss.ss_size = stackMem.size(); ss.ss_flags = 0;
        sigaltstack(&ss, nullptr);
        struct sigaction sa{};
        sa.sa_sigaction = handler;
        sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND;
        sigemptyset(&sa.sa_mask);
        for (int sig : {SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE}) sigaction(sig, &sa, nullptr);
    }
} g_install;

}  // namespace
