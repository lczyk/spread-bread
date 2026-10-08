/*
 * seccomp-shim: lets sshd take logins where seccomp filters cannot be
 * installed.
 *
 * Preloaded into the image's sshd via LD_PRELOAD in the Dockerfile CMD;
 * sshd-session and sshd-auth inherit it. openssh 10.4+ aborts the pre-auth
 * child when prctl(PR_SET_SECCOMP) fails, and qemu-user (s390x, ppc64le) and
 * Docker Desktop's Rosetta (amd64 on Apple Silicon) refuse that call with
 * EINVAL. Reporting success for that one failure lets sshd carry on
 * unsandboxed, as openssh did before 10.4. Natively the call succeeds and the
 * shim changes nothing.
 *
 * Written without libc headers so a bare clang can cross-compile it; the
 * constants are the same on every Linux arch. prctl stays variadic because
 * calling glibc's variadic prctl through a fixed-argument pointer is unsafe
 * on ppc64le.
 */

#include <stdarg.h>

#define PR_SET_SECCOMP 22
#define EINVAL 22
#define RTLD_NEXT ((void *) -1l)

extern void *dlsym(void *, const char *);
extern int *__errno_location(void);

int prctl(int option, ...)
{
    static int (*real)(int, ...);
    unsigned long a2, a3, a4, a5;
    va_list ap;
    int r;

    va_start(ap, option);
    a2 = va_arg(ap, unsigned long);
    a3 = va_arg(ap, unsigned long);
    a4 = va_arg(ap, unsigned long);
    a5 = va_arg(ap, unsigned long);
    va_end(ap);

    if (!real)
        real = (int (*)(int, ...))dlsym(RTLD_NEXT, "prctl");
    r = real(option, a2, a3, a4, a5);
    if (r == -1 && option == PR_SET_SECCOMP && *__errno_location() == EINVAL)
        return 0;
    return r;
}
