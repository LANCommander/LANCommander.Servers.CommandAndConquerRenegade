#Requires -Modules Logging

# Writes the RENEGADE_* settings into the server's own config files, through the merged view so
# the edits land in Overlay/. Only the keys below are changed; everything else in the files (and
# hand edits to other keys) is kept.
#
#   server.ini                  [Server]: game type, ports, RenRem remote admin, WOL login
#   data/<RENEGADE_CONFIG>      [Settings]: name, MOTD, password, players, time limit, rules
#   tt.cfg                      rotation: the map list (TT ignores the MapNameNN keys)

$root = $Env:SERVER_ROOT

function Get-CaseInsensitive([string] $Dir, [string] $Name) {
    if (-not (Test-Path -Path $Dir)) { return $null }
    Get-ChildItem -Path $Dir -Force | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
}

function Test-True([string] $Value) { "$Value".Trim().ToLower() -in @('true', '1', 'yes', 'on') }
function Format-YesNo([string] $Value) { if (Test-True $Value) { 'yes' } else { 'no' } }
function Format-TrueFalse([string] $Value) { if (Test-True $Value) { 'true' } else { 'false' } }

function Format-Int([string] $Value, [int] $Default, [int] $Min, [int] $Max, [string] $Setting) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "$Default" }
    $n = 0
    if (-not [int]::TryParse($Value.Trim(), [ref] $n) -or $n -lt $Min -or $n -gt $Max) {
        throw "$Setting must be a whole number from $Min to $Max (got '$Value')"
    }
    "$n"
}

# Set Key=Value in [Section] of an INI file, appending the key (or section) when it's missing.
# The files are CRLF; Renegade reads `Key=Value` and `Key = Value` alike.
function Set-IniValues([string] $Path, [string] $Section, [System.Collections.Specialized.OrderedDictionary] $Values) {
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -Path $Path) {
        $lines.AddRange([string[]]([System.IO.File]::ReadAllText($Path) -split '\r?\n'))
        while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    }

    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) {
        $lines.Add('')
        $lines.Add("[$Section]")
        $start = $lines.Count - 1
    }

    foreach ($v in $Values.GetEnumerator()) {
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].TrimStart().StartsWith('[')) { $end = $i; break }
        }

        $line = "$($v.Key)=$($v.Value)"
        $found = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match "^\s*$([regex]::Escape($v.Key))\s*=") {
                $lines[$i] = $line
                $found = $true
                break
            }
        }
        if (-not $found) {
            # After the section's last non-blank line
            $at = $end
            while ($at -gt $start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
            $lines.Insert($at, $line)
        }
    }

    [System.IO.File]::WriteAllText($Path, ($lines -join "`r`n") + "`r`n")
    chown "$($Env:UID):$($Env:GID)" $Path
}

function Format-Text([string] $Value, [int] $Max, [string] $Setting) {
    $Value = "$Value" -replace '[\r\n]', ' '
    if ($Max -gt 0 -and $Value.Length -gt $Max) {
        Write-Log -Level Warning "$Setting is longer than $Max characters; server lists cut it off"
    }
    $Value
}

if (-not (Get-CaseInsensitive $root 'server.exe')) {
    Write-Log -Level Error "server.exe not found in $root; skipping server configuration"
    return
}

$dataDir = Get-ChildItem -Path $root -Directory -Force | Where-Object { $_.Name -ieq 'data' } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $dataDir) {
    Write-Log -Level Error "No data folder in $root; skipping server configuration"
    return
}

try {
    # ---- server.ini --------------------------------------------------------------------------------

    $gameType = switch ("$Env:RENEGADE_GAME_TYPE".Trim().ToLower()) {
        { $_ -in @('', 'lan') } { 'LAN' }
        'gamespy'               { 'GameSpy' }
        'wol'                   { 'WOL' }
        default { throw "RENEGADE_GAME_TYPE must be LAN, GameSpy or WOL (got '$Env:RENEGADE_GAME_TYPE')" }
    }

    $port      = Format-Int $Env:RENEGADE_PORT 4848 1 65535 'RENEGADE_PORT'
    $queryPort = Format-Int $Env:RENEGADE_QUERY_PORT 25300 1 65535 'RENEGADE_QUERY_PORT'
    $adminPort = Format-Int $Env:RENEGADE_REMOTE_ADMIN_PORT ([int]$port + 1) 1 65535 'RENEGADE_REMOTE_ADMIN_PORT'
    $config    = if ($Env:RENEGADE_CONFIG) { $Env:RENEGADE_CONFIG.Trim() } else { 'svrcfg_cnc.ini' }

    $serverIni = [ordered]@{
        'Config'          = $config
        'GameType'        = $gameType
        'Port'            = $port
        'GameSpyGamePort' = $port   # must match Port
        'GameSpyQueryPort'= $queryPort
    }

    if ($Env:RENEGADE_REMOTE_ADMIN_PASSWORD) {
        if ($Env:RENEGADE_REMOTE_ADMIN_PASSWORD.Length -ne 8) {
            Write-Log -Level Warning "RENEGADE_REMOTE_ADMIN_PASSWORD should be exactly 8 characters; RenRem clients may not log in otherwise"
        }
        $serverIni['AllowRemoteAdmin']    = 'true'
        $serverIni['RemoteAdminPassword'] = $Env:RENEGADE_REMOTE_ADMIN_PASSWORD
        $serverIni['RemoteAdminIP']       = if ($Env:RENEGADE_REMOTE_ADMIN_IP) { $Env:RENEGADE_REMOTE_ADMIN_IP.Trim() } else { '127.0.0.1' }
        $serverIni['RemoteAdminPort']     = $adminPort
    } else {
        # The stock server.ini enables RenRem with the password "password"
        $serverIni['AllowRemoteAdmin'] = 'false'
    }

    if ($Env:RENEGADE_WOL_NICKNAME)     { $serverIni['Nickname']    = $Env:RENEGADE_WOL_NICKNAME }
    if ($Env:RENEGADE_WOL_PASSWORD)     { $serverIni['Password']    = $Env:RENEGADE_WOL_PASSWORD }
    if ($Env:RENEGADE_WOL_SERIAL)       { $serverIni['Serial']      = $Env:RENEGADE_WOL_SERIAL }
    if ($Env:RENEGADE_WOL_LOGIN_SERVER) { $serverIni['LoginServer'] = $Env:RENEGADE_WOL_LOGIN_SERVER }

    $serverIniPath = Get-CaseInsensitive $root 'server.ini'
    $serverIniPath = if ($serverIniPath) { $serverIniPath.FullName } else { Join-Path $root 'server.ini' }
    Set-IniValues $serverIniPath 'Server' $serverIni

    # ---- map rotation (tt.cfg) ---------------------------------------------------------------------

    $ttCfg = Get-CaseInsensitive $root 'tt.cfg'
    $rotation = @()

    if ($Env:RENEGADE_MAPS) {
        foreach ($name in @("$Env:RENEGADE_MAPS" -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            $base = $name -replace '\.mix$', ''
            if (Get-CaseInsensitive $dataDir "$base.mix") {
                $rotation += $base
            } else {
                Write-Log -Level Warning "RENEGADE_MAPS: $base.mix not found in data/; leaving it out of the rotation"
            }
        }
        if ($rotation.Count -eq 0) { throw "RENEGADE_MAPS has no maps that exist in data/" }

        if (-not $ttCfg) { throw "tt.cfg not found in $root; can't set the map rotation" }
        $text = [System.IO.File]::ReadAllText($ttCfg.FullName)
        $list = "rotation:`r`n[`r`n" + (($rotation | ForEach-Object { "`t`"$($_.Replace('"', ''))`"" }) -join ",`r`n") + "`r`n];"
        if ($text -match '(?s)rotation\s*:\s*\[.*?\]\s*;') {
            $text = [regex]::Replace($text, '(?s)rotation\s*:\s*\[.*?\]\s*;', { param($m) $list })
        } else {
            $text = $text.TrimEnd() + "`r`n`r`n$list`r`n"
        }
        [System.IO.File]::WriteAllText($ttCfg.FullName, $text)
        chown "$($Env:UID):$($Env:GID)" $ttCfg.FullName
    } elseif ($ttCfg) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($ttCfg.FullName), '(?s)rotation\s*:\s*\[(.*?)\]')
        if ($m.Success) { $rotation = @([regex]::Matches($m.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) }
    }

    # ---- game settings (data/<RENEGADE_CONFIG>) ----------------------------------------------------

    $password = "$Env:RENEGADE_PASSWORD"
    $settings = [ordered]@{
        'bGameTitle'              = Format-Text $(if ($Env:RENEGADE_SERVER_NAME) { $Env:RENEGADE_SERVER_NAME } else { 'Renegade Server' }) 30 'RENEGADE_SERVER_NAME'
        'bMotd'                   = Format-Text $Env:RENEGADE_MOTD 0 'RENEGADE_MOTD'
        'IsPassworded'            = if ($password) { 'yes' } else { 'no' }
        'bPassword'               = $password
        'MaxPlayers'              = Format-Int $Env:RENEGADE_MAX_PLAYERS 32 1 127 'RENEGADE_MAX_PLAYERS'
        'TimeLimitMinutes'        = Format-Int $Env:RENEGADE_TIME_LIMIT 30 0 100000 'RENEGADE_TIME_LIMIT'
        'StartingCredits'         = Format-Int $Env:RENEGADE_STARTING_CREDITS 0 0 1000000 'RENEGADE_STARTING_CREDITS'
        'RadarMode'               = Format-Int $Env:RENEGADE_RADAR_MODE 1 0 2 'RENEGADE_RADAR_MODE'
        'IsFriendlyFirePermitted' = Format-YesNo $Env:RENEGADE_FRIENDLY_FIRE
        'IsTeamChangingAllowed'   = Format-YesNo $Env:RENEGADE_TEAM_CHANGING
        'RemixTeams'              = Format-YesNo $Env:RENEGADE_REMIX_TEAMS
        'SpawnWeapons'            = Format-YesNo $Env:RENEGADE_SPAWN_WEAPONS
        'CanRepairBuildings'      = Format-YesNo $Env:RENEGADE_CAN_REPAIR_BUILDINGS
        'DriverIsAlwaysGunner'    = Format-YesNo $Env:RENEGADE_DRIVER_IS_GUNNER
        'BaseDestructionEndsGame' = Format-YesNo $Env:RENEGADE_BASE_DESTRUCTION_ENDS_GAME
        'BeaconPlacementEndsGame' = Format-YesNo $Env:RENEGADE_BEACON_ENDS_GAME
        'DoMapsLoop'              = 'yes'
        'IsDedicated'             = 'yes'
        'IsLaddered'              = 'no'    # no ladder server on a LAN
        'IsQuickMatch'            = 'no'    # unsupported by TT
        'IsClanGame'              = 'no'
        'IsAutoRestart'           = 'no'    # the container restarts it
    }
    if ($rotation.Count -gt 0) {
        # Obsolete under TT, but keep them pointing at a real map
        $settings['MapName']   = "$($rotation[0]).mix"
        $settings['MapName00'] = "$($rotation[0]).mix"
    }

    $configPath = Get-CaseInsensitive $dataDir $config
    $configPath = if ($configPath) { $configPath.FullName } else { Join-Path $dataDir $config }
    Set-IniValues $configPath 'Settings' $settings

    Write-Log "Configured $gameType server on $port/udp: '$($settings['bGameTitle'])', $($settings['MaxPlayers']) players, rotation $($rotation -join ', ')"
} catch {
    Write-Log -Level Error "$($_.Exception.Message). Keeping the previous configuration."
}
