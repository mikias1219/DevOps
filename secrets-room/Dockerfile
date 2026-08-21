FROM node:20-bookworm-slim

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY server.js ./
COPY public ./public

ENV PORT=8300
EXPOSE 8300
CMD ["npm", "start"]
