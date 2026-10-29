Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$zipUrl    = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
$cfgPath   = Join-Path $env:APPDATA 'steamcmd-gui.json'
$cachePath = Join-Path $env:APPDATA 'steamcmd-gui-apps.json'

# Built-in fallback list (used if the Steam list can't be fetched). Verify IDs if one fails.
$fallback = @(
    @('Valheim Dedicated Server',896660), @('Rust Dedicated Server',258550),
    @('ARK: Survival Evolved Dedicated Server',376030), @('7 Days to Die Dedicated Server',294420),
    @('Project Zomboid Dedicated Server',380870), @('Palworld Dedicated Server',2394010),
    @("Garry's Mod Dedicated Server",4020), @('Left 4 Dead 2 Dedicated Server',222860),
    @('Team Fortress 2 Dedicated Server',232250), @('Satisfactory Dedicated Server',1690800),
    @("Don't Starve Together Dedicated Server",343050), @('Conan Exiles Dedicated Server',443030),
    @('Squad Dedicated Server',403240), @('Insurgency: Sandstorm Dedicated Server',581330),
    @('V Rising Dedicated Server',1829350), @('Enshrouded Dedicated Server',2278520),
    @('Counter-Strike 2 (server files)',730)
) | ForEach-Object { [pscustomobject]@{ Name = $_[0]; AppId = [int]$_[1] } }

$defaults = @{ SteamCmdDir='C:\steamcmd'; GamesRoot='C:\servers'; AppId=''; GameDir='C:\servers\game'
               Anonymous=$true; Username=''; Validate=$true; ApiKey=''; DedOnly=$true; RememberPw=$false; PwEnc=''; AutoCheck=$false; CheckMins=60; AutoInstall=$false }
$cfg = $defaults
$script:servers = New-Object System.Collections.ArrayList
$script:apps = @()
$script:loading = $false
$script:busy = $false
$script:lastCheck = Get-Date

if (Test-Path $cfgPath) {
    try {
        $saved = Get-Content $cfgPath -Raw | ConvertFrom-Json
        foreach ($k in @($defaults.Keys)) { if ($null -ne $saved.$k) { $cfg[$k] = $saved.$k } }
        foreach ($s in @($saved.Servers)) { if ($s) { [void]$script:servers.Add($s) } }
    } catch {}
}
if (Test-Path $cachePath) {
    try { $script:apps = @(Get-Content $cachePath -Raw | ConvertFrom-Json) } catch {}
}
if ($script:apps.Count -eq 0) { $script:apps = $fallback }

function Save-Config {
    $cfg.SteamCmdDir = $txtCmd.Text; $cfg.AppId = $txtApp.Text; $cfg.GameDir = $txtGame.Text
    $cfg.Anonymous = $chkAnon.Checked; $cfg.Username = $txtUser.Text; $cfg.Validate = $chkVal.Checked
    $cfg.ApiKey = $txtKey.Text; $cfg.DedOnly = $chkDed.Checked
    $cfg.RememberPw = $chkRemember.Checked
    $cfg.AutoCheck = $chkAutoCheck.Checked; $cfg.CheckMins = [int]$numMins.Value; $cfg.AutoInstall = $chkAutoInstall.Checked
    $cfg.PwEnc = ''
    if ($chkRemember.Checked -and $txtPass.Text) {
        # Encrypted with Windows DPAPI: only this Windows user on this PC can decrypt it
        $cfg.PwEnc = ConvertTo-SecureString $txtPass.Text -AsPlainText -Force | ConvertFrom-SecureString
    }
    $cfg.Servers = @($script:servers)
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $cfgPath
}

function Log($msg) { $txtLog.AppendText("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $msg) }

function Browse($box) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($box.Text -and (Test-Path $box.Text)) { $d.SelectedPath = $box.Text }
    if ($d.ShowDialog() -eq 'OK') { $box.Text = $d.SelectedPath }
}

function Run-Wait($exe, $argList) {
    $p = Start-Process -FilePath $exe -ArgumentList $argList -PassThru
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
    }
    return $p.ExitCode
}

function Set-Busy($busy) {
    $script:busy = $busy
    foreach ($b in @($btnSteam, $btnGame, $btnRefresh, $btnUpdateNow, $btnStartSrv, $btnCheckNow)) { $b.Enabled = -not $busy }
    $form.Cursor = if ($busy) { 'WaitCursor' } else { 'Default' }
}

function Safe-Name($n) { (($n -replace '[^\w\- ]', '').Trim() -replace '\s+', '-') }

function Get-UpdateArgs($appId, $dir, $forFile = $false) {
    # Launcher .bat files never contain the password: they rely on SteamCMD's cached login
    $login = '+login anonymous'
    if (-not $chkAnon.Checked) {
        $login = "+login $($txtUser.Text.Trim())"
        if ($txtPass.Text -and -not $forFile) { $login += " `"$($txtPass.Text)`"" }
    }
    $val = if ($chkVal.Checked) { ' validate' } else { '' }
    return "+force_install_dir `"$dir`" $login +app_update $appId$val +quit"
}

# ---------------- UI helpers ----------------
function Add-Label($p, $text, $x, $y, $bold = $false) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true
    if ($bold) { $l.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5) }
    $p.Controls.Add($l); return $l
}
function Add-Text($p, $x, $y, $w, $text) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y); $t.Width = $w; $t.Text = $text
    $p.Controls.Add($t); return $t
}
function Add-Button($p, $text, $x, $y, $w, $h = 30) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, $h)
    $p.Controls.Add($b); return $b
}
function Add-Check($p, $text, $x, $y, $checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text; $c.Location = New-Object System.Drawing.Point($x, $y); $c.AutoSize = $true; $c.Checked = [bool]$checked
    $p.Controls.Add($c); return $c
}
function Add-ListView($p, $x, $y, $w, $h) {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.GridLines = $true; $lv.HideSelection = $false
    $lv.Location = New-Object System.Drawing.Point($x, $y); $lv.Size = New-Object System.Drawing.Size($w, $h)
    $p.Controls.Add($lv); return $lv
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SteamCMD Setup'
$form.Size = New-Object System.Drawing.Size(760, 700)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10); $tabs.Size = New-Object System.Drawing.Size(725, 520)
$tabSetup = New-Object System.Windows.Forms.TabPage 'Setup'
$tabGames = New-Object System.Windows.Forms.TabPage 'Game list'
$tabSrv   = New-Object System.Windows.Forms.TabPage 'My servers'
$tabs.TabPages.AddRange(@($tabSetup, $tabGames, $tabSrv))
$form.Controls.Add($tabs)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Location = New-Object System.Drawing.Point(10, 540); $txtLog.Size = New-Object System.Drawing.Size(725, 110)
$form.Controls.Add($txtLog)

# ---------------- Tab: Setup ----------------
Add-Label $tabSetup '1. Install / update SteamCMD' 15 12 $true | Out-Null
Add-Label $tabSetup 'SteamCMD folder:' 15 42 | Out-Null
$txtCmd = Add-Text $tabSetup 15 65 480 $cfg.SteamCmdDir
$btnCmdBrowse = Add-Button $tabSetup 'Browse...' 505 63 100 27
$btnSteam = Add-Button $tabSetup 'Install / Update SteamCMD' 15 100 250 34
$btnOpenCmd = Add-Button $tabSetup 'Open folder' 275 100 120 34

Add-Label $tabSetup '2. Install / update a game or server (manual)' 15 155 $true | Out-Null
Add-Label $tabSetup 'App ID:' 15 185 | Out-Null
$txtApp = Add-Text $tabSetup 15 208 200 $cfg.AppId
Add-Label $tabSetup 'Install to folder:' 15 240 | Out-Null
$txtGame = Add-Text $tabSetup 15 263 480 $cfg.GameDir
$btnGameBrowse = Add-Button $tabSetup 'Browse...' 505 261 100 27
$chkAnon = Add-Check $tabSetup 'Anonymous login (works for most dedicated servers)' 15 298 $cfg.Anonymous
$lblUser = Add-Label $tabSetup 'Steam username:' 15 328
$txtUser = Add-Text $tabSetup 15 351 250 $cfg.Username
$lblPass = Add-Label $tabSetup 'Password (blank = type it in the console window):' 280 328
$txtPass = Add-Text $tabSetup 280 351 250 ''
$txtPass.UseSystemPasswordChar = $true
$chkRemember = Add-Check $tabSetup 'Remember' 545 353 $cfg.RememberPw
$chkVal = Add-Check $tabSetup 'Validate files (slower, repairs corrupted installs)' 15 386 $cfg.Validate
$btnGame = Add-Button $tabSetup 'Install / Update Game' 15 418 250 34
$btnOpenGame = Add-Button $tabSetup 'Open folder' 275 418 120 34

function Refresh-Login {
    foreach ($c in @($txtUser, $lblUser, $txtPass, $lblPass, $chkRemember)) { $c.Enabled = -not $chkAnon.Checked }
}
$chkAnon.Add_CheckedChanged({ Refresh-Login })
Refresh-Login

# ---------------- Tab: Game list ----------------
Add-Label $tabGames 'Search Steam apps (press Enter):' 10 10 | Out-Null
$txtSearch = Add-Text $tabGames 10 32 250 ''
$btnSearch = Add-Button $tabGames 'Search' 270 30 70 27
$chkDed = Add-Check $tabGames 'Dedicated servers only' 355 34 $cfg.DedOnly
$btnRefresh = Add-Button $tabGames 'Refresh list from Steam' 10 68 220 32
Add-Label $tabGames 'Steam Web API key (optional, gives a more complete list):' 10 108 | Out-Null
$txtKey = Add-Text $tabGames 10 130 420 $cfg.ApiKey
$lvGames = Add-ListView $tabGames 10 165 690 270
[void]$lvGames.Columns.Add('Name', 540); [void]$lvGames.Columns.Add('App ID', 100)
$btnAddSrv = Add-Button $tabGames 'Add checked to My servers' 10 445 250 34
$lblCount = Add-Label $tabGames '' 280 453

function Refresh-GameList {
    $q = $txtSearch.Text.Trim()
    $rows = $script:apps
    if ($chkDed.Checked) { $rows = $rows | Where-Object { $_.Name -match 'dedicated server|server files' } }
    if ($q) { $rows = $rows | Where-Object { $_.Name -like "*$q*" -or [string]$_.AppId -eq $q } }
    $rows = @($rows | Sort-Object Name)
    $total = $rows.Count
    $rows = $rows | Select-Object -First 1500
    $lvGames.BeginUpdate(); $lvGames.Items.Clear()
    foreach ($a in $rows) {
        $it = New-Object System.Windows.Forms.ListViewItem([string]$a.Name)
        [void]$it.SubItems.Add([string]$a.AppId); $it.Tag = [int]$a.AppId
        [void]$lvGames.Items.Add($it)
    }
    $lvGames.EndUpdate()
    $lblCount.Text = "$total match(es)" + $(if ($total -gt 1500) { ' (showing first 1500, refine your search)' } else { '' })
}

function Get-SteamApps {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $apps = New-Object System.Collections.Generic.List[object]
    $key = $txtKey.Text.Trim()
    if ($key) {
        $last = 0
        do {
            $u = "https://api.steampowered.com/IStoreService/GetAppList/v1/?key=$key&include_games=true&include_software=true&max_results=50000&last_appid=$last"
            $r = (Invoke-RestMethod -Uri $u).response
            foreach ($a in $r.apps) { if ($a.name) { $apps.Add([pscustomobject]@{ Name = [string]$a.name; AppId = [int]$a.appid }) } }
            $more = [bool]$r.have_more_results; $last = $r.last_appid
            [System.Windows.Forms.Application]::DoEvents()
        } while ($more)
    } else {
        $r = Invoke-RestMethod -Uri 'https://api.steampowered.com/ISteamApps/GetAppList/v2/'
        foreach ($a in $r.applist.apps) { if ($a.name) { $apps.Add([pscustomobject]@{ Name = [string]$a.name; AppId = [int]$a.appid }) } }
    }
    return $apps
}

$btnRefresh.Add_Click({
    Save-Config
    Set-Busy $true
    try {
        Log 'Fetching app list from Steam (this can take a moment)...'
        $list = @(Get-SteamApps)
        if ($list.Count -lt 10) { throw 'Steam returned an empty list.' }
        $script:apps = $list
        $serverish = @($list | Where-Object { $_.Name -match 'server' })
        $serverish | ConvertTo-Json | Set-Content $cachePath
        Log "Loaded $($list.Count) apps ($($serverish.Count) server-related cached for next time)."
        Refresh-GameList
    } catch {
        Log "ERROR: $($_.Exception.Message)"
        Log 'Steam may require a Web API key for the full list. Paste one above, or use the built-in list.'
        if ($script:apps.Count -eq 0) { $script:apps = $fallback }
        Refresh-GameList
    }
    Set-Busy $false
})

$btnSearch.Add_Click({ Refresh-GameList })
$txtSearch.Add_KeyDown({ if ($_.KeyCode -eq 'Return') { $_.SuppressKeyPress = $true; Refresh-GameList } })
$chkDed.Add_CheckedChanged({ Refresh-GameList })

# ---------------- Tab: My servers ----------------
$lvSrv = Add-ListView $tabSrv 10 10 690 230
[void]$lvSrv.Columns.Add('Auto-update on start', 130); [void]$lvSrv.Columns.Add('Name', 230)
[void]$lvSrv.Columns.Add('App ID', 70); [void]$lvSrv.Columns.Add('Install folder', 240)
Add-Label $tabSrv 'Install folder:' 10 250 | Out-Null
$txtSDir = Add-Text $tabSrv 10 272 590 ''
$btnSBrowse = Add-Button $tabSrv 'Browse...' 610 270 90 27
Add-Label $tabSrv 'Start command (runs inside the install folder, e.g. start_server.bat or server.exe -port 2456):' 10 305 | Out-Null
$txtSCmd = Add-Text $tabSrv 10 327 690 ''
$btnSaveSrv   = Add-Button $tabSrv 'Save changes' 10 365 130
$btnRemoveSrv = Add-Button $tabSrv 'Remove' 150 365 130
$btnUpdateNow = Add-Button $tabSrv 'Update now' 290 365 130
$btnStartSrv  = Add-Button $tabSrv 'Start server' 430 365 130
$btnLauncher  = Add-Button $tabSrv 'Create launcher' 570 365 130
Add-Label $tabSrv 'Ticked servers auto-update every time you press Start server or run their launcher .bat.' 10 400 | Out-Null
$chkAutoCheck = Add-Check $tabSrv 'Auto-check for updates every' 10 428 $cfg.AutoCheck
$numMins = New-Object System.Windows.Forms.NumericUpDown
$numMins.Location = New-Object System.Drawing.Point(215, 426); $numMins.Width = 60
$numMins.Minimum = 5; $numMins.Maximum = 1440; $numMins.Value = [decimal][Math]::Min(1440, [Math]::Max(5, [int]$cfg.CheckMins))
$tabSrv.Controls.Add($numMins)
Add-Label $tabSrv 'min' 282 430 | Out-Null
$btnCheckNow = Add-Button $tabSrv 'Check for updates now' 480 424 220 30
$chkAutoInstall = Add-Check $tabSrv 'Install automatically when an update is found (close the server first)' 10 458 $cfg.AutoInstall

function Get-SelectedServer {
    if ($lvSrv.SelectedItems.Count -eq 0) { Log 'Select a server in the list first.'; return $null }
    $id = [int]$lvSrv.SelectedItems[0].Tag
    return ($script:servers | Where-Object { [int]$_.AppId -eq $id } | Select-Object -First 1)
}

function Refresh-Servers {
    $script:loading = $true
    $lvSrv.BeginUpdate(); $lvSrv.Items.Clear()
    foreach ($s in $script:servers) {
        $it = New-Object System.Windows.Forms.ListViewItem('')
        [void]$it.SubItems.Add([string]$s.Name); [void]$it.SubItems.Add([string]$s.AppId); [void]$it.SubItems.Add([string]$s.Dir)
        $it.Tag = [int]$s.AppId; $it.Checked = [bool]$s.AutoUpdate
        [void]$lvSrv.Items.Add($it)
    }
    $lvSrv.EndUpdate()
    $script:loading = $false
}

function Update-Server($s) {
    $exe = Join-Path $txtCmd.Text.Trim() 'steamcmd.exe'
    if (-not (Test-Path $exe)) { Log 'SteamCMD not installed yet. Run step 1 on the Setup tab.'; return $false }
    if (-not $chkAnon.Checked -and -not $txtUser.Text.Trim()) { Log 'Enter a Steam username on the Setup tab or tick anonymous.'; return $false }
    New-Item -ItemType Directory -Force -Path $s.Dir | Out-Null
    Log "Updating $($s.Name) (console window will open)..."
    $code = Run-Wait $exe (Get-UpdateArgs $s.AppId $s.Dir)
    if ($code -eq 0) { Log "$($s.Name) is up to date." } else { Log "SteamCMD exited with code $code." }
    return ($code -eq 0)
}

function Get-InstalledBuild($s) {
    $f = Join-Path $s.Dir "steamapps\appmanifest_$($s.AppId).acf"
    if (-not (Test-Path $f)) { return $null }
    if ((Get-Content $f -Raw) -match '"buildid"\s+"(\d+)"') { return $Matches[1] }
    return $null
}

function Get-LatestBuild($appId) {
    $exe = Join-Path $txtCmd.Text.Trim() 'steamcmd.exe'
    $out = Join-Path $env:TEMP "steamcmd-info-$appId.txt"
    if (Test-Path $out) { Remove-Item $out -Force }
    $p = Start-Process -FilePath $exe -ArgumentList "+login anonymous +app_info_update 1 +app_info_print $appId +quit" `
         -WindowStyle Hidden -RedirectStandardOutput $out -PassThru
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
    }
    if (-not (Test-Path $out)) { return $null }
    $txt = Get-Content $out -Raw
    if ($txt -match '"branches"\s*\{\s*"public"\s*\{\s*"buildid"\s*"(\d+)"') { return $Matches[1] }
    return $null
}

function Check-Server($s, $install) {
    $latest = Get-LatestBuild $s.AppId
    if (-not $latest) { Log "Couldn't read the latest build for $($s.Name)."; return }
    $have = Get-InstalledBuild $s
    if (-not $have) { Log "$($s.Name) isn't installed in $($s.Dir) yet (latest build $latest)."; return }
    if ($have -eq $latest) { Log "$($s.Name): up to date (build $have)."; return }
    Log "$($s.Name): update available (installed $have, latest $latest)."
    if ($install) { [void](Update-Server $s) }
}

function Run-Check($install) {
    $exe = Join-Path $txtCmd.Text.Trim() 'steamcmd.exe'
    if (-not (Test-Path $exe)) { Log 'SteamCMD not installed yet. Run step 1 on the Setup tab.'; return }
    $list = @($script:servers | Where-Object { $_.AutoUpdate })
    if ($list.Count -eq 0) { Log 'No servers ticked for auto-update.'; return }
    $script:lastCheck = Get-Date
    Set-Busy $true
    try {
        Log 'Checking for updates...'
        foreach ($s in $list) { Check-Server $s $install }
    } catch { Log "ERROR: $($_.Exception.Message)" }
    Set-Busy $false
}

$btnCheckNow.Add_Click({ Save-Config; Run-Check $chkAutoInstall.Checked })
$chkAutoCheck.Add_CheckedChanged({
    $script:lastCheck = Get-Date
    Save-Config
    if ($chkAutoCheck.Checked) { Log "Auto-check on: every $([int]$numMins.Value) min while this window is open." }
})
$chkAutoInstall.Add_CheckedChanged({ Save-Config })
$numMins.Add_ValueChanged({ Save-Config })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000
$timer.Add_Tick({
    if (-not $chkAutoCheck.Checked -or $script:busy) { return }
    if (((Get-Date) - $script:lastCheck).TotalMinutes -ge [int]$numMins.Value) { Run-Check $chkAutoInstall.Checked }
})
$timer.Start()

$lvSrv.Add_ItemChecked({
    if ($script:loading) { return }
    $id = [int]$_.Item.Tag
    $s = $script:servers | Where-Object { [int]$_.AppId -eq $id } | Select-Object -First 1
    if ($s) { $s.AutoUpdate = $_.Item.Checked; Save-Config }
})
$lvSrv.Add_SelectedIndexChanged({
    if ($lvSrv.SelectedItems.Count -gt 0) {
        $s = Get-SelectedServer
        if ($s) { $txtSDir.Text = [string]$s.Dir; $txtSCmd.Text = [string]$s.Cmd }
    }
})
$btnSBrowse.Add_Click({ Browse $txtSDir })

$btnAddSrv.Add_Click({
    $added = 0
    foreach ($it in $lvGames.CheckedItems) {
        $id = [int]$it.Tag
        if ($script:servers | Where-Object { [int]$_.AppId -eq $id }) { continue }
        $name = $it.Text
        [void]$script:servers.Add([pscustomobject]@{
            Name = $name; AppId = $id; AutoUpdate = $true
            Dir = (Join-Path $cfg.GamesRoot (Safe-Name $name)); Cmd = ''
        })
        $added++
    }
    Save-Config; Refresh-Servers
    Log "Added $added server(s) to My servers. Set each start command there."
    if ($added -gt 0) { $tabs.SelectedTab = $tabSrv }
})

$btnSaveSrv.Add_Click({
    $s = Get-SelectedServer
    if ($s) { $s.Dir = $txtSDir.Text.Trim(); $s.Cmd = $txtSCmd.Text.Trim(); Save-Config; Refresh-Servers; Log "Saved $($s.Name)." }
})
$btnRemoveSrv.Add_Click({
    $s = Get-SelectedServer
    if ($s) { $script:servers.Remove($s); Save-Config; Refresh-Servers; Log "Removed $($s.Name) (files on disk untouched)." }
})
$btnUpdateNow.Add_Click({
    $s = Get-SelectedServer
    if ($s) { Save-Config; Set-Busy $true; [void](Update-Server $s); Set-Busy $false }
})
$btnStartSrv.Add_Click({
    $s = Get-SelectedServer
    if (-not $s) { return }
    $s.Dir = $txtSDir.Text.Trim(); $s.Cmd = $txtSCmd.Text.Trim(); Save-Config
    Set-Busy $true
    try {
        if ($s.AutoUpdate) { if (-not (Update-Server $s)) { Log 'Update failed, starting anyway.' } }
        if (-not $s.Cmd) { Log 'No start command set for this server.' }
        elseif (-not (Test-Path $s.Dir)) { Log 'Install folder does not exist yet.' }
        else { Start-Process cmd.exe -ArgumentList "/k $($s.Cmd)" -WorkingDirectory $s.Dir; Log "Started $($s.Name)." }
    } catch { Log "ERROR: $($_.Exception.Message)" }
    Set-Busy $false
})
$btnLauncher.Add_Click({
    $s = Get-SelectedServer
    if (-not $s) { return }
    $s.Dir = $txtSDir.Text.Trim(); $s.Cmd = $txtSCmd.Text.Trim(); Save-Config
    $exe = Join-Path $txtCmd.Text.Trim() 'steamcmd.exe'
    $folder = Join-Path $txtCmd.Text.Trim() 'launchers'
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $file = Join-Path $folder ("Start-" + (Safe-Name $s.Name) + '.bat')
    $lines = @('@echo off', "title $($s.Name)")
    if ($s.AutoUpdate) { $lines += "`"$exe`" $(Get-UpdateArgs $s.AppId $s.Dir $true)" }
    $lines += "cd /d `"$($s.Dir)`""
    if ($s.Cmd) { $lines += $s.Cmd }
    $lines += 'pause'
    $lines | Set-Content -Path $file -Encoding ASCII
    Log "Launcher created: $file"
    Start-Process explorer.exe "/select,`"$file`""
})

# ---------------- Setup tab handlers ----------------
$btnCmdBrowse.Add_Click({ Browse $txtCmd })
$btnGameBrowse.Add_Click({ Browse $txtGame })
$btnOpenCmd.Add_Click({ if (Test-Path $txtCmd.Text) { Start-Process explorer.exe $txtCmd.Text } })
$btnOpenGame.Add_Click({ if (Test-Path $txtGame.Text) { Start-Process explorer.exe $txtGame.Text } })

$btnSteam.Add_Click({
    Save-Config
    Set-Busy $true
    try {
        $dir = $txtCmd.Text.Trim()
        if (-not $dir) { throw 'Choose a SteamCMD folder.' }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $exe = Join-Path $dir 'steamcmd.exe'
        if (-not (Test-Path $exe)) {
            Log 'Downloading steamcmd.zip...'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $zip = Join-Path $env:TEMP 'steamcmd.zip'
            Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $dir -Force
            Remove-Item $zip -Force
            Log 'Extracted steamcmd.exe.'
        } else { Log 'steamcmd.exe already present.' }
        Log 'Running SteamCMD self-update (a console window will open)...'
        $code = Run-Wait $exe '+quit'
        if ($code -eq 0) { Log 'SteamCMD is up to date.' } else { Log "SteamCMD exited with code $code." }
    } catch { Log "ERROR: $($_.Exception.Message)" }
    Set-Busy $false
})

$btnGame.Add_Click({
    Save-Config
    Set-Busy $true
    try {
        $exe = Join-Path $txtCmd.Text.Trim() 'steamcmd.exe'
        if (-not (Test-Path $exe)) { throw 'SteamCMD not installed yet. Run step 1 first.' }
        if ($txtApp.Text.Trim() -notmatch '^\d+$') { throw 'App ID must be a number.' }
        if (-not $txtGame.Text.Trim()) { throw 'Choose an install folder.' }
        if (-not $chkAnon.Checked -and -not $txtUser.Text.Trim()) { throw 'Enter a Steam username or tick anonymous.' }
        New-Item -ItemType Directory -Force -Path $txtGame.Text.Trim() | Out-Null
        Log "Installing app $($txtApp.Text.Trim()) (a console window will open)..."
        $code = Run-Wait $exe (Get-UpdateArgs $txtApp.Text.Trim() $txtGame.Text.Trim())
        if ($code -eq 0) { Log 'Done.' } else { Log "SteamCMD exited with code $code. Check the console output." }
    } catch { Log "ERROR: $($_.Exception.Message)" }
    Set-Busy $false
})

Refresh-GameList
Refresh-Servers
if ($cfg.PwEnc) {
    try {
        $sec = ConvertTo-SecureString $cfg.PwEnc
        $txtPass.Text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    } catch { Log 'Saved password could not be decrypted; please re-enter it.' }
}
$form.Add_FormClosing({ Save-Config })
[void]$form.ShowDialog()
