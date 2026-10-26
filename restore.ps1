# Restore Cursor files from the backup created by install.ps1.
$ErrorActionPreference = "Stop"

try {
  $utf8Console = New-Object System.Text.UTF8Encoding $false
  [Console]::OutputEncoding = $utf8Console
  $OutputEncoding = $utf8Console
} catch {}

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-Elevated {
  $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arg | Out-Null
}

function Test-CanWriteFile([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $true }
  try {
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($item.IsReadOnly) { $item.IsReadOnly = $false }
    $stream = [System.IO.File]::Open(
      $path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::ReadWrite
    )
    $stream.Dispose()
    return $true
  } catch {
    return $false
  }
}

try {
  $cursor = Get-Process -Name "Cursor" -ErrorAction SilentlyContinue
  if ($cursor) {
    throw "Cursor is still running. Use File, then Exit, then run restore.bat again."
  }

  $backupRoot = Join-Path $env:APPDATA "Cursor\User\cursor-chat-bidi\backup"
  if (-not (Test-Path -LiteralPath $backupRoot)) {
    throw "No backup was found. apply.bat has to finish successfully once before restore works."
  }

  $jobs = @()
  foreach ($dir in @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue)) {
    $rootFile = Join-Path $dir.FullName "install-root.txt"
    if (-not (Test-Path -LiteralPath $rootFile)) { continue }
    $root = ([System.IO.File]::ReadAllText($rootFile)).Trim()
    if (-not $root) { continue }
    $jobs += [pscustomobject]@{ Dir = $dir.FullName; Root = $root }
  }
  if ($jobs.Count -eq 0) {
    throw "The backup has no install-root.txt. Run apply.bat again, then run restore.bat."
  }

  $needsAdmin = $false
  foreach ($job in $jobs) {
    $html = Join-Path $job.Root "resources\app\out\vs\code\electron-sandbox\workbench\workbench.html"
    $main = Join-Path $job.Root "resources\app\out\main.js"
    $product = Join-Path $job.Root "resources\app\product.json"
    foreach ($file in @($html, $main, $product)) {
      if (-not (Test-CanWriteFile $file)) { $needsAdmin = $true }
    }
  }
  if ($needsAdmin -and -not (Test-IsAdmin)) {
    try {
      Start-Elevated
      exit 0
    } catch {
      Write-Host "Administrator permission was not granted. Protected folders will not be restored."
    }
  }

  $restored = 0
  $skipped = 0
  foreach ($job in $jobs) {
    $root = $job.Root
    $exe = Join-Path $root "Cursor.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
      Write-Host ("skipped, this install is gone: " + $root)
      continue
    }

    $outDir = Join-Path $root "resources\app\out"
    $appDir = Join-Path $root "resources\app"
    $wbDir = Join-Path $outDir "vs\code\electron-sandbox\workbench"
    $map = @(
      @{ Name = "workbench.html"; Dest = (Join-Path $wbDir "workbench.html") },
      @{ Name = "main.js"; Dest = (Join-Path $outDir "main.js") },
      @{ Name = "product.json"; Dest = (Join-Path $appDir "product.json") }
    )

    $blocked = $false
    foreach ($item in $map) {
      if (-not (Test-CanWriteFile $item.Dest)) { $blocked = $true }
    }
    if ($blocked) {
      $skipped++
      Write-Host ("not restored, this folder needs administrator permission: " + $root)
      continue
    }

    foreach ($item in $map) {
      $src = Join-Path $job.Dir $item.Name
      if (Test-Path -LiteralPath $src) {
        $destItem = Get-Item -LiteralPath $item.Dest -ErrorAction SilentlyContinue
        if ($destItem -and $destItem.IsReadOnly) { $destItem.IsReadOnly = $false }
        Copy-Item -LiteralPath $src -Destination $item.Dest -Force
        Write-Host ("restored: " + $item.Dest)
      }
    }

    $injected = Join-Path $wbDir "cursor-chat-bidi.js"
    if (Test-Path -LiteralPath $injected) {
      Remove-Item -LiteralPath $injected -Force
      Write-Host ("removed: " + $injected)
    }
    $restored++
  }

  if ($restored -eq 0) {
    throw "Nothing was restored. Run restore.bat again and click Yes if Windows asks for administrator permission."
  }

  Write-Host ""
  Write-Host ("Done. Restored " + $restored + " install(s).")
  if ($skipped -gt 0) {
    Write-Host "Some folders were not restored. Run restore.bat again and click Yes."
  }
  Write-Host "Open Cursor."
} catch {
  Write-Host ""
  Write-Host ("ERROR: " + $_.Exception.Message)
  Write-Host "Press Enter to close."
  [void](Read-Host)
  exit 1
}

Write-Host "Press Enter to close."
[void](Read-Host)
exit 0
