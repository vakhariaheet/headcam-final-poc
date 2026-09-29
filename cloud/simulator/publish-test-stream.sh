#!/usr/bin/env bash
set -euo pipefail

MEDIAMTX_HOST="${MEDIAMTX_HOST:-mediamtx}"
MEDIAMTX_RTSP_PORT="${MEDIAMTX_RTSP_PORT:-8554}"
STREAM_PATH="${STREAM_PATH:-live/hat}"

echo "[simulator] waiting for MediaMTX at ${MEDIAMTX_HOST}:${MEDIAMTX_RTSP_PORT}..."
until nc -z "${MEDIAMTX_HOST}" "${MEDIAMTX_RTSP_PORT}"; do
  sleep 1
done

echo "[simulator] publishing synthetic test pattern to rtsp://${MEDIAMTX_HOST}:${MEDIAMTX_RTSP_PORT}/${STREAM_PATH}"
echo "[simulator] this stands in for the hat's real H.265 RTSP uplink until hardware arrives"

while true; do
  ffmpeg -re \
    -f lavfi -i "testsrc2=size=1920x1080:rate=30" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -f rtsp -rtsp_transport tcp \
    "rtsp://${MEDIAMTX_HOST}:${MEDIAMTX_RTSP_PORT}/${STREAM_PATH}" \
    || true
  echo "[simulator] ffmpeg publisher exited, retrying in 2s..."
  sleep 2
done
