# FAIMS3 Stack nach PC-Neustart starten (kurz)

## 1) Docker Desktop/WSL sauber starten

In **Windows PowerShell als Admin**:

```powershell
wsl --shutdown
net start com.docker.service
```

Falls Docker Desktop nicht automatisch startet:

```powershell
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

## 2) In WSL prüfen, ob Docker bereit ist

```bash
until docker info >/dev/null 2>&1; do echo "Warte auf Docker..."; sleep 2; done
docker version
```

## 3) Prod-Stack starten

```bash
cd /home/jakob/projects/faims3
docker compose -f compose.prod.yml up -d
docker compose -f compose.prod.yml ps
```

Soll-Zustand:
1. `caddy`, `api`, `web`, `app` = `Up`
2. `couchdb` = `healthy`

## 4) Schnelltests

```bash
DOMAIN=fe6103-c0005.sna94.uni-tuebingen.de
curl -I https://$DOMAIN/
curl -I https://$DOMAIN/app/
curl -I https://$DOMAIN/api/info
curl -I https://$DOMAIN/couchdb/_up
```

Erwartung:
1. `/` = `200`
2. `/app/` = `200`
3. `/api/info` = `200`
4. `/couchdb/_up` = `404` (absichtlich geblockt)

Hinweis CouchDB-Zugriff:
Browser-Zugriff läuft über Caddy: `https://fe6103-c0005.sna94.uni-tuebingen.de/couchdb/_utils/`

## 5) Wenn es hakt (typisch nach Neustart)

```bash
docker compose -f compose.prod.yml logs --tail=120 caddy api couchdb
docker compose -f compose.prod.yml down
docker compose -f compose.prod.yml up -d
```
