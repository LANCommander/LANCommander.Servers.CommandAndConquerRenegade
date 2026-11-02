#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Installs the server into /config/Server (the overlay's lower dir) in two parts:
#
# 1. The Tiberian Technologies server package (RENEGADE_SERVER_URL). Its serverfiles/ folder is
#    copied over Server/, replacing any client files with the same names (scripts.dll differs
#    between the TT client and server). Server/.tt-server-url records the URL; the package is
#    installed again when it changes. RENEGADE_SERVER_SHA256 is checked when set.
#
# 2. The retail data the TT package leaves out: data/always.dat and data/always2.dat (and
#    always.dbs when the source has it). They're taken from RENEGADE_ARCHIVE_URL, a zip of a
#    Renegade install, when Server/ doesn't have them yet.
#
# Wine looks files up case-insensitively, but Linux keeps `Data` and `data` apart, so everything
# goes into the one data folder Server/ already has (whatever its case) and existing file names
# keep their case.

Add-Type -AssemblyName System.IO.Compression.FileSystem

Invoke-Hook "PreInstallRenegade"

$server  = $Env:SERVER_DIR
$marker  = Join-Path $server '.tt-server-url'
$changed = $false

New-Item -ItemType Directory -Path $server -Force | Out-Null

function Get-CaseInsensitive([string] $Dir, [string] $Name) {
    if (-not (Test-Path -Path $Dir)) { return $null }
    Get-ChildItem -Path $Dir -Force | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
}

function Get-DataDir {
    $dirs = @(Get-ChildItem -Path $server -Directory -Force | Where-Object { $_.Name -ieq 'data' })
    if ($dirs.Count -gt 1) {
        Write-Log -Level Warning "Server/ has more than one data folder ($($dirs.Name -join ', ')); using $($dirs[0].Name). Merge them, Wine sees only one."
    }
    if ($dirs.Count -ge 1) { return $dirs[0].FullName }

    $dir = Join-Path $server 'data'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $dir
}

# Copy a zip entry to $Dir/$Name, reusing the case of a file that's already there
function Save-Entry([System.IO.Compression.ZipArchiveEntry] $Entry, [string] $Dir, [string] $Name) {
    $existing = Get-CaseInsensitive $Dir $Name
    $path = if ($existing) { $existing.FullName } else { Join-Path $Dir $Name }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $path, $true)
}

function Get-Download([string] $Url, [string] $Path) {
    curl -fL --retry 3 --output $Path "$Url"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
}

# ---- 1. TT server package -------------------------------------------------------------------------

$installed = if (Test-Path -Path $marker) { (Get-Content -Path $marker -Raw).Trim() } else { '' }
$exe       = Get-CaseInsensitive $server 'server.exe'

if (-not $Env:RENEGADE_SERVER_URL) {
    if (-not $exe) { Write-Log -Level Error "server.exe not found in $server and RENEGADE_SERVER_URL is empty" }
} elseif ($exe -and $installed -eq $Env:RENEGADE_SERVER_URL) {
    Write-Log "TT server found in $server ($installed)"
} else {
    Write-Log "Downloading the TT server from $Env:RENEGADE_SERVER_URL"

    $zipPath = '/tmp/renegade-server.zip'
    Get-Download $Env:RENEGADE_SERVER_URL $zipPath

    if ($Env:RENEGADE_SERVER_SHA256) {
        $sha = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLower()
        if ($sha -ne $Env:RENEGADE_SERVER_SHA256.Trim().ToLower()) {
            Remove-Item -Force -Path $zipPath
            throw "RENEGADE_SERVER_SHA256 mismatch for $Env:RENEGADE_SERVER_URL (got $sha)"
        }
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        # The package keeps the server in server/serverfiles/; find the folder holding server.exe
        $exeEntry = $zip.Entries | Where-Object { $_.Name -ieq 'server.exe' } |
            Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if (-not $exeEntry) { throw "server.exe not found in $Env:RENEGADE_SERVER_URL" }
        $prefix = $exeEntry.FullName.Substring(0, $exeEntry.FullName.Length - $exeEntry.Name.Length)

        $dataDir = Get-DataDir
        $count = 0
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith($prefix) -or -not $entry.Name) { continue }
            $parts = $entry.FullName.Substring($prefix.Length).Split('/')

            # Walk the path, reusing the case of folders that already exist; data/ maps to $dataDir
            $dir = $server
            for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                if ($i -eq 0 -and $parts[0] -ieq 'data') { $dir = $dataDir; continue }
                $sub = Get-CaseInsensitive $dir $parts[$i]
                $dir = if ($sub) { $sub.FullName } else { New-Item -ItemType Directory -Path (Join-Path $dir $parts[$i]) | Select-Object -ExpandProperty FullName }
            }
            Save-Entry $entry $dir $parts[-1]
            $count++
        }
        Write-Log "Installed $count TT server files from $prefix"
    } finally {
        $zip.Dispose()
        Remove-Item -Force -Path $zipPath -ErrorAction SilentlyContinue
    }

    Set-Content -Path $marker -Value $Env:RENEGADE_SERVER_URL -NoNewline
    $changed = $true
}

# ---- 2. Retail data -------------------------------------------------------------------------------

$required = @('always.dat', 'always2.dat')
$optional = @('always.dbs')
$dataDir  = Get-DataDir
$missing  = @($required | Where-Object { -not (Get-CaseInsensitive $dataDir $_) })

if ($missing.Count -eq 0) {
    Write-Log "Retail data found in $dataDir"
} elseif ($Env:RENEGADE_ARCHIVE_URL) {
    Write-Log "Downloading the retail data ($($missing -join ', ')) from $Env:RENEGADE_ARCHIVE_URL"

    $zipPath = '/tmp/renegade-game.zip'
    Get-Download $Env:RENEGADE_ARCHIVE_URL $zipPath

    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($name in ($required + $optional)) {
            if ($name -in $optional -and (Get-CaseInsensitive $dataDir $name)) { continue }
            if ($name -in $required -and $name -notin $missing) { continue }

            # <anything>/data/<name>, shortest path first (skips copies in backup folders)
            $entry = $zip.Entries | Where-Object {
                $_.Name -ieq $name -and $_.FullName -imatch '(^|/)data/[^/]+$'
            } | Sort-Object { $_.FullName.Length } | Select-Object -First 1

            if ($entry) {
                Save-Entry $entry $dataDir $name
                Write-Log "Extracted $($entry.FullName)"
            } elseif ($name -in $required) {
                throw "$name not found in $Env:RENEGADE_ARCHIVE_URL (looked for data/$name)"
            }
        }
    } finally {
        $zip.Dispose()
        Remove-Item -Force -Path $zipPath -ErrorAction SilentlyContinue
    }
    $changed = $true
} else {
    Write-Log -Level Error "$($missing -join ' and ') not found in $dataDir. Copy them from a Renegade install, or set RENEGADE_ARCHIVE_URL to a zip of one."
}

if ($changed) {
    chown -R "$($Env:UID):$($Env:GID)" $server

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }
}

Invoke-Hook "PostInstallRenegade"

Set-Location $Env:SERVER_ROOT
