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
<img width="753" height="710" alt="Screenshot 2026-10-28 203935" src="https://github.com/user-attachments/assets/99655c76-eae2-4ab3-89a2-26b5661ce56c" />
<img width="760" height="726" alt="Screenshot 2026-10-28 203952" src="https://github.com/user-attachments/assets/0da18291-6290-4df4-a79c-7651e3314b0e" />
<img width="753" height="703" alt="Screenshot 2026-10-28 204009" src="https://github.com/user-attachments/assets/93a720fd-cbd8-4340-a65e-167e3374ed71" />
<img width="757" height="702" alt="Screenshot 2026-10-28 223405" src="https://github.com/user-attachments/assets/0b9ef0ca-099f-4e63-8513-1f4622509953" />
