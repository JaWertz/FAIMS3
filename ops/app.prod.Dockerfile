# syntax=docker/dockerfile:1
FROM node:22-alpine AS build
WORKDIR /src

# bash needed for ./app/bin/prebuildConfig.sh (shebang #!/bin/bash)
RUN apk add --no-cache bash

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

COPY pnpm-workspace.yaml pnpm-lock.yaml package.json turbo.json ./
COPY api/package.json ./api/
COPY app/package.json ./app/
COPY library/data-model/package.json ./library/data-model/
COPY library/forms/package.json ./library/forms/

RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

COPY . .

RUN chmod +x /src/app/bin/*.sh || true
# Build with production overrides layered on top of dist defaults.
RUN cp /src/app/.env.dist /src/app/.env && cat /src/app/.env.prod >> /src/app/.env
RUN pnpm turbo build --filter=@faims3/app

FROM node:22-alpine AS run
WORKDIR /srv

COPY --from=build /src /srv

EXPOSE 3000

CMD ["sh","-lc","cd /srv/app && ./node_modules/.bin/vite preview --host 0.0.0.0 --port 3000 --strictPort"]
