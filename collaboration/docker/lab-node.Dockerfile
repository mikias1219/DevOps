# Lab Node base — build tools baked in ONCE so app Dockerfiles never run apt-get.
# Build: docker-devops/scripts/warm-lab-base.sh
FROM node:20-bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
