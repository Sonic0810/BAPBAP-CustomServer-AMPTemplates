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
5. Open `http://ark.atomi23.de:5055/health`; expected response includes
   `"ok":true` and the current release label.

Current packaged release:

```text
bapcustomserver-20260531-medusa-v172
```

Current tested mod DLL SHA256:

```text
3E796F1E22D124F6433DAE5BC67149A4A25D0CB5FD607DAB11FFE6934EA15E8D
```

Current Medusa artifacts:

```text
BAPBAP.ModAPI.dll 0E14F39A9C47B6EBA106A0F23E76A0989B3270D7BCDD3E4BB0DD51E63BDB3CB5
BAPBAP.Medusa.dll 4D3050CAC36C94AA726F575DE2F271A34248EB70CC81D6C55D27F2248CFBA16C
medusa.bundle     2F2CCF12032185E8ED66652417BDEADA764299C523073B7A77205391BA8A2A02
```

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

Required Linux/Wine runtime:

- Wine with 32-bit support (`wine`, `wine32`, `wine64`).
- `xvfb` and `xauth`.
- Mesa software graphics packages, including i386 variants.
- No `winetricks` step is required for the proven path.

The match launcher must remain `./start-match.sh`. Do not replace it with raw
`wine` or `xvfb-run`, because the wrapper owns diagnostics, Wine prefix reset,
software graphics defaults, and Unity graphics mode selection.

Before publishing, run the local Linux-layout smoke test:

```powershell
.\tools\Test-AmpLinuxWinePackageInWsl.ps1
```

After pressing `Update` and `Start` on the real AMP instance, use both live
checks before calling the host ready:

```powershell
.\tools\Test-AmpLivePublic.ps1 -FailOnUnreachable
```

```bash
curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/verify-amp-instance.sh | sudo docker exec -i AMP_BAPBAPModding01 bash -s
```

The public check proves DNS, release assets, raw AMP template files, and
externally reachable `/health`/TCP ports. The container check proves the live
AMP filesystem, hashes, appsettings, local health, and current `ss` port state.

For updates later, publish a new GitHub Release with the same asset name and
press `Update` in AMP. This refreshes server/game/mod files and the AMP UI template files while preserving `data/**` and `logs/**`.
