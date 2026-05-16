# BAPBAP Custom Server GitHub AutoInstall AMP Template

This template is the recommended web-panel-only deployment path.

AMP install/update flow:

1. AMP runs the Generic module update.
2. The template downloads `bapcustomserver-amp-full-linux-wine.zip` from a GitHub Release.
3. AMP unzips it into the instance root.
4. AMP marks the Linux start files executable.
5. Start uses `/bin/sh ./BapCustomServer/amp-webpanel-start.sh`, so the first process is a system executable and does not depend on ZIP-preserved executable bits.

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

For updates later, publish a new GitHub Release with the same asset name and
press `Update` in AMP.
