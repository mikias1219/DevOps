# Collaboration frontend image owned by docker-devops (do not use the app-repo Dockerfile).
FROM node:20-bookworm-slim AS deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json* .npmrc* ./
RUN npm install --no-audit --no-fund --legacy-peer-deps

FROM node:20-bookworm-slim AS builder
WORKDIR /app
ARG NEXT_PUBLIC_COLLABORATION_URL=http://172.16.50.39:5000/api/v1
ARG NEXT_PUBLIC_WS_URL=http://172.16.50.39:5000
ARG NEXT_PUBLIC_API_URL=http://172.16.50.39:5000/api/v1
ARG NEXT_PUBLIC_API_BASE_URL=http://172.16.50.39:5000/api/v1
ARG NEXT_PUBLIC_COLLABORATION_SOCKET_URL=http://172.16.50.39:5000
ARG NEXT_PUBLIC_APP_URL=http://172.16.50.39:3000
ENV NEXT_PUBLIC_COLLABORATION_URL=$NEXT_PUBLIC_COLLABORATION_URL
ENV NEXT_PUBLIC_WS_URL=$NEXT_PUBLIC_WS_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL
ENV NEXT_PUBLIC_COLLABORATION_SOCKET_URL=$NEXT_PUBLIC_COLLABORATION_SOCKET_URL
ENV NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN rm -rf node_modules
COPY --from=deps /app/node_modules ./node_modules
RUN mkdir -p public
RUN NODE_OPTIONS=--max-old-space-size=4096 npx next build

FROM node:20-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0
ENV PORT=3001
RUN useradd -m -u 1001 nextjs
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
RUN chown -R nextjs:nextjs /app
USER nextjs
EXPOSE 3001
CMD ["npx", "next", "start", "-H", "0.0.0.0", "-p", "3001"]
