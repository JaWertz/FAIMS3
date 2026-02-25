# FAIMS3: TERRA-FAIMS vs Standard-Version

Stand: 2026-02-23  
Zielsystem: `fe6103-c0005.sna94.uni-tuebingen.de`  
Betriebskontext: Windows 11 + WSL2 + Docker Desktop + Caddy + HTTPS

## 1. Kurzfassung

Die Standard-FAIMS3-Entwicklung ist auf lokale Entwicklung ausgelegt (Hot Reload, offene Ports, Dev-Server).  
Wir haben das Setup auf einen stabileren, extern erreichbaren "prod-ish" Betrieb umgestellt:

1. Öffentliche Domain + öffentlich vertrauenswürdiges TLS (Let's Encrypt).
2. Kein Vite-Dev-Server im Endzustand.
3. Keine `localhost`-Redirects in Auth-Flows.
4. Nur Caddy ist von außen erreichbar, interne Services bleiben intern.
5. Mobile-Login-Flow wurde auf echte HTTPS-URL + App-Callback ausgerichtet.

## 2. Wichtige Änderungen im Detail

## 2.1 Eigenes Prod-Compose statt nur Standard-Compose

Was wurde geändert:
1. Neue Datei `compose.prod.yml`.
2. Service-Ports für `api`, `web`, `app`, `couchdb` nicht mehr direkt nach außen veröffentlicht.
3. Caddy ist der einzige öffentliche Einstieg (`80/443`).

Warum:
1. Sauberer Trennschnitt zwischen Dev-Betrieb und produktionsnahem Betrieb.
2. Weniger Angriffsfläche und weniger Verbindungschaos.

## 2.2 Reverse Proxy über Caddy + echtes ACME-Zertifikat

Was wurde geändert:
1. Eigene Proxy-Konfiguration in `ops/Caddyfile`.
2. Routing:
   - `/` -> Web UI
   - `/app/` -> App UI
   - `/api/*` + Login/Auth-Routen -> API
3. TLS mit ACME (Let's Encrypt) statt `tls internal`.

Warum:
1. Mobile Geräte vertrauen öffentlichen Zertifikaten automatisch.
2. Interne Caddy-CA erzeugt auf echten Geräten oft Zertifikatsfehler.

## 2.3 Dev-Betrieb entfernt: Web/App werden gebaut und dann nur ausgeliefert

Was wurde geändert:
1. Neue Dockerfiles:
   - `ops/web.prod.Dockerfile`
   - `ops/app.prod.Dockerfile`
2. Build passiert im Image-Build.
3. Laufzeit startet `vite preview` auf fertigen Build-Artefakten, nicht `vite dev`.

## 2.4 Produktions-URL- und Redirect-Konfiguration

Was wurde geändert:
1. Produktionsnahe API-Umgebung in `ops/api.env.prod`.
2. Web/App-Prod-Umgebungen:
   - `web/.env.prod`
   - `app/.env.prod`
3. Redirect-Whitelist enthält:
   - `https://fe6103-c0005.sna94.uni-tuebingen.de`
   - `org.fedarch.faims3://auth-return`

## 2.5 Interne Services absichern (CouchDB/API nicht direkt öffentlich)

Was wurde geändert:
1. CouchDB-Port `5984` ist nicht öffentlich gepublished.
2. In Caddy wird `/couchdb/_up` mit `404` beantwortet.

## 2.6 API-Keys und Signaturpfade für stabile Auth

Was wurde geändert:
1. Schlüssel als Volume-Mount: `./api/keys:/app/keys:ro`.
2. API wird mit Key-File-Konfiguration gestartet (`KEY_SOURCE=FILE`, `PROFILE_NAME=default`).

Warum:
1. Die API muss bei jedem Start sicher dieselben Schlüssel finden.
2. Schreibschutz (`:ro`) senkt das Risiko versehentlicher Änderungen.

## 2.7 Mobile-Build-Helfer, aber nah an FAIMS-Standardfluss

Was wurde geändert:
1. Neue Hilfsdateien:
   - `ops/build-mobile-android.sh`
   - `ops/app.mobile.env.prod`
   - `ops/java17-env.sh`
   - `ops/MOBILE_ANDROID_BUILD.md`
2. Build-Reihenfolge bleibt FAIMS-konform:
   - `pnpm run webapp-build`
   - `pnpm run webapp-sync -- android`

## 2.8 App-Code-Anpassungen gegenüber Upstream (wichtige Abweichung)

Was wurde geändert:
1. In `app/src/App.tsx` wird `basename` aus `VITE_BASE_PATH` verwendet.
2. Auth-Redirect-URL wird zentral über Helper gebaut:
   - `app/src/utils/helpers.tsx`
   - genutzt in mehreren Login-/Shortcode-Komponenten.
3. `app/vite.config.ts` wurde erweitert:
   - `base` aus Env
   - `allowedHosts` über `VITE_ALLOWED_HOSTS`

Warum:
1. Die App läuft unter `/app/` statt Domain-Root.
2. Ohne diese Anpassung landeten Redirects/Assets an falschen Pfaden.
3. `allowedHosts` verhindert Host-Header-Probleme beim Zugriff über echte Domain.

Hinweis:
1. Dieser Punkt ist die größte echte Code-Abweichung von Upstream.
-> Bei zukünftigen Updates sollte er besonders geprüft werden.

## 2.9 Test- und Betriebsdokumentation ergänzt

Was wurde geändert:
1. `ops/PROD_MANUAL_TESTPLAN.md` für reproduzierbare manuelle Abnahme.

## 3. Risiken und Wartungshinweise

1. App-Code-Diffs (Abschnitt 2.8) bei jedem Upstream-Update gezielt nachziehen.
2. Platzhalter-Secrets in `ops/api.env.prod` vor echtem Produktivbetrieb ersetzen.
3. Caddy/ACME regelmäßig prüfen (Zertifikatsverlängerung, DNS/Firewall).

## 4. Dateiliste der wesentlichen Abweichungen

1. `compose.prod.yml`
2. `ops/Caddyfile`
3. `ops/api.env.prod`
4. `web/.env.prod`
5. `app/.env.prod`
6. `ops/web.prod.Dockerfile`
7. `ops/app.prod.Dockerfile`
8. `ops/build-mobile-android.sh`
9. `ops/app.mobile.env.prod`
10. `ops/java17-env.sh`
11. `ops/MOBILE_ANDROID_BUILD.md`
12. `ops/PROD_MANUAL_TESTPLAN.md`
13. `app/src/App.tsx`
14. `app/src/utils/helpers.tsx`
15. `app/src/gui/components/authentication/cluster_card.tsx`
16. `app/src/gui/components/authentication/login_form.tsx`
17. `app/src/gui/components/authentication/oneServerLanding.tsx`
18. `app/src/gui/components/authentication/shortCodeOnly.tsx`
19. `app/src/gui/pages/shortcode.tsx`
20. `app/vite.config.ts`

