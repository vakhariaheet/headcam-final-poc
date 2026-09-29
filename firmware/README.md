# Firmware

[amb82_hat_native](amb82_hat_native/README.md) is the active AMB82-Mini
firmware: BLE Wi-Fi provisioning, JXF37 camera, and outbound RTMP publishing.
Its source, host tests, sensor configuration, and vendored librtmp license
must remain in the repository. The external AmebaPro2 SDK/toolchain is
required to build; setup instructions are in the native README.

The earlier Arduino camera, direct-stream, live-stream, and hat prototypes
have been retired. Historical CHANGELOG entries still describe them.
Wi-Fi credentials arrive over BLE; no `secrets.h` is needed.
The optional ignored `cloud_config.h` has a committed example and is not
required when the app supplies the ingest URL.

See [configuration notes](../CONFIGURATION.md) for environment and secret handling.
