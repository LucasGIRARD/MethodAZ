ARG NODE_IMAGE=node:24-bookworm-slim
FROM ${NODE_IMAGE} AS build

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ make python3 \
    && rm -rf /var/lib/apt/lists/*

COPY . .
RUN npm ci \
    && npm prune --omit=dev

FROM ${NODE_IMAGE}

ENV NODE_ENV=production
WORKDIR /app

COPY --from=build --chown=node:node /app /app

USER node

EXPOSE 8000

CMD ["node", "--enable-source-maps", "build/index.mjs", "/etc/kill-newsletter/configuration.mjs", "--type", "server", "--port", "8000"]
