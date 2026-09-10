Stage 1: Build the local Hiero JavaScript SDK
FROM node:20-bookworm-slim AS sdk-builder

WORKDIR /sdk

RUN corepack enable
RUN npm install -g @go-task/cli

COPY . .

RUN pnpm install --frozen-lockfile
RUN task build
RUN pnpm pack --pack-destination /sdk-package


Stage 2: Build and run the TCK server
FROM node:20-bookworm-slim
WORKDIR /app

COPY tck/package.json ./

Remove the published SDK dependency so we can install the locally built SDK.
RUN npm pkg delete dependencies.@hiero-ledger/sdk

COPY --from=sdk-builder /sdk-package/.tgz /tmp/

RUN npm install
RUN npm install /tmp/.tgz

COPY tck/ .

EXPOSE 8544

CMD ["npm", "start"]