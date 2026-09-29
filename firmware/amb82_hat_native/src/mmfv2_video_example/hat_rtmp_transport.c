#include "hat_rtmp_transport.h"
#include <errno.h>
#ifdef CONFIG_PLATFORM_8735B
#include "FreeRTOS.h"
#include "task.h"
#else
#include <sys/select.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#endif

static bool (*cancel_callback)(void *);
static void *cancel_context;
void hat_rtmp_set_cancel(bool (*callback)(void *), void *context)
{
    cancel_callback = callback;
    cancel_context = context;
}
uint32_t hat_rtmp_now(void)
{
#ifdef CONFIG_PLATFORM_8735B
    return (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)((uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
#endif
}
static bool cancelled(void)
{
    return cancel_callback && cancel_callback(cancel_context);
}
static int ready(int fd, bool write, uint32_t start)
{
    while (!cancelled() && (uint32_t)(hat_rtmp_now() - start) < 5000) {
        fd_set set;
        FD_ZERO(&set); FD_SET(fd, &set);
        struct timeval wait = {0, 100000};
        int rc = select(fd + 1, write ? NULL : &set, write ? &set : NULL, NULL, &wait);
        if (rc > 0) return 1;
        if (rc < 0 && errno != EINTR) return -1;
    }
    errno = ETIMEDOUT;
    return -1;
}
int hat_rtmp_connect_socket(int fd, const struct sockaddr *addr, socklen_t size)
{
    unsigned long nonblocking = 1;
    if (ioctl(fd, FIONBIO, &nonblocking) < 0) return -1;
#ifndef CONFIG_PLATFORM_8735B
#ifdef SO_NOSIGPIPE
    int enabled = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled));
#endif
#endif
    if (cancelled()) return -1;
    int rc = connect(fd, addr, size);
    if (rc == 0) return 0;
    if (errno != EINPROGRESS && errno != EWOULDBLOCK) return -1;
    if (ready(fd, true, hat_rtmp_now()) < 0) return -1;
    int error = 0;
    socklen_t length = sizeof(error);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) < 0) return -1;
    errno = error;
    return error ? -1 : 0;
}
int hat_rtmp_recv(int fd, void *data, size_t size, int flags)
{
    uint32_t start = hat_rtmp_now();
    while (ready(fd, false, start) > 0) {
        if (cancelled()) return -1;
        int rc = recv(fd, data, size, flags);
        if (rc >= 0) return rc;
        if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) return -1;
    }
    return -1;
}
int hat_rtmp_send(int fd, const void *data, size_t size, int flags)
{
    uint32_t start = hat_rtmp_now();
    while (ready(fd, true, start) > 0) {
        if (cancelled()) return -1;
#ifdef MSG_NOSIGNAL
        flags |= MSG_NOSIGNAL;
#endif
        int rc = send(fd, data, size, flags);
        if (rc >= 0) return rc;
        if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) return -1;
    }
    return -1;
}
int hat_rtmp_readable(int fd)
{
    fd_set set;
    FD_ZERO(&set); FD_SET(fd, &set);
    struct timeval wait = {0, 0};
    return select(fd + 1, &set, NULL, NULL, &wait);
}
