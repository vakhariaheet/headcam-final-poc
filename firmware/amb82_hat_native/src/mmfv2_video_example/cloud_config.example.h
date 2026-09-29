#pragma once
// Optional default. Copy to cloud_config.h (gitignored) and set your cloud URL.
// A START_STREAM command with a URL overrides this. Empty means no destination.
#define HAT_DEFAULT_RTMP_URL ""
// Example: rtmp://ingest.example.com:1935/live/hat
// RTMPS/TLS is not supported in this initial RTMP transport.
