# SteamCMD Setup GUI

A small Windows GUI (PowerShell + WinForms) for installing and updating SteamCMD and managing Steam dedicated servers.

## Features
- Download, install and self-update SteamCMD
- Install or update any Steam app by App ID (anonymous or account login)
- Searchable Steam game list with App IDs (dedicated-server filter)
- "My servers" list with per-server auto-update on start
- Auto-check for new builds on a timer, with optional auto-install
- Steam Workshop mods per server: add by ID or URL, names looked up automatically, auto-download on update/start, optional copy into a mods folder
- Generates per-server launcher `.bat` files (never contain your password)

## Usage
1. Download `SteamCMD-Setup.ps1` and `Run-SteamCMD-Setup.bat` into the same folder.
2. Double-click `Run-SteamCMD-Setup.bat`.
3. On the **Setup** tab, click **Install / Update SteamCMD**.

If Windows blocks the script: right-click the `.ps1` > Properties > Unblock.

## Notes
- Requires Windows PowerShell 5.1 or newer.
- Settings are stored in `%APPDATA%\steamcmd-gui.json`, outside this repo.
- A remembered password is encrypted with Windows DPAPI (current user, this PC only).
- Not affiliated with Valve. SteamCMD is downloaded from Valve's servers.
