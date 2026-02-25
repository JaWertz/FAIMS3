# FAIMS3 Android Build + Installation (USB Device, Schritt-für-Schritt)

Ziel: APK bauen, per USB auf echtes Android-Gerät installieren und Login testen.

## 0) Voraussetzungen

1. Backend läuft (`compose.prod.yml`) und Domain antwortet über HTTPS:
   - `https://fe6103-c0005.sna94.uni-tuebingen.de`
2. Android Studio ist auf Windows installiert.
3. Android SDK liegt unter:
   - `C:\Users\Jakob\AppData\Local\Android\Sdk`
4. Gerät ist per USB verbunden.

## 1) Android-Gerät vorbereiten

Auf dem Handy:

1. `Einstellungen -> Telefoninfo -> Softwareinformationen -> Buildnummer` 7x tippen.
2. `Einstellungen -> Entwickleroptionen` öffnen.
3. `USB-Debugging` einschalten.
4. USB-Kabel an PC, USB-Modus auf `Dateiübertragung` stellen.
5. RSA-Abfrage auf dem Gerät bestätigen: `Immer zulassen` + `OK`.

Optional (nur für manuelle APK-Installation per Dateimanager):
1. `Install unknown apps` für den Dateimanager erlauben.
2. Für `adb install` ist das normalerweise nicht nötig.

## 2) Projekt nach Windows spiegeln (WSL)

```bash
mkdir -p /mnt/c/dev/faims3-win
rsync -a --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '**/node_modules' \
  /home/jakob/projects/faims3/ /mnt/c/dev/faims3-win/
```

Hinweis: `.git` wird absichtlich nicht mitkopiert. Deshalb muss der Commit-Hash unten manuell gesetzt werden.

## 3) Web-Bundle + Capacitor Sync bauen (WSL)

```bash
cd /mnt/c/dev/faims3-win
corepack enable
pnpm install --frozen-lockfile

# About Build -> Version korrekt setzen
export VITE_COMMIT_VERSION="$(git -C /home/jakob/projects/faims3 rev-parse --short=9 HEAD)"

source ops/java17-env.sh
./ops/build-mobile-android.sh
```

Soll-Ergebnis:
1. `webapp-build` erfolgreich
2. `webapp-sync -- android` erfolgreich

## 4) APK unter Windows bauen (PowerShell)

In **Windows PowerShell**:

```powershell
cd C:\dev\faims3-win\app\android

$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_SDK_ROOT="$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_HOME="$env:LOCALAPPDATA\Android\Sdk"
$env:APP_ID="org.fedarch.faims3"

"sdk.dir=$($env:LOCALAPPDATA -replace '\\','/')/Android/Sdk" | Out-File -Encoding ascii .\local.properties

# wichtig: Daemon neu starten, damit geänderte ENV (APP_ID) sicher greift
& .\gradlew.bat --stop
& .\gradlew.bat clean assembleDebug
```

APK liegt danach unter:

`C:\dev\faims3-win\app\android\app\build\outputs\apk\debug\app-debug.apk`

Wenn Build-Tools fehlen/defekt sind:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --install "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

## 5) APK auf Gerät installieren (WSL oder PowerShell)

Beispiel in WSL:

```bash
adb kill-server
adb start-server
adb devices

adb uninstall org.fedarch.faims3 || true
# WICHTIG: Wenn `adb version` "Running on Windows" zeigt, Windows-Pfad nutzen
adb install -r "$(wslpath -w /mnt/c/dev/faims3-win/app/android/app/build/outputs/apk/debug/app-debug.apk)"
adb shell pm clear org.fedarch.faims3
adb shell monkey -p org.fedarch.faims3 -c android.intent.category.LAUNCHER 1
```

Wenn `No activities found` erscheint:
1. Prüfen, welche Package-ID tatsächlich installiert wurde:
   - `adb shell pm list packages | rg -i "faims|fieldmark|fedarch"`
2. Wenn nur `au.edu.faims.fieldmark` da ist, wurde ohne `APP_ID` gebaut.
   - In Schritt 4 `APP_ID` setzen und APK neu bauen/installieren.

Wenn `adb devices` leer ist:
1. USB-Kabel neu verbinden
2. USB-Debugging am Gerät aus/an
3. RSA-Prompt erneut bestätigen

## 6) Login-Test

In der App:

1. Server: `https://fe6103-c0005.sna94.uni-tuebingen.de`
2. Shortcode mit Prefix `FAIMS-XXXXXX` testen
3. QR-Login testen

Parallel Logs:

WSL (Server):

```bash
cd /home/jakob/projects/faims3
docker compose -f compose.prod.yml logs -f --tail=200 api caddy
```

WSL (Device-App):

```bash
adb logcat -c
adb logcat -v time | rg -i "org\\.fedarch\\.faims3|auth/exchange|invalid prefix|token is not valid|ssl|cert|failed to fetch"
```

## 7) Wichtige Env-Checks (Backend)

In `ops/api.env.prod`:

1. `CONDUCTOR_PUBLIC_URL=https://fe6103-c0005.sna94.uni-tuebingen.de`
2. `REDIRECT_WHITELIST` enthält:
   - `https://fe6103-c0005.sna94.uni-tuebingen.de`
   - `org.fedarch.faims3://auth-return`

## 8) TLS-Hinweis

Für Geräte-Tests ACME/öffentliches Zertifikat verwenden (Let’s Encrypt).  
`tls internal` verursacht auf echten Geräten oft Trust-Probleme.
