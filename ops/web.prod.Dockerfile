# syntax=docker/dockerfile:1
FROM node:22-alpine AS build
WORKDIR /src
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
COPY pnpm-workspace.yaml pnpm-lock.yaml package.json turbo.json ./
COPY api/package.json ./api/
COPY web/package.json ./web/
COPY library/data-model/package.json ./library/data-model/
COPY library/forms/package.json ./library/forms/
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

COPY . .
# Build with production overrides layered on top of dist defaults.
RUN cp /src/web/.env.dist /src/web/.env && cat /src/web/.env.prod >> /src/web/.env
# Vite build (production mode) – keine Dev-Client Artefakte
RUN pnpm turbo build --filter=@faims3/web

FROM node:22-alpine AS run
WORKDIR /srv
COPY --from=build /src /srv
EXPOSE 3001
# vite preview => served dist, kein /@vite/client
CMD ["sh","-lc","cd /srv/web && ./node_modules/.bin/vite preview --host 0.0.0.0 --port 3001 --strictPort"]
