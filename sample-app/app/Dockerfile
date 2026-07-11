# Public base image so the build is fully reproducible with no private deps.
FROM node:20-alpine

WORKDIR /app
COPY package.json ./
# No third-party dependencies, so install is a no-op but keeps the layer honest.
RUN npm install --omit=dev || true
COPY server.js ./

ENV PORT=8080
EXPOSE 8080

# Run as non-root for a slightly more production-like posture.
USER node

CMD ["node", "server.js"]
