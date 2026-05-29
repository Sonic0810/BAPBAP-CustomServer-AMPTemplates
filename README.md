# BAPBAP Custom Server GitHub AutoInstall AMP Template

This template is the recommended web-panel-only deployment path.

AMP install/update flow:

1. AMP runs the Generic module update.
2. The update manifest syncs the latest KVP/configmanifest/metaconfig/ports/update JSON from GitHub raw into the AMP instance root. New AMP UI fields therefore arrive through the normal `Update` button and apply on the next start/reload.
3. The template downloads `bapcustomserver-amp-full-linux-wine.zip` from a GitHub Release.
4. AMP unzips it into the instance base directory (`BapCustomServer/`).
5. AMP marks the Linux start files executable.
6. Start uses `/bin/sh ./amp-webpanel-start.sh` from that base directory, so the first process is a system executable and does not depend on ZIP-preserved executable bits.

The KVP uses the same layout as normal AMP configuration repositories:
`App.UpdateSources=@IncludeJson[bapcustomservergithubupdates.json]`. Keep the
KVP, updates JSON, and `manifest.json` in the repository root when using AMP's
remote configuration source feature.

Use a private GitHub repository unless you explicitly have redistribution rights
for every included game file. Do not commit the game payload into git; upload it
as a GitHub Release asset.

Build the template package:

```powershell
.\tools\Build-AmpGitHubAutoInstallPackage.ps1 -Repository OWNER/REPO
```

Generated archive:

```text
deployment\amp-github-autoinstall\bapcustomserver-github-autoinstall-template.zip
```

Required release asset name by default:

```text
bapcustomserver-amp-full-linux-wine.zip
```

Web panel install:

1. Import `bapcustomserver-github-autoinstall-template.zip`.
2. Create a new instance from `BAPBAP Custom Server GitHub AutoInstall`.
3. Press `Update` once. This downloads and installs the full package.
4. Press `Start`.
5. Open `http://ark.atomi23.de:5055/health`; expected response is `{"ok":true}`.

Preserved runtime data:

- The update ZIP must not contain `data/**` or `logs/**`.
- The server stores player accounts, purchases/economy, friends, ranked state, admin state, match history, audit logs, and game logs only under those preserved directories.
- Dedicated game config under `game/Mods/` and `game/UserData/` is refreshed by updates; those files are runtime/mod configuration, not player state.

AMP map toggles:

- `mapId=1`: `Map2_BazaarCity 3`
- `mapId=2`: `Map3_Lyceum`
- `mapId=3`: `Arena_Map2`
- `mapId=4`: `OpenBetaMap#J02_P_Boccato`

The server picks the map once per match and reuses that same value for `/setup-game`, `QUEUE_MATCHED`, and `GAME_STARTED`.

Required port exposure:

- `5055/tcp` for lobby/API/WebSocket.
- `7777/tcp` for match WebSocket.
- `7778/udp` for match KCP.
- `7779/tcp` for match TCP fallback.
- `7850/tcp` for bootstrap HTTP if the AMP/container setup requires explicit exposure.

Before publishing, run the local Linux-layout smoke test:

```powershell
.\tools\Test-AmpLinuxWinePackageInWsl.ps1
```

For updates later, publish a new GitHub Release with the same asset name and
press `Update` in AMP. This refreshes server/game/mod files and the AMP UI template files while preserving `data/**` and `logs/**`.
