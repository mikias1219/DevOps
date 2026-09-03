# syntax=docker/dockerfile:1
# Lab backend — FROM prebuilt lab-node (no apt). Fast after warm-lab-base.sh.
ARG LAB_NODE=127.0.0.1:5001/lab-node:20
FROM ${LAB_NODE} AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
  npm config set fetch-timeout 600000 fetch-retries 5 \
  && npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund

FROM ${LAB_NODE} AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN --mount=type=cache,target=/root/.npm \
  npm run build

FROM ${LAB_NODE} AS runner
WORKDIR /app
# NODE_ENV comes from compose env_file (lab: development → no API encryption).
# Do not use `npm run start:prod` — it hardcodes NODE_ENV=production.
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
EXPOSE 5000
CMD ["node", "dist/main"]
