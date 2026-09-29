#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef CONFIG_PLATFORM_8735B
#include "lwip/sockets.h"
#include "lwip/netdb.h"
#else
#include <sys/socket.h>
#endif
// One publisher per process. The callback is checked while waiting on socket I/O.
void hat_rtmp_set_cancel(bool (*callback)(void *), void *context);
uint32_t hat_rtmp_now(void);
int hat_rtmp_connect_socket(int fd, const struct sockaddr *addr, socklen_t size);
int hat_rtmp_recv(int fd, void *data, size_t size, int flags);
int hat_rtmp_send(int fd, const void *data, size_t size, int flags);
int hat_rtmp_readable(int fd);
