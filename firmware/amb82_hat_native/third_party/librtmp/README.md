# librtmp

Source: https://github.com/mstorsjo/rtmpdump
Pinned commit: fa8646daeb19dfd12c181f7d19de708d623704c0
License: LGPL-2.1-or-later; see COPYING and retained source notices.

Only the protocol library sources are included. Built with NO_CRYPTO: plain
RTMP only, no RTMPS/RTMPE. Local changes: lwIP/FreeRTOS includes and timeout
representation in rtmp_sys.h, cancellable socket adapter, monotonic clock,
portable strings/hostent declarations, a 1 MiB packet allocation cap, and cleanup of a newly allocated packet body
on a truncated read (cached channel bodies may already be freed by ReadN).
The four librtmp_*.c wrappers compile these sources within the SDK's glob.
