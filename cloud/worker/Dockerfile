FROM ghcr.io/puppeteer/puppeteer:latest

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
COPY overlay.html ./
RUN npm run build

# The base image ships a Chrome build under a version-specific cache path
# that doesn't always match what the npm-installed puppeteer version expects
# by default, so resolve the actual binary at build time instead of pinning
# a revision that will go stale when the base image updates.
RUN find /home/pptruser/.cache/puppeteer -type f -iname chrome | head -n1 > /app/chrome-path.txt \
    && test -s /app/chrome-path.txt

RUN mkdir -p /output && chown -R pptruser:pptruser /app /output
USER pptruser

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

EXPOSE 4100

CMD ["node", "dist/server.js"]
