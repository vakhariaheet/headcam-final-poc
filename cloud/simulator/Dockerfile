FROM alpine:3.20

RUN apk add --no-cache ffmpeg bash

COPY publish-test-stream.sh /publish-test-stream.sh
RUN chmod +x /publish-test-stream.sh

ENTRYPOINT ["/publish-test-stream.sh"]
