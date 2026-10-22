# ---------------------------------------------------------------------------
# Google Drive -> local backup, converting Google files to Office formats.
#   Docs -> .docx   Sheets -> .xlsx   Slides -> .pptx   Drawings -> .svg
#
# 1. Copies ALL of My Drive into  $Dest\My Drive
#    (except anything matched in excludes.txt, e.g. the Classroom folder)
# 2. Copies each item listed in shared_items.txt into
#    $Dest\Shared drives\<Label>\<path>   (or $Dest\My Drive\<path> for "mydrive" lines)
#
# Usage (PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\backup_drive.ps1           # real run
#   powershell -ExecutionPolicy Bypass -File .\backup_drive.ps1 -DryRun   # preview only
#   ... -SharedOnly            # skip My Drive, only do shared_items.txt (can combine with -DryRun)
#
# Safe to re-run: rclone only fetches new/changed files and never deletes
# anything locally.
# ---------------------------------------------------------------------------
param([switch]$DryRun, [switch]$SharedOnly)

# ---- Settings -------------------------------------------------------------
$Remote  = "gdrive"                                  # name used in `rclone config`
$Dest    = Join-Path $HOME "DriveBackup"             # where the backup goes
$List    = Join-Path $PSScriptRoot "shared_items.txt"
$Excludes = Join-Path $PSScriptRoot "excludes.txt"    # folders to skip in My Drive
$Formats = "docx,xlsx,pptx,svg"
# ---------------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$Log = Join-Path $Dest ("backup_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$Common = @(
  "--drive-export-formats", $Formats,
  "--drive-skip-shortcuts",
  "--transfers", "4", "--checkers", "8", "--tpslimit", "10",
  "--progress",
  "--log-file", $Log, "--log-level", "INFO"
)
if ($DryRun) { $Common += "--dry-run"; Write-Host ">>> DRY RUN - nothing will be copied" }

$failures = 0

# ---- 1. My Drive ----------------------------------------------------------
if ($SharedOnly) {
  Write-Host ">>> Skipping My Drive (-SharedOnly)"
} else {
$myDriveDest = Join-Path $Dest "My Drive"
Write-Host ">>> Backing up My Drive -> $myDriveDest"
$Excl = @()
if (Test-Path $Excludes) { $Excl = @("--exclude-from", $Excludes); Write-Host "    (skipping paths listed in excludes.txt)" }
rclone copy "${Remote}:" $myDriveDest @Common @Excl
if ($LASTEXITCODE -ne 0) { Write-Host "!!! My Drive backup reported errors (see log)"; $failures++ }
}

# ---- 2. Selected shared-drive items ---------------------------------------
if (Test-Path $List) {
  foreach ($raw in Get-Content $List) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }

    $parts = $line.Split("|")
    $id    = $parts[0].Trim()
    $label = if ($parts.Count -gt 1 -and $parts[1].Trim()) { $parts[1].Trim() } else { $id }
    $path  = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }

    if ($id -ieq "mydrive") {
      $src = "${Remote}:${path}"; $sharedRoot = Join-Path $Dest "My Drive"     # item from your own Drive
    } else {
      $src = "${Remote},team_drive=${id}:${path}"
      $sharedRoot = Join-Path (Join-Path $Dest "Shared drives") $label
    }

    # Work out whether the item is a folder or a single file
    $isDir = $true
    if ($path) {
      $statJson = rclone lsjson --stat $src --drive-export-formats $Formats 2>$null
      if ($LASTEXITCODE -ne 0 -or -not $statJson) {
        Write-Host "!!! Not found: [$label] $path  (check the exact name with rclone lsf)"
        $failures++; continue
      }
      $isDir = ($statJson | Out-String | ConvertFrom-Json).IsDir
    }

    if ($isDir) {
      $target = if ($path) { Join-Path $sharedRoot $path } else { $sharedRoot }
    } else {
      $parent = Split-Path $path -Parent
      $target = if ($parent) { Join-Path $sharedRoot $parent } else { $sharedRoot }
    }

    $shown = if ($path) { $path } else { "<whole drive>" }
    Write-Host ">>> [$label] $shown -> $target"
    rclone copy $src $target @Common
    if ($LASTEXITCODE -ne 0) { Write-Host "!!! Errors copying [$label] $path (see log)"; $failures++ }
  }
} else {
  Write-Host ">>> No shared_items.txt found - skipping shared drives"
}

Write-Host ""
if ($failures) { Write-Host "Finished with $failures problem(s). Log: $Log"; exit 1 }
else           { Write-Host "All done. Log: $Log" }
