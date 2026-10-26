# Apply Cursor chat bidi (RTL/LTR by first letter).
# Finds every Cursor install. Asks for administrator only when a folder is protected.
param(
  [string[]]$InstallPath,
  [switch]$DiscoverOnly
)

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

function Start-Elevated([string[]]$Paths) {
  $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  foreach ($p in @($Paths)) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $arg += " `"" + ($p.Replace('"', "")) + "`""
  }
  Write-Host ""
  Write-Host "Cursor inside a protected folder needs administrator permission."
  Write-Host "If Windows asks, click Yes. This window stays open."
  $proc = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arg -Wait -PassThru
  if ($proc) { return [int]$proc.ExitCode }
  return 1
}

function Resolve-CursorRoot([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $Path = $Path.Trim().Trim('"')
  if ($Path -match '^"([^"]+)"') { $Path = $Matches[1] }
  $Path = $Path -replace ',\d+$', ''
  $Path = $Path.Trim()
  if (-not $Path) { return $null }

  $start = $null
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) { $start = $item.Directory.FullName }
    elseif ($item) { $start = $item.FullName }
  } elseif ($Path -match '(?i)\.exe$') {
    $parent = Split-Path -Parent $Path
    if ($parent -and (Test-Path -LiteralPath $parent)) { $start = $parent }
  }
  if (-not $start) { return $null }

  $dir = $start
  for ($i = 0; $i -lt 8 -and $dir; $i++) {
    $exe = Join-Path $dir "Cursor.exe"
    $html = Join-Path $dir "resources\app\out\vs\code\electron-sandbox\workbench\workbench.html"
    if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $html)) {
      return (Resolve-Path -LiteralPath $dir).ProviderPath
    }
    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
  }
  return $null
}

function Add-CursorRoot($Roots, [string]$Path) {
  $root = Resolve-CursorRoot $Path
  if (-not $root) { return }
  foreach ($existing in $Roots) {
    if ($existing.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return }
  }
  [void]$Roots.Add($root)
}

function Add-RootsFromKnownFolders($Roots) {
  $ErrorActionPreference = "Continue"
  $parents = @()
  if ($env:ProgramFiles) { $parents += $env:ProgramFiles }
  if (${env:ProgramFiles(x86)}) { $parents += ${env:ProgramFiles(x86)} }
  if ($env:LOCALAPPDATA) {
    $parents += (Join-Path $env:LOCALAPPDATA "Programs")
    Add-CursorRoot $Roots (Join-Path $env:LOCALAPPDATA "cursor")
  }
  foreach ($parent in $parents) {
    if (-not $parent -or -not (Test-Path -LiteralPath $parent)) { continue }
    Add-CursorRoot $Roots (Join-Path $parent "cursor")
    Add-CursorRoot $Roots (Join-Path $parent "Cursor")
  }
  if ($env:USERPROFILE) {
    Add-CursorRoot $Roots (Join-Path $env:USERPROFILE "scoop\apps\cursor\current")
  }
}

function Add-RootsFromRegistry($Roots) {
  $ErrorActionPreference = "Continue"
  $bases = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
  )
  foreach ($base in $bases) {
    if (-not (Test-Path -LiteralPath $base)) { continue }
    foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
      try { $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop }
      catch { continue }
      $name = [string]$item.DisplayName
      $blob = (([string]$item.InstallLocation) + " " + ([string]$item.DisplayIcon) + " " + ([string]$item.UninstallString))
      $namedCursor = $name -match '^(?i)cursor$'
      $looksLikeCursor = $blob -match '(?i)\\Cursor\.exe\b'
      if (-not $namedCursor -and -not $looksLikeCursor) { continue }
      Add-CursorRoot $Roots ([string]$item.InstallLocation)
      Add-CursorRoot $Roots ([string]$item.DisplayIcon)
      Add-CursorRoot $Roots ([string]$item.UninstallString)
    }
  }

  $appPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Cursor.exe",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Cursor.exe"
  )
  foreach ($keyPath in $appPaths) {
    if (-not (Test-Path -LiteralPath $keyPath)) { continue }
    try {
      $reg = Get-Item -LiteralPath $keyPath -ErrorAction Stop
      Add-CursorRoot $Roots ([string]$reg.GetValue(""))
      Add-CursorRoot $Roots ([string]$reg.GetValue("Path"))
    } catch {}
  }
}

function Add-RootsFromShortcuts($Roots) {
  $ErrorActionPreference = "Continue"
  $shell = $null
  try { $shell = New-Object -ComObject WScript.Shell } catch { return }
  $dirs = @(
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"),
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:PUBLIC "Desktop"),
    (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar")
  )
  foreach ($dir in $dirs) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
    $links = @(Get-ChildItem -LiteralPath $dir -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.BaseName -match '(?i)cursor' })
    foreach ($link in $links) {
      try {
        $shortcut = $shell.CreateShortcut($link.FullName)
        Add-CursorRoot $Roots $shortcut.TargetPath
        Add-CursorRoot $Roots $shortcut.WorkingDirectory
      } catch {}
    }
  }
}

function Add-RootsFromCommands($Roots) {
  $ErrorActionPreference = "Continue"
  foreach ($name in @("Cursor.exe", "cursor", "cursor.cmd")) {
    try { $cmds = @(Get-Command $name -All -ErrorAction SilentlyContinue) }
    catch { continue }
    foreach ($cmd in $cmds) {
      if (-not $cmd -or -not $cmd.Source) { continue }
      Add-CursorRoot $Roots $cmd.Source
      if ($cmd.Source -notmatch '(?i)\.(cmd|bat|ps1)$') { continue }
      try { $text = [System.IO.File]::ReadAllText($cmd.Source) } catch { continue }
      foreach ($match in [regex]::Matches($text, '(?i)[A-Z]:\\[^"''\r\n|*?<>]+\\Cursor\.exe')) {
        Add-CursorRoot $Roots $match.Value
      }
    }
  }
}

function Test-CanWriteFile([string]$path) {
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

function Test-CanCreateFile([string]$dir) {
  if (-not (Test-Path -LiteralPath $dir)) { return $false }
  $probe = Join-Path $dir (".cursor-chat-bidi-write-test-" + [guid]::NewGuid().ToString("N"))
  $stream = $null
  try {
    $stream = [System.IO.File]::Open(
      $probe,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    return $true
  } catch {
    return $false
  } finally {
    if ($stream) { $stream.Dispose() }
    if (Test-Path -LiteralPath $probe) {
      Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
  }
}

function Test-RootWritable([string]$root) {
  $files = @(
    (Join-Path $root "resources\app\out\vs\code\electron-sandbox\workbench\workbench.html"),
    (Join-Path $root "resources\app\out\main.js"),
    (Join-Path $root "resources\app\product.json")
  )
  foreach ($file in $files) {
    if ((Test-Path -LiteralPath $file) -and -not (Test-CanWriteFile $file)) { return $false }
  }
  $wbDir = Join-Path $root "resources\app\out\vs\code\electron-sandbox\workbench"
  return (Test-CanCreateFile $wbDir)
}

function Clear-ReadOnly([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  if ($item -and $item.IsReadOnly) { $item.IsReadOnly = $false }
}

if ($DiscoverOnly) {
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($finder in @("Add-RootsFromKnownFolders", "Add-RootsFromRegistry", "Add-RootsFromShortcuts", "Add-RootsFromCommands")) {
    try { & $finder $found } catch { Write-Host $_.Exception.Message }
  }
  foreach ($p in @($InstallPath)) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $resolved = Resolve-CursorRoot $p
    if (-not $resolved) {
      Write-Host ("NOT_CURSOR " + $p)
      exit 1
    }
    Add-CursorRoot $found $resolved
  }
  if ($found.Count -eq 0) {
    Write-Host "NO_CURSOR_FOUND"
    exit 1
  }
  foreach ($root in $found) { Write-Host $root }
  exit 0
}

$here = Split-Path -Parent $PSCommandPath
$logPath = Join-Path $here "install-log.txt"
function Write-Log([string]$message) {
  $line = "{0}  {1}`r`n" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message
  $enc = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::AppendAllText($logPath, $line, $enc)
  Write-Host $message
}

try {
  Set-Content -LiteralPath $logPath -Value ("started " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

  $source = Join-Path $here "chat-bidi.js"
  if (-not (Test-Path -LiteralPath $source)) {
    throw "chat-bidi.js was not found next to install.ps1. Keep the whole folder together, then run apply.bat."
  }
  $scriptText = [System.IO.File]::ReadAllText($source)
  if ($scriptText -notlike "*__cursorChatBidiInstalled*") {
    throw "chat-bidi.js is incomplete. Copy that file again."
  }

  $cursor = Get-Process -Name "Cursor" -ErrorAction SilentlyContinue
  if ($cursor) {
    throw "Cursor is still running. Use File, then Exit. In Task Manager, confirm Cursor.exe is gone, then run apply.bat again."
  }

  function Get-FileChecksum([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { $hash = $sha.ComputeHash($stream) }
    finally {
      $stream.Dispose()
      $sha.Dispose()
    }
    return ([Convert]::ToBase64String($hash)).TrimEnd("=")
  }

  function Backup-Once([string]$file, [string]$destDir, [string]$name) {
    if (-not (Test-Path -LiteralPath $file)) { return }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dest = Join-Path $destDir $name
    if (-not (Test-Path -LiteralPath $dest)) {
      Copy-Item -LiteralPath $file -Destination $dest
      Write-Log ("backup: " + $dest)
    }
  }

  $marker = "CURSOR_CHAT_BIDI"
  $bootstrap = @'
/*CURSOR_CHAT_BIDI_START*/
;Promise.all([import("node:fs"),import("node:path"),import("node:url"),import("electron")]).then(function(mods){try{var fs=mods[0],path=mods[1],url=mods[2],electron=mods[3];var dir=path.dirname(url.fileURLToPath(import.meta.url));var candidates=[];if(process.env.APPDATA)candidates.push(path.join(process.env.APPDATA,"Cursor","User","cursor-chat-bidi","chat-bidi.js"));candidates.push(path.join(dir,"vs","code","electron-sandbox","workbench","cursor-chat-bidi.js"));var code="";for(var i=0;i<candidates.length;i++){try{var text=fs.readFileSync(candidates[i],"utf8");if(text&&text.indexOf("__cursorChatBidiInstalled")>=0){code=text;break;}}catch(e){}}if(!code)return;var app=electron.app,BrowserWindow=electron.BrowserWindow,hooked=new WeakSet();function inject(wc){if(!wc||wc.isDestroyed())return;wc.executeJavaScript(code).catch(function(){});}function hook(win){if(!win||win.isDestroyed()||!win.webContents||hooked.has(win))return;hooked.add(win);var wc=win.webContents;wc.on("dom-ready",function(){inject(wc);});wc.on("did-finish-load",function(){inject(wc);});wc.on("did-navigate-in-page",function(){inject(wc);});if(!wc.isLoading())inject(wc);}function arm(){BrowserWindow.getAllWindows().forEach(hook);app.on("browser-window-created",function(_e,win){hook(win);});}if(app.isReady())arm();else app.whenReady().then(arm);}catch(e){}}).catch(function(){});
/*CURSOR_CHAT_BIDI_END*/
'@

  $userDir = Join-Path $env:APPDATA "Cursor\User\cursor-chat-bidi"
  New-Item -ItemType Directory -Force -Path $userDir | Out-Null
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText((Join-Path $userDir "chat-bidi.js"), $scriptText, $utf8)

  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($finder in @("Add-RootsFromKnownFolders", "Add-RootsFromRegistry", "Add-RootsFromShortcuts", "Add-RootsFromCommands")) {
    try { & $finder $roots }
    catch { Write-Log ("search failed: " + $_.Exception.Message) }
  }

  $manual = New-Object System.Collections.Generic.List[string]
  foreach ($p in @($InstallPath)) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    [void]$manual.Add($p)
    $resolved = Resolve-CursorRoot $p
    if (-not $resolved) {
      throw "This folder is not a Cursor install: $p`nChoose the folder that contains Cursor.exe."
    }
    Add-CursorRoot $roots $resolved
  }

  if ($roots.Count -eq 0) {
    Write-Host ""
    Write-Host "Cursor was not found automatically."
    Write-Host "Right-click the Cursor shortcut, choose Open file location,"
    Write-Host "and paste the folder that contains Cursor.exe."
    $typed = Read-Host "Folder"
    $resolved = Resolve-CursorRoot $typed
    if (-not $resolved) {
      throw "Cursor was not found. Paste the folder from Open file location, or run: apply.bat `"D:\Apps\Cursor`""
    }
    Add-CursorRoot $roots $resolved
    [void]$manual.Add($typed)
  }

  $needsAdmin = $false
  foreach ($root in $roots) {
    if (-not (Test-RootWritable $root)) { $needsAdmin = $true }
  }
  if ($needsAdmin -and -not (Test-IsAdmin)) {
    $elevated = -1
    try {
      $elevated = Start-Elevated @($manual.ToArray())
    } catch {
      Write-Log ("Administrator permission was not granted: " + $_.Exception.Message)
      Write-Host "Administrator permission was not granted."
      Write-Host "Copies in your user folder will still be updated."
    }
    if ($elevated -eq 0) { exit 0 }
    if ($elevated -gt 0) {
      throw "The administrator window did not finish the install. Run apply.bat again and click Yes."
    }
  }

  $backupRoot = Join-Path $userDir "backup"
  $patchedRoots = New-Object System.Collections.Generic.List[string]
  $skippedRoots = New-Object System.Collections.Generic.List[string]

  foreach ($root in $roots) {
    if (-not (Test-RootWritable $root)) {
      [void]$skippedRoots.Add($root)
      Write-Log ("skipped, this folder needs administrator permission: " + $root)
      continue
    }

    Write-Log ("updating: " + $root)
    $outDir = Join-Path $root "resources\app\out"
    $appDir = Join-Path $root "resources\app"
    $wbDir = Join-Path $outDir "vs\code\electron-sandbox\workbench"
    $htmlPath = Join-Path $wbDir "workbench.html"
    $jsTarget = Join-Path $wbDir "cursor-chat-bidi.js"
    $mainPath = Join-Path $outDir "main.js"
    $productPath = Join-Path $appDir "product.json"
    $safeName = ($root.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $destDir = Join-Path $backupRoot $safeName

    Backup-Once $htmlPath $destDir "workbench.html"
    Backup-Once $mainPath $destDir "main.js"
    Backup-Once $productPath $destDir "product.json"
    [System.IO.File]::WriteAllText((Join-Path $destDir "install-root.txt"), $root, $utf8)

    Clear-ReadOnly $jsTarget
    [System.IO.File]::WriteAllText($jsTarget, $scriptText, $utf8)
    Write-Log ("  wrote: " + $jsTarget)

    Clear-ReadOnly $htmlPath
    $html = [System.IO.File]::ReadAllText($htmlPath)
    if ($html -notlike "*$marker*") {
      $needle = '<script src="./workbench.js" type="module"></script>'
      if (-not $html.Contains($needle)) {
        throw "This Cursor version was not recognized: $htmlPath"
      }
      $insert = "<!-- $marker -->`n`t<script src=`"./cursor-chat-bidi.js`"></script>`n`t$needle"
      $html = $html.Replace($needle, $insert)
      [System.IO.File]::WriteAllText($htmlPath, $html, $utf8)
      Write-Log "  workbench.html updated"
    } else {
      Write-Log "  workbench.html was already updated"
    }

    if (Test-Path -LiteralPath $productPath) {
      Clear-ReadOnly $productPath
      $product = [System.IO.File]::ReadAllText($productPath)
      $keyPattern = '("vs/code/electron-sandbox/workbench/workbench\.html"\s*:\s*")[^"]+(")'
      if ($product -match $keyPattern) {
        $hash = Get-FileChecksum $htmlPath
        $updated = [regex]::Replace($product, $keyPattern, ('${1}' + $hash + '${2}'))
        if ($updated -ne $product) {
          [System.IO.File]::WriteAllText($productPath, $updated, $utf8)
          Write-Log "  product.json checksum updated"
        } else {
          Write-Log "  product.json checksum already matched"
        }
      } else {
        Write-Log "  product.json has no workbench.html checksum"
      }
    }

    if (Test-Path -LiteralPath $mainPath) {
      Clear-ReadOnly $mainPath
      $main = [System.IO.File]::ReadAllText($mainPath)
      $startMark = $marker + "_START"
      if ($main -notlike "*$startMark*") {
        if (-not $main.EndsWith("`n")) { $main += "`n" }
        $main += $bootstrap + "`n"
        [System.IO.File]::WriteAllText($mainPath, $main, $utf8)
        Write-Log "  main.js updated"
      } else {
        Write-Log "  main.js was already updated"
      }
    }

    [void]$patchedRoots.Add($root)
  }

  if ($patchedRoots.Count -eq 0) {
    throw "Nothing was updated. Run apply.bat again and click Yes if Windows asks for administrator permission."
  }

  Write-Log ("Done. Updated " + $patchedRoots.Count + " Cursor install(s).")
  Write-Host ""
  Write-Host "Updated:"
  foreach ($root in $patchedRoots) { Write-Host ("  " + $root) }
  if ($skippedRoots.Count -gt 0) {
    Write-Host ""
    Write-Host "Not updated, because administrator permission is required:"
    foreach ($root in $skippedRoots) { Write-Host ("  " + $root) }
    Write-Host "Run apply.bat again and click Yes when Windows asks."
  }
  Write-Host ""
  Write-Host "Open Cursor."
  Write-Host "A paragraph that starts in Persian aligns right."
  Write-Host "A paragraph that starts in English aligns left."
} catch {
  Write-Host ""
  Write-Host ("ERROR: " + $_.Exception.Message)
  if ($logPath) {
    Add-Content -LiteralPath $logPath -Value ("ERROR: " + $_.Exception.Message) -Encoding UTF8
  }
  Write-Host "Press Enter to close."
  [void](Read-Host)
  exit 1
}

Write-Host "Press Enter to close."
[void](Read-Host)
exit 0
