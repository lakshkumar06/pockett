FROM node:24-bookworm-slim
WORKDIR /app
COPY Runtime/package*.json Runtime/
COPY Spacetime/spacetimedb/package*.json Spacetime/spacetimedb/
RUN npm ci --omit=dev --prefix Runtime && npm ci --omit=dev --prefix Spacetime/spacetimedb
COPY Runtime/src Runtime/src
COPY Spacetime/spacetimedb/src/domain.ts Spacetime/spacetimedb/src/domain.ts
USER node
WORKDIR /app/Runtime
ENV HOST=0.0.0.0 PORT=8787
EXPOSE 8787
CMD ["node", "src/server.ts"]
