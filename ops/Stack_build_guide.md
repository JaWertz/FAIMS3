# FAIMS3 Stack Build Guide (Neuer Server, kompletter Ablauf)

Ziel: Einen neuen Server von 0 aufsetzen und den aktuellen Stack so bauen, dass Login und Sync stabil funktionieren.

## 1) Infrastruktur-Voraussetzungen

1. Domain zeigt per DNS-A/AAAA auf den Server.
2. Ports `80/tcp` und `443/tcp` sind offen (Cloud-Firewall + Host-Firewall).
3. Docker ist installiert und lauffaehig.
4. Git ist installiert.

Hinweis: Dieser Guide geht von Linux/WSL mit Docker Compose Plugin aus.

## 2) Host vorbereiten (Ubuntu Beispiel)

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg git

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
newgrp docker

docker info
docker compose version
```

## 3) Repo holen

```bash
mkdir -p /home/jakob/projects
cd /home/jakob/projects
git clone <REPO_URL> faims3
cd /home/jakob/projects/faims3
```

Wenn du schon ein Repo auf dem Zielserver hast: nur `cd /home/jakob/projects/faims3`.

## 4) Produktions-Konfiguration setzen

Passe mindestens diese Dateien an:

1. `ops/Caddyfile`
2. `ops/api.env.prod`
3. `web/.env.prod`
4. `app/.env.prod`
5. `api/.env.keygen` (neu anlegen oder aktualisieren)

Pflicht-Regeln:

1. Ueberall dieselbe Domain verwenden.
2. `ops/api.env.prod`:
   - `CONDUCTOR_PUBLIC_URL` und `NEW_CONDUCTOR_URL` auf die Domain
   - `COUCHDB_PUBLIC_URL=https://<DOMAIN>/couchdb`
   - `REDIRECT_WHITELIST` enthaelt Domain und App-Scheme
   - `FAIMS_COOKIE_SECRET` und `COUCHDB_SECRET` auf lange Random-Werte setzen
3. `app/.env.prod`:
   - `VITE_CONDUCTOR_URL`, `VITE_COUCHDB_URL`, `VITE_WEB_URL`, `VITE_APP_URL` korrekt
   - `VITE_BASE_PATH=/app/`
4. `web/.env.prod`:
   - `VITE_API_URL`, `VITE_CONDUCTOR_URL`, `VITE_COUCHDB_URL`, `VITE_WEB_URL`, `VITE_APP_URL` korrekt
5. `api/.env.keygen`:
   - `PROFILE_NAME=default`
   - `FAIMS_COOKIE_SECRET=<gleich wie in ops/api.env.prod>`
   - `COUCHDB_PASSWORD=<gleich wie in ops/api.env.prod>`

Falls `api/.env.keygen` fehlt, neu anlegen:

```bash
cat > api/.env.keygen <<'EOF'
PROFILE_NAME=default
FAIMS_COOKIE_SECRET=<SET_ME_64_HEX_CHARS>
COUCHDB_PASSWORD=<SET_ME>
EOF
```

Beispiel fuer sichere Secrets:

```bash
openssl rand -hex 32
```

Hinweis zur Laenge:

1. Es gibt im Code keine harte Mindestlaenge fuer `FAIMS_COOKIE_SECRET`.
2. Fuer Produktion mindestens 32 Zeichen, empfohlen 64+ zufaellige Zeichen.
3. `openssl rand -hex 32` liefert 64 Hex-Zeichen und ist dafuer geeignet.

## 5) JWT/CouchDB-Keymaterial erzeugen (Pflicht)

```bash
cd /home/jakob/projects/faims3
./api/keymanagement/makeInstanceKeys.sh ./api/.env.keygen
rg -n "^\[jwt_keys\]|^rsa:" api/couchdb/local.ini
```

Erwartung: `[jwt_keys]` und eine Zeile `rsa:default=...` in `api/couchdb/local.ini`.

## 6) Stack bauen und starten

```bash
cd /home/jakob/projects/faims3
docker compose -f compose.prod.yml build
docker compose -f compose.prod.yml up -d
docker compose -f compose.prod.yml ps
```

Erwartung:

1. `couchdb` wird `healthy`
2. `api`, `web`, `app`, `caddy` sind `Up`

## 7) Datenbanken initialisieren/migrieren (Pflicht auf frischem Server)

Auf diesem Build-Setup liegt das Migrationsskript kompiliert im Container:

```bash
cd /home/jakob/projects/faims3
docker compose -f compose.prod.yml exec -T api sh -lc \
  'node /app/api/build/src/scripts/migrate.js --keys'
```

Erwartung: Ausgabe endet mit `Migration completed successfully`.

## 8) Verifikation nach Erstaufbau (Pflichttests)

### 8.1 Endpunkte

```bash
DOMAIN=<DEINE_DOMAIN>
curl -I https://$DOMAIN/
curl -I https://$DOMAIN/app/
curl -I https://$DOMAIN/api/info
```

Erwartung: jeweils `200`.

### 8.2 JWT-Key aktiv im laufenden CouchDB

```bash
docker compose -f compose.prod.yml exec -T couchdb sh -lc \
  'sed -n "/\[jwt_keys\]/,/^\[/p" /opt/couchdb/etc/local.d/local.ini'
```

Erwartung: `rsa:default=...` ist sichtbar.

### 8.3 Login + Sync Echt-Test

Terminal 1:

```bash
cd /home/jakob/projects/faims3
timeout 120s docker compose -f compose.prod.yml logs -f --since=0s api couchdb caddy \
| grep -Ei "auth/refresh|_revs_diff|_changes|sync-status|unauthorized|exp not in future|Unknown kid| 400 | 401 "
```

Terminal 2:

1. In App einloggen.
2. Survey oeffnen.
3. Datensatz anlegen.

Erwartung:

1. `POST /api/auth/refresh` liefert `200`.
2. `_revs_diff` und `_changes` laufen nicht dauerhaft auf `401/400`.
3. `sync-status` bleibt `200`.

## 9) Update-Prozess auf bestehendem Server

```bash
cd /home/jakob/projects/faims3
git pull

# nur noetig wenn Key/Secret/Profile geaendert wurde:
./api/keymanagement/makeInstanceKeys.sh ./api/.env.keygen

docker compose -f compose.prod.yml build
docker compose -f compose.prod.yml up -d --force-recreate
```

Bei Aenderung der Keys immer `couchdb` neu bauen, sonst ist `local.ini` im Image alt.

## 10) Typische Fehlerbilder

1. Login geht, Sync geht nicht (`401/400` auf `_revs_diff`/`_changes`):
   - `jwt_keys` fehlt oder `kid` passt nicht.
2. ACME/Let's Encrypt scheitert:
   - DNS falsch oder Port 80/443 geblockt.
3. `permission denied /var/run/docker.sock`:
   - Benutzer nicht in `docker`-Gruppe oder Session neu starten.

## 11) Was nach dem Build unbedingt getestet werden muss

Ja, Tests sind noetig. Minimum:

1. `docker compose ps` (Health)
2. `curl` auf `/`, `/app/`, `/api/info`
3. Login + echter Datensatz-Sync mit Live-Logs (8.3)
