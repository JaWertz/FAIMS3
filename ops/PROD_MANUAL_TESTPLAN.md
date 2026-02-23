# FAIMS3 Prod-ish Manual Test Plan (Caddy + HTTPS)

Target domain: `https://fe6103-c0005.sna94.uni-tuebingen.de`  
Host context: Windows 11 + WSL2 Ubuntu 22.04 + Docker Desktop  
Goal: verify a non-dev deployment (no Vite dev client, no localhost redirects) via Caddy TLS proxy.

## 0. Last Validated Run

Date: `2026-02-23` (Europe/Berlin)  
Status: `PASS` for platform checks, `mobile auth flow still under active testing`.

Validated results:

1. Public TLS is active (Let's Encrypt):
   - issuer: `C=US; O=Let's Encrypt; CN=E7`
   - cert valid from `2026-02-23` to `2026-05-24`
2. Core routing works:
   - `/` -> `200`
   - `/app` -> `308` -> `/app/`
   - `/app/` -> `200`
   - `/login?...` -> `200`
   - `/api/info` -> `200`
3. No dev artifacts:
   - no `@vite/client` in `/` and `/app/`
4. Static MIME types are correct:
   - app JS served as `text/javascript`
   - app CSS served as `text/css`
5. CouchDB public health path is blocked:
   - `/couchdb/_up` -> `404`
6. `api/info` returns expected server identity:
   - `id: default`, `prefix: FAIMS`, `serverVersion: 1.4.0`

## 1. Preconditions

1. Run from repo root: `/home/jakob/projects/faims3`
2. Containers up with prod compose:
   - `docker compose -f compose.prod.yml up -d --build`
3. Only Caddy publishes host ports:
   - `docker compose -f compose.prod.yml ps -a`
   - Expected: only `caddy` has `80:80` and `443:443`
4. SNI/TLS test uses explicit resolve to production IP:
   - `curl -Iv --resolve fe6103-c0005.sna94.uni-tuebingen.de:443:134.2.77.110 https://fe6103-c0005.sna94.uni-tuebingen.de/`

## 2. Manual CLI Test Steps

### 2.1 TLS and SNI

1. Test HTTPS with SNI and explicit resolve:
   - `curl -Iv --resolve fe6103-c0005.sna94.uni-tuebingen.de:443:134.2.77.110 https://fe6103-c0005.sna94.uni-tuebingen.de/`
   - Expected: `HTTP/2 200`, issuer is Let's Encrypt, certificate verify OK.
2. Optional cross-host test (from another uni-network PC):
   - Open `https://fe6103-c0005.sna94.uni-tuebingen.de/`
   - Expected: page loads over HTTPS without custom CA import.

### 2.2 No Dev Artifacts

1. Web root:
   - `curl -fsS https://fe6103-c0005.sna94.uni-tuebingen.de/ | grep -i "@vite/client" && echo DEV_FOUND || echo OK`
   - Expected: `OK`
2. App UI:
   - `curl -fsS https://fe6103-c0005.sna94.uni-tuebingen.de/app/ | grep -i "@vite/client" && echo DEV_FOUND || echo OK`
   - Expected: `OK`
3. Runtime logs (no startup build on every restart):
   - `docker compose -f compose.prod.yml logs -n 120 --no-color web app`
   - Expected: no repeated `pnpm install`/`turbo build` during container start
4. Host header hardening (optional, recommended):
   - `docker compose -f compose.prod.yml exec web sh -lc "wget -S --spider --header='Host: evil.example' http://127.0.0.1:3001/ 2>&1 | head -n 5"`
   - `docker compose -f compose.prod.yml exec app sh -lc "wget -S --spider --header='Host: evil.example' http://127.0.0.1:3000/ 2>&1 | head -n 5"`
   - Expected: `403 Forbidden`

### 2.3 Routing and Status Codes

1. Web root:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/`
   - Expected: `200`
2. App:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/app/`
   - Expected: `200`
3. Web alias endpoint:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/web`
   - Expected: `308` to `/` or `200` (acceptable if frontend route answers directly)
4. API info:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/api/info`
   - Expected: `200`
5. API base path (sanity, optional):
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/api/`
   - Expected: usually `404` (must not be `502`)
6. API protected endpoint without auth:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/api/teams`
   - Expected: `401` or `403` (depending middleware)
7. Login page:
   - `curl -I "https://fe6103-c0005.sna94.uni-tuebingen.de/login?redirect=https://fe6103-c0005.sna94.uni-tuebingen.de"`
   - Expected: `200`

### 2.4 Redirect Sanity (no localhost leakage)

1. Login HTML must not reference localhost:
   - `curl -fsS "https://fe6103-c0005.sna94.uni-tuebingen.de/login?redirect=https://fe6103-c0005.sna94.uni-tuebingen.de" | rg -n "localhost|127\\.0\\.0\\.1|:8080|:3000|:3001" || true`
   - Expected: no output
2. Browser check:
   - DevTools -> Network -> inspect `Location` headers and redirect chain
   - Expected: no `localhost` / `127.0.0.1` in redirect targets

### 2.5 CouchDB Exposure

1. Direct port 5984 should not be host-published:
   - `docker compose -f compose.prod.yml ps -a`
   - Expected: couchdb has no host `PORTS` mapping
2. Internal health should pass:
   - `docker compose -f compose.prod.yml exec couchdb sh -lc "curl -fsS http://127.0.0.1:5984/_up"`
   - Expected: `{"status":"ok"...}`
3. External couch health endpoint should be blocked:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/couchdb/_up`
   - Expected: `404`
4. If `/couchdb/*` route is enabled, verify auth on protected couch endpoints:
   - `curl -I https://fe6103-c0005.sna94.uni-tuebingen.de/couchdb/_all_dbs`
   - Expected: `401`

## 3. Browser URL Matrix (manual)

1. `https://fe6103-c0005.sna94.uni-tuebingen.de/`
   - Expected: web UI loads (`200`)
2. `https://fe6103-c0005.sna94.uni-tuebingen.de/app/`
   - Expected: app UI loads (`200`)
3. `https://fe6103-c0005.sna94.uni-tuebingen.de/api/info`
   - Expected: JSON response (`200`)
4. `https://fe6103-c0005.sna94.uni-tuebingen.de/api/teams`
   - Expected while logged out: auth error (`401/403`)
5. `https://fe6103-c0005.sna94.uni-tuebingen.de/login?redirect=https://fe6103-c0005.sna94.uni-tuebingen.de`
   - Expected: login form (`200`)

## 4. Auth Flow Manual Test

1. Open login URL above.
2. Authenticate with valid account.
3. In DevTools Network, inspect auth requests:
   - `POST /auth/local` -> expected `302`
   - `POST /api/auth/exchange` -> expected `200`
4. After success, verify redirect lands on intended app/web route (for example `/teams`).
5. Confirm no redirect URL contains `localhost` or `127.0.0.1`.
6. If browser falls back to `/login?redirect=...` after successful credentials:
   - check API log for `POST /api/auth/exchange ... 500`
   - run: `docker compose -f compose.prod.yml exec api sh -lc "id && ls -l /app/keys/*_private_key.pem && test -r /app/keys/default_private_key.pem && echo KEY_READABLE || echo KEY_NOT_READABLE"`
   - expected: `KEY_READABLE` (if not, regenerate keys and/or `chmod 644 api/keys/*_private_key.pem api/keys/*_public_key.pem`)
7. For mobile callback validation:
   - confirm `REDIRECT_WHITELIST` contains `org.fedarch.faims3://auth-return`
   - run one mobile login roundtrip and confirm callback scheme is used.

## 5. Definition of Done (DoD)

All conditions must be true:

1. `docker compose -f compose.prod.yml ps -a` shows all services `Up`, couchdb `healthy`.
2. Only Caddy publishes host ports 80/443.
3. Root and `/app/` return 200 and contain no `@vite/client`.
4. `/api/info` returns 200 and `/api/teams` is auth-protected (401/403 when logged out).
5. Login + post-login navigation works without localhost redirects (`POST /api/auth/exchange` returns 200).
6. API logs show no key-file missing errors.
7. CouchDB is not directly exposed via host `:5984`.
8. Container starts do not run build jobs each restart.

## 6. Mobile App Validation (Current)

1. Device recognized: `adb devices` shows hardware device connected.
2. App reset before test:
   - `adb shell pm clear org.fedarch.faims3`
3. Launch flow observed in logs:
   - Browser plugin opens: `https://fe6103-c0005.sna94.uni-tuebingen.de/login?redirect=org.fedarch.faims3://auth-return`
   - Deep link callback to `org.fedarch.faims3://auth-return/...` is triggered.
4. No obvious TLS trust errors in current log sample:
   - no `SSLHandshakeException`, no certificate trust failure entries.
5. If login still fails in-app, collect correlated server logs while reproducing:
   - `docker compose -f compose.prod.yml logs -f --tail=200 api caddy`
   - focus on `/api/auth/exchange` status and payload validation messages.

## 7. Security Review and Recommendations

### 7.1 Vite `allowedHosts`

Current production recommendation:

1. Do not use `allowedHosts: true` in prod-facing preview.
2. Restrict to explicit hosts only, e.g.:
   - `fe6103-c0005.sna94.uni-tuebingen.de`
   - `localhost`
   - `127.0.0.1`
3. Keep host list configurable via env for migrations.

### 7.2 Caddy Headers and Proxy

1. Ensure Host/Proto forwarding is preserved (default reverse_proxy behavior).
2. API should trust proxy behind Caddy (`TRUST_PROXY=1`) to avoid rate-limit misclassification.
3. Keep TLS on 443 only and avoid exposing backend service ports.

### 7.3 CouchDB Exposure

1. Never publish couchdb `5984` directly to host.
2. If `/couchdb/*` is needed for app sync, protect sensitive endpoints (auth required) and monitor access logs.
3. If app architecture allows, prefer removing public `/couchdb/*` route entirely.
4. At minimum, avoid exposing operational endpoints publicly unless needed (`/_up`, config routes).

### 7.4 Secrets and Env Hygiene

1. Replace placeholder secrets in `ops/api.env.prod` before real production use.
2. Keep `.env.prod` and keys generation deterministic and documented.
3. Restrict redirect whitelist to exact required origins and custom schemes.
