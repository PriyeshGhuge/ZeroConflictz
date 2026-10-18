# ==============================================================================
# ZeroConflict CLI - PowerShell Stream-Safe Installer for Windows
# Usage: irm https://<domain>/cli.ps1 | iex
# ==============================================================================

[CmdletBinding()]
param(
    [string]$Repo = "ZeroConflictz/cli",
    [string]$BinName = "zeroconflict",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  [ok] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [! ] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "Error: $Msg" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Installing $BinName for Windows ===" -ForegroundColor Cyan
Write-Host ""

# Ensure TLS 1.2 and 1.3 are enabled
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor `
    [System.Net.SecurityProtocolType]::Tls12

# -----------------------------------------------------------------------------
# Step 1: Detect Architecture
# -----------------------------------------------------------------------------
Write-Step "Detecting CPU architecture..."
$rawArch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) {
    $rawArch = $env:PROCESSOR_ARCHITEW6432
}

$targetArch = ""
switch ($rawArch.ToUpper()) {
    "AMD64" { $targetArch = "amd64" }
    "ARM64" { $targetArch = "arm64" }
    Default {
        Write-Err "Unsupported architecture: $rawArch. Supported architectures: x64 (AMD64), ARM64."
        return
    }
}
Write-Ok "Detected architecture: Windows/$targetArch ($rawArch)"

# -----------------------------------------------------------------------------
# Step 2: Resolve Release Version
# -----------------------------------------------------------------------------
$resolvedTag = $Version
if (-not $resolvedTag) {
    Write-Step "Fetching latest release metadata from GitHub Releases API..."
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{ "User-Agent" = "ZeroConflict-PowerShell-Installer" }

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -UseBasicParsing
        $resolvedTag = $release.tag_name
    } catch {
        # Fallback to redirect resolution if unauthenticated API limit is reached
        try {
            $webRequest = [System.Net.WebRequest]::Create("https://github.com/$Repo/releases/latest")
            $webRequest.AllowAutoRedirect = $false
            $response = $webRequest.GetResponse()
            $redirectUrl = $response.GetResponseHeader("Location")
            $response.Close()
            if ($redirectUrl) {
                $resolvedTag = ($redirectUrl.TrimEnd('/') -split '/')[-1]
            }
        } catch {
            Write-Err "Failed to determine latest release tag for $Repo : $($_.Exception.Message)"
            Write-Host "You can specify a version explicitly: irm https://<domain>/cli.ps1 | & { param(`$v) `$v } -Version 'v1.0.0'"
            return
        }
    }
}

if (-not $resolvedTag) {
    Write-Err "Could not resolve a release version."
    return
}

$cleanVersion = $resolvedTag.TrimStart('v')
Write-Ok "Target version: $resolvedTag"

# -----------------------------------------------------------------------------
# Step 3: Prepare Temporary Download Directory
# -----------------------------------------------------------------------------
$archiveName = "${BinName}_${cleanVersion}_windows_${targetArch}.zip"
$archiveUrl = "https://github.com/$Repo/releases/download/$resolvedTag/$archiveName"
$checksumsUrl = "https://github.com/$Repo/releases/download/$resolvedTag/checksums.txt"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    $archiveFile = Join-Path $tempDir $archiveName
    $checksumsFile = Join-Path $tempDir "checksums.txt"

    # -------------------------------------------------------------------------
    # Step 4: Download Archive and Checksums
    # -------------------------------------------------------------------------
    Write-Step "Downloading $archiveName..."
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archiveFile -UseBasicParsing
    Write-Ok "Downloaded $archiveName"

    Write-Step "Downloading checksums.txt..."
    Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumsFile -UseBasicParsing
    Write-Ok "Downloaded checksums.txt"

    # -------------------------------------------------------------------------
    # Step 5: Verify SHA-256 Checksum
    # -------------------------------------------------------------------------
    Write-Step "Verifying SHA-256 checksum..."
    $actualHash = (Get-FileHash -Path $archiveFile -Algorithm SHA256).Hash.ToLower()

    $expectedHash = ""
    $checksumLines = Get-Content $checksumsFile
    foreach ($line in $checksumLines) {
        if ($line -match "([a-fA-F0-9]{64})\s+.*$([regex]::Escape($archiveName))") {
            $expectedHash = $matches[1].ToLower()
            break
        }
    }

    if (-not $expectedHash) {
        throw "Archive $archiveName was not found in checksums.txt!"
    }

    if ($actualHash -ne $expectedHash) {
        Write-Err "Checksum verification failed!"
        Write-Err "  Expected: $expectedHash"
        Write-Err "  Actual:   $actualHash"
        throw "Aborting installation due to checksum mismatch."
    }
    Write-Ok "Checksum verified: $actualHash"

    # -------------------------------------------------------------------------
    # Step 6: Extract Binary to Target Directory
    # -------------------------------------------------------------------------
    $installDir = Join-Path $HOME ".local\bin"
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    }

    Write-Step "Extracting $archiveName..."
    $extractDir = Join-Path $tempDir "extracted"
    Expand-Archive -Path $archiveFile -DestinationPath $extractDir -Force

    $binarySource = Join-Path $extractDir "$BinName.exe"
    if (-not (Test-Path $binarySource)) {
        throw "Binary $BinName.exe was not found inside the downloaded archive."
    }

    $binaryTarget = Join-Path $installDir "$BinName.exe"
    Copy-Item -Path $binarySource -Destination $binaryTarget -Force
    Write-Ok "Installed binary to: $binaryTarget"

    # -------------------------------------------------------------------------
    # Step 7: Permanently Update User PATH & Refresh Current Session
    # -------------------------------------------------------------------------
    Write-Step "Checking PATH configuration..."
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $userPath) { $userPath = "" }

    $pathItems = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $resolvedInstallDir = (Resolve-Path $installDir).Path

    $alreadyInUserPath = $false
    foreach ($item in $pathItems) {
        try {
            if ((Resolve-Path $item -ErrorAction SilentlyContinue).Path -eq $resolvedInstallDir) {
                $alreadyInUserPath = $true
                break
            }
        } catch {}
    }

    if (-not $alreadyInUserPath) {
        $newUserPath = if ($userPath) { "$userPath;$installDir" } else { $installDir }
        [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
        Write-Ok "Added $installDir permanently to User PATH environment variable."
    } else {
        Write-Ok "$installDir is already present in User PATH."
    }

    # Refresh current session PATH
    $sessionPaths = $env:PATH -split ';'
    $alreadyInSessionPath = $false
    foreach ($sp in $sessionPaths) {
        try {
            if ((Resolve-Path $sp -ErrorAction SilentlyContinue).Path -eq $resolvedInstallDir) {
                $alreadyInSessionPath = $true
                break
            }
        } catch {}
    }

    if (-not $alreadyInSessionPath) {
        $env:PATH = "$installDir;$env:PATH"
        Write-Ok "Refreshed current session PATH."
    }

    Write-Host ""
    Write-Host "$BinName was successfully installed!" -ForegroundColor Green
    Write-Host "Location: $binaryTarget" -ForegroundColor DarkGray
    Write-Host "You can now run: $BinName --version" -ForegroundColor Cyan
    Write-Host ""
}
finally {
    # Cleanup temporary directory
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}
