FROM node:20-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends chromium ca-certificates fonts-noto-core && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY server.js ./
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
EXPOSE 8787
CMD ["node", "server.js"]
