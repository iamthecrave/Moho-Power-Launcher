# ==========================================================================
#  Moho Power Launcher - shared code
#  Paths, settings, the script library, the install record, and the
#  Tools-panel list. Every other file loads this one.
#
#  Copyright (C) 2026 Cheesoid: Doug Craven and Claude (an AI model by Anthropic)
#  PolyForm Noncommercial License 1.0.0 - see LICENSE
#
#  THE ONE RULE
#  The launcher only ever removes files it put in your scripts folder itself.
#  Each file it copies is recorded (path + fingerprint) in installed.json.
#  Anything else in your scripts folder - scripts you installed with Moho,
#  your own scripts - is never touched. If you edit a file the launcher
#  installed, it becomes yours and the launcher stops managing it.
# ==========================================================================

# ---------- names and places ----------
$MPL = @{}
$MPL.Name      = 'Moho Power Launcher'
$MPL.Version   = '1.2.0c-search'
$MPL.MutexName = 'Local\MohoPowerLauncher.Running'   # held while a launcher window is open

$MPL.AppDir   = $PSScriptRoot

# On this computer only: where Moho and the folders are, and the log
$MPL.DataDir  = Join-Path $env:LOCALAPPDATA 'Moho Power Launcher'
$MPL.Settings = Join-Path $MPL.DataDir 'settings.json'
$MPL.Log      = Join-Path $MPL.DataDir 'log.txt'

# Shared by every computer that uses the same Custom Content Folder (Dropbox, OneDrive...):
# the install record, what's ticked, saved sets and toolbar groups. They live in a
# "Moho Power Launcher" folder inside the Custom Content Folder - see MPL-UseShared.
$MPL.SharedName = 'Moho Power Launcher'
$MPL.Shared  = ''
$MPL.Choices = ''
$MPL.Record  = Join-Path $MPL.DataDir 'installed.json'     # until the content folder is known
$MPL.Toolbar = Join-Path $MPL.DataDir 'toolbar.json'

# Settings that belong to one computer; everything else is shared
$MPL.LocalKeys = @('MohoPath', 'ContentFolder', 'MasterFolder', 'LastContentFolder')

$MPL.Suffix = '_for-moho-install-script-command'   # Moho's own name ending for script packages
$MPL.Label  = 'launcher.txt'                        # one line in a package folder: "Column | Name"

# Folder names that mark the top of a Moho scripts layout inside a package
$MPL.ScriptDirs = @('tool', 'menu', 'utility', 'ScriptResources', 'layer', 'button', 'modules')

# Marker lines around everything the launcher adds to _tool_list.txt
$MPL.TBBegin = '/* Moho Power Launcher: begin */'
$MPL.TBEnd   = '/* Moho Power Launcher: end */'

$MPL.IconSuffixes = @('.png', '@2x.png', '_large.png', '_cursor.png')   # a script's icon files

# The launcher's columns: five that are always there, plus up to five of your own (MyColumns)
$MPL.FixedColumns = @('Draw', 'Rig', 'Animate', 'All Purpose', 'Unsorted')
$MPL.MaxMyColumns = 5


# ==========================================================================
#  Small helpers
# ==========================================================================

$script:MPLLog      = New-Object System.Collections.Generic.List[string]
$script:MPLWarnings = New-Object System.Collections.Generic.List[string]
$script:MPLNotes    = New-Object System.Collections.Generic.List[string]   # good news to show once, e.g. an edit saved

function MPL-Log([string]$message) {
    $script:MPLLog.Add(("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $message))
}

# A note is logged and shown once before Moho starts (nothing to decide)
function MPL-Note([string]$message) {
    $script:MPLNotes.Add($message)
    MPL-Log $message
}

# A warning is logged and also shown to the user before Moho starts
function MPL-Warn([string]$message) {
    $script:MPLWarnings.Add($message)
    MPL-Log ("WARNING: " + $message)
}

# The data folder is made only when something is first saved,
# so cancelling the installer leaves nothing behind.
function MPL-EnsureDataDir {
    if (-not (Test-Path -LiteralPath $MPL.DataDir)) {
        New-Item -ItemType Directory -Path $MPL.DataDir -Force | Out-Null
    }
}

# Adds this session's log lines to log.txt, keeping only the last 400 old lines
function MPL-SaveLog {
    try {
        MPL-EnsureDataDir
        $old = @()
        if (Test-Path -LiteralPath $MPL.Log) {
            $old = @(Get-Content -LiteralPath $MPL.Log -Tail 400 -Encoding UTF8)
        }
        MPL-WriteLines $MPL.Log ($old + $script:MPLLog) $null
        $script:MPLLog.Clear()
    } catch {
        # a log that can't be written must never stop the launcher
    }
}

function MPL-Box([string]$message, [string]$icon = 'Information', [string]$buttons = 'OK') {
    return [System.Windows.Forms.MessageBox]::Show($message, $MPL.Name, $buttons, $icon)
}

# True only for a path that is filled in and exists.
# (Test-Path throws on an empty string, so every check goes through here.)
function MPL-Exists([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try { return (Test-Path -LiteralPath $path) } catch { return $false }
}

# True when two paths are the same folder. If either is unknown, there is nothing to compare,
# so that also counts as the same.
function MPL-SameFolder([string]$a, [string]$b) {
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { return $true }
    try {
        $fullA = [IO.Path]::GetFullPath($a).TrimEnd('\', '/')
        $fullB = [IO.Path]::GetFullPath($b).TrimEnd('\', '/')
        return ($fullA -ieq $fullB)
    } catch {
        return ($a -ieq $b)
    }
}

# Text files the launcher writes are UTF-8 without a BOM
function MPL-WriteText([string]$path, [string]$text) {
    # a few tries: Dropbox can hold a file for a moment while it syncs
    for ($attempt = 1; ; $attempt++) {
        try {
            [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
            return
        } catch [System.IO.IOException] {
            if ($attempt -ge 10) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

# Read a JSON file the launcher wrote. Read as UTF-8 so names with accents survive.
function MPL-ReadJson([string]$path) {
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# Read a text file as lines, remembering its line endings, BOM and final newline,
# so MPL-WriteLines can write it back byte for byte (that's what makes undo exact).
function MPL-ReadLines([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $skip = 0
    if ($hasBom) { $skip = 3 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $skip, $bytes.Length - $skip)

    $newline = "`r`n"
    if (-not $text.Contains("`r`n") -and $text.Contains("`n")) { $newline = "`n" }

    # Lines split on either ending, so a file with mixed endings still reads correctly
    $endsWithNewline = $text.EndsWith("`n")
    $body = $text -replace '\r?\n$', ''

    $lines = @()
    if ($text.Length -gt 0) { $lines = $body -split '\r?\n' }

    return @{ Lines = [string[]]$lines; NL = $newline; Bom = $hasBom; Final = $endsWithNewline }
}

# Write lines in the format MPL-ReadLines found (or Windows style, UTF-8, final newline)
function MPL-WriteLines([string]$path, $lines, $format) {
    if (-not $format) { $format = @{ NL = "`r`n"; Bom = $false; Final = $true } }
    $text = @($lines) -join $format.NL
    if ($format.Final) { $text += $format.NL }
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($format.Bom)))
}

# A file's fingerprint
function MPL-Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

# Delete a file, retrying for up to 3 seconds in case Dropbox, antivirus or an editor has it open
function MPL-RemoveWithRetry([string]$path) {
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            Remove-Item -LiteralPath $path -Force -Confirm:$false -ErrorAction Stop
            return $true
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    return $false
}

# Delete a folder only if it is empty
function MPL-RemoveIfEmpty([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    if (Get-ChildItem -LiteralPath $path -Force | Select-Object -First 1) { return $false }
    try {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# A package's key: its folder or file name without "moho-script_", Moho's
# install-command suffix or ".lua", in lower case. Ticks and configurations use it.
function MPL-Key([string]$name) {
    $key = $name -replace '^moho-script_', ''
    $key = $key -replace "$([regex]::Escape($MPL.Suffix))$", ''
    $key = $key -replace '\.lua$', ''
    return $key.ToLower()
}

# A saved list can come back from JSON as an array inside an array: flatten it to plain strings
function MPL-Flatten($value) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($x in @($value)) {
        if ($null -eq $x) { continue }
        if ($x -is [string]) {
            $out.Add($x)
        } elseif ($x -is [System.Collections.IEnumerable]) {
            foreach ($y in (MPL-Flatten $x)) { $out.Add([string]$y) }
        } else {
            $out.Add([string]$x)
        }
    }
    return ,([string[]]$out.ToArray())
}


# ==========================================================================
#  Settings
# ==========================================================================
#  On this computer (settings.json in %LOCALAPPDATA%\Moho Power Launcher):
#  MohoPath           Moho.exe
#  ContentFolder      Moho's Custom Content Folder (it holds the 'scripts' folder)
#  MasterFolder       your script library: one folder per script
#  LastContentFolder  the content folder the last launch filled (to tidy it if you switch)
#
#  Shared (choices.json in <ContentFolder>\Moho Power Launcher):
#  MyColumns        your own launcher columns (up to 5), shown in a second row
#  Columns, SplitTag  from 1.0/1.1 (extra Columns become MyColumns; SplitTag is no longer used)
#  AutoGroups       e.g. {"ai_": "AI"}: unsorted tools whose name starts ai_ go in Tools-panel group AI
#  LooseMenuFolder  Scripts-menu folder for single .lua files
#  Selected, LastConfiguration, Configurations: what is ticked, and saved sets
#  LeaveAlone       scripts installed through Moho that you chose not to add ("Not these")

function MPL-SharedDir([string]$contentFolder) {
    return (Join-Path $contentFolder $MPL.SharedName)
}

# Point the record, toolbar groups and choices at this content folder's shared folder
function MPL-UseShared([string]$contentFolder) {
    if (MPL-Exists $contentFolder) {
        $dir = MPL-SharedDir $contentFolder
        $MPL.Shared  = $dir
        $MPL.Choices = Join-Path $dir 'choices.json'
        $MPL.Record  = Join-Path $dir 'installed.json'
        $MPL.Toolbar = Join-Path $dir 'toolbar.json'
    } else {
        $MPL.Shared  = ''
        $MPL.Choices = ''
        $MPL.Record  = Join-Path $MPL.DataDir 'installed.json'
        $MPL.Toolbar = Join-Path $MPL.DataDir 'toolbar.json'
    }
}

function MPL-EnsureFolderOf([string]$file) {
    $dir = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($MPL.Shared -and $dir -eq $MPL.Shared) {
        $about = Join-Path $dir '_About this folder.txt'
        if (-not (Test-Path -LiteralPath $about)) {
            MPL-WriteText $about ("Moho Power Launcher keeps its shared data here, so every computer that uses this folder`r`n" +
                                  "(through Dropbox, OneDrive...) sees the same ticks, saved sets, toolbar groups and install record.`r`n`r`n" +
                                  "installed.json  the files the launcher put in the scripts folder (it only ever removes those)`r`n" +
                                  "choices.json    what's ticked, saved sets, columns`r`n" +
                                  "toolbar.json    Tools-panel groups (Sort toolbar...)`r`n`r`n" +
                                  "Please don't edit these by hand.`r`n")
        }
    }
}

# Copy a JSON object's properties onto the settings, turning nested objects into dictionaries
function MPL-MergeSettings($s, $json) {
    foreach ($p in $json.PSObject.Properties) {
        if ($p.Name -eq 'Note') { continue }
        if ($p.Name -eq 'Configurations' -or $p.Name -eq 'AutoGroups') {
            $dict = [ordered]@{}
            if ($p.Value) {
                foreach ($q in $p.Value.PSObject.Properties) { $dict[$q.Name] = $q.Value }
            }
            $s[$p.Name] = $dict
        } else {
            $s[$p.Name] = $p.Value
        }
    }
}

function MPL-LoadSettings {
    $s = [ordered]@{
        MohoPath          = ''
        ContentFolder     = ''
        MasterFolder      = ''
        LastContentFolder = ''
        MyColumns         = @()
        Columns           = @()
        SplitTag          = ''
        AutoGroups        = [ordered]@{}
        LooseMenuFolder   = 'Downloaded'
        Selected          = @()
        LastConfiguration = ''
        Configurations    = [ordered]@{}
        LeaveAlone        = @()
    }

    # 1. this computer's settings (1.0.0 kept everything here)
    $hadSharedKeysLocally = $false
    if (Test-Path -LiteralPath $MPL.Settings) {
        try {
            $json = MPL-ReadJson $MPL.Settings
            MPL-MergeSettings $s $json
            $hadSharedKeysLocally = [bool]($json.PSObject.Properties.Name -contains 'Selected')
        } catch {
            MPL-Warn "settings.json could not be read; using defaults. ($($_.Exception.Message))"
        }
    }

    # 2. the shared choices, which win over anything kept on this computer
    MPL-UseShared $s.ContentFolder
    if ($MPL.Shared) {
        MPL-MoveToShared
        if (Test-Path -LiteralPath $MPL.Choices) {
            try {
                MPL-MergeSettings $s (MPL-ReadJson $MPL.Choices)
            } catch {
                MPL-Warn "choices.json could not be read; using this computer's choices. ($($_.Exception.Message))"
            }
        } elseif ($hadSharedKeysLocally) {
            $script:MPLSaveChoicesNow = $true          # first run after updating from 1.0.0
        }
    }

    $s.Selected = MPL-Flatten $s.Selected
    $s.Columns  = MPL-Flatten $s.Columns
    $s.MyColumns = MPL-Flatten $s.MyColumns
    # 1.0/1.1 kept every column in Columns: anything beyond the fixed ones becomes one of yours
    foreach ($c in $s.Columns) {
        if ($MPL.FixedColumns -notcontains $c -and $s.MyColumns -notcontains $c -and $s.MyColumns.Count -lt $MPL.MaxMyColumns) {
            $s.MyColumns = [string[]](@($s.MyColumns) + $c)
        }
    }
    $s.Columns = @()
    foreach ($name in @($s.Configurations.Keys)) {
        $s.Configurations[$name] = MPL-Flatten $s.Configurations[$name]
    }
    # Which shared folder these choices came from. Saving never overwrites another folder's
    # choices with these (e.g. a fresh install on a second computer, or switching folders).
    $s['__ChoicesFrom'] = $MPL.Shared
    if ($script:MPLSaveChoicesNow) {
        $script:MPLSaveChoicesNow = $false
        try { MPL-SaveSettings $s; MPL-Log 'Moved ticks and saved sets to the shared folder.' } catch {}
    }
    return $s
}

function MPL-SaveSettings($s) {
    MPL-UseShared $s.ContentFolder
    $local = [ordered]@{}
    $shared = [ordered]@{ Note = 'Shared by every computer that uses this content folder. Edit in the launcher, not here.' }
    foreach ($key in @($s.Keys)) {
        if ($key.StartsWith('__')) { continue }
        if ($MPL.LocalKeys -contains $key -or -not $MPL.Shared) { $local[$key] = $s[$key] }
        else { $shared[$key] = $s[$key] }
    }
    MPL-EnsureDataDir
    MPL-WriteText $MPL.Settings ($local | ConvertTo-Json -Depth 8)

    if ($MPL.Shared) {
        # Only write the shared choices if they're ours to write: none there yet, or these were read from there
        $from = [string]$s['__ChoicesFrom']
        $mine = (-not (Test-Path -LiteralPath $MPL.Choices)) -or ($from -and (MPL-SameFolder $from $MPL.Shared))
        if ($mine) {
            MPL-EnsureFolderOf $MPL.Choices
            MPL-WriteText $MPL.Choices ($shared | ConvertTo-Json -Depth 8)
            $s['__ChoicesFrom'] = $MPL.Shared
        } else {
            MPL-Log "This content folder already has shared choices (from another computer); kept them."
        }
    }
}

# Updating from 1.0.0: its install record and toolbar groups were kept on this computer only.
# Move them into the shared folder. If the shared folder already has a record (another computer
# got there first), add this computer's entries to it. The old files are kept, renamed *.moved.json.
function MPL-MoveToShared {
    $oldRecord  = Join-Path $MPL.DataDir 'installed.json'
    $oldToolbar = Join-Path $MPL.DataDir 'toolbar.json'

    if (Test-Path -LiteralPath $oldRecord) {
        try {
            $old = MPL-ReadJson $oldRecord
            $scriptsHere = Join-Path (Split-Path -Parent $MPL.Shared) 'scripts'
            if ($old.ScriptsFolder -and -not (MPL-SameFolder ([string]$old.ScriptsFolder) $scriptsHere)) {
                MPL-Log "This computer's old install record is for another folder ($($old.ScriptsFolder)); left where it is."
                return
            }
            $rec = MPL-LoadRecord
            if (-not $rec.Broken) {
                if ($old.Files) {
                    foreach ($p in $old.Files.PSObject.Properties) {
                        if (-not $rec.Files.ContainsKey($p.Name)) {
                            $rec.Files[$p.Name] = @{ Rel = $p.Value.Rel; Hash = $p.Value.Hash; Package = $p.Value.Package }
                        }
                    }
                }
                foreach ($d in (MPL-Flatten $old.Dirs)) { if (-not $rec.Dirs.Contains($d)) { $rec.Dirs.Add($d) } }
                if ($old.ToolListCreated -and -not $rec.ToolListCreated) {
                    $rec.ToolListCreated = $true
                    if ($old.ToolListHash) { $rec.ToolListHash = [string]$old.ToolListHash }
                }
                MPL-SaveRecord $rec
                Move-Item -LiteralPath $oldRecord -Destination (Join-Path $MPL.DataDir 'installed.moved.json') -Force
                MPL-Log "Moved this computer's install record to the shared folder ($($MPL.Shared))."
            }
        } catch {
            MPL-Warn "Couldn't move this computer's install record to the shared folder: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $oldToolbar) {
        try {
            if (-not (Test-Path -LiteralPath $MPL.Toolbar)) {
                MPL-EnsureFolderOf $MPL.Toolbar
                Copy-Item -LiteralPath $oldToolbar -Destination $MPL.Toolbar
            }
            Move-Item -LiteralPath $oldToolbar -Destination (Join-Path $MPL.DataDir 'toolbar.moved.json') -Force
        } catch {
            MPL-Warn "Couldn't move this computer's toolbar groups to the shared folder: $($_.Exception.Message)"
        }
    }
}

function MPL-ScriptsFolder($s) {
    return (Join-Path $s.ContentFolder 'scripts')
}


# ==========================================================================
#  Finding Moho and its Custom Content Folder
# ==========================================================================

function MPL-FindMoho {
    $found = @()

    # 1. Windows' list of installed programs
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallKeys) {
        foreach ($key in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like 'Moho*' -and $p.InstallLocation) {
                $exe = Join-Path $p.InstallLocation 'Moho.exe'
                if (Test-Path -LiteralPath $exe) { $found += Get-Item -LiteralPath $exe }
            }
        }
    }

    # 2. The usual program folders
    $patterns = @(
        "$env:ProgramFiles\*\Moho.exe",
        "$env:ProgramFiles\*\*\Moho.exe",
        "${env:ProgramFiles(x86)}\*\Moho.exe",
        "${env:ProgramFiles(x86)}\*\*\Moho.exe"
    )
    foreach ($pattern in $patterns) {
        $found += @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)
    }

    # the newest Moho wins
    $best = $found | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }
    return ''
}

# The folder Moho itself is set to read, or '' if unknown.
# Moho keeps it as "EditableFilesDir" in
#   %APPDATA%\Lost Marble\Moho Pro\<version>\Moho Pro<version>.user.settings
# with lines like:  "EditableFilesDir"<tab>"C:\\Users\\me\\Documents\\Moho Pro"
function MPL-MohoContentFolder {
    $files = @()
    foreach ($edition in @('Moho Pro', 'Moho Debut', 'Moho')) {
        $pattern = Join-Path $env:APPDATA "Lost Marble\$edition\*\*.user.settings"
        $files += @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)
    }
    foreach ($file in ($files | Sort-Object LastWriteTime -Descending)) {
        $match = Select-String -LiteralPath $file.FullName -Encoding UTF8 -Pattern '^"EditableFilesDir"\s+"(.*)"\s*$' |
                 Select-Object -First 1
        if ($match) {
            $dir = $match.Matches[0].Groups[1].Value -replace '\\\\', '\'
            if (MPL-Exists $dir) { return $dir }
        }
    }
    return ''
}

# Moho's own setting, or the default Documents\Moho Pro
function MPL-FindContentFolder {
    $dir = MPL-MohoContentFolder
    if ($dir) { return $dir }
    $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Moho Pro'
    if (Test-Path -LiteralPath $default) { return $default }
    return ''
}

# Moho's built-in Tools-panel list (used when your scripts folder has none of its own)
function MPL-BuiltInToolList($s) {
    if (-not $s.MohoPath) { return '' }
    $path = Join-Path (Split-Path -Parent $s.MohoPath) 'Resources\Support\Scripts\Tool\_tool_list.txt'
    if (Test-Path -LiteralPath $path) { return $path }
    return ''
}


# ==========================================================================
#  The install record  (installed.json)
# ==========================================================================
#  Files             rel path (lower case) -> { Rel; Hash; Package }
#  Dirs              folders (rel) the launcher created
#  ToolListCreated   the launcher created scripts\tool\_tool_list.txt ...
#  ToolListHash      ... and this is how it looked when the launcher last wrote it
#  ToolListAdded     the exact lines the launcher added to the tool list (so it can take them out again)

function MPL-NewRecord {
    return @{
        Files           = @{}
        Dirs            = New-Object System.Collections.Generic.List[string]
        ToolListCreated = $false
        ToolListHash    = ''
        ToolListAdded   = New-Object System.Collections.Generic.List[string]
    }
}

function MPL-LoadRecord {
    $r = MPL-NewRecord
    if (-not (Test-Path -LiteralPath $MPL.Record)) { return $r }
    try {
        $json = MPL-ReadJson $MPL.Record
        if ($json.Files) {
            foreach ($p in $json.Files.PSObject.Properties) {
                $r.Files[$p.Name] = @{ Rel = $p.Value.Rel; Hash = $p.Value.Hash; Package = $p.Value.Package; Key = [string]$p.Value.Key }
            }
        }
        foreach ($d in (MPL-Flatten $json.Dirs)) {
            if (-not $r.Dirs.Contains($d)) { $r.Dirs.Add($d) }
        }
        $r.ToolListCreated = [bool]$json.ToolListCreated
        if ($json.ToolListHash) { $r.ToolListHash = [string]$json.ToolListHash }
        foreach ($line in (MPL-Flatten $json.ToolListAdded)) { $r.ToolListAdded.Add($line) }
    } catch {
        # Keep the broken file for inspection, and remove nothing this time:
        # without the record, the launcher can't tell its files from yours.
        $keep = Join-Path (Split-Path -Parent $MPL.Record) ("installed.broken-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        try { Copy-Item -LiteralPath $MPL.Record -Destination $keep -Force } catch {}
        MPL-Warn ("installed.json could not be read (kept as $(Split-Path -Leaf $keep)), so nothing was removed this time. " +
                  "($($_.Exception.Message))")
        $r.Broken = $true
    }
    return $r
}

function MPL-SaveRecord($r) {
    MPL-EnsureFolderOf $MPL.Record
    $out = [ordered]@{
        Note            = 'Files Moho Power Launcher put in your scripts folder. Do not edit.'
        Files           = $r.Files
        Dirs            = @($r.Dirs)
        ToolListCreated = $r.ToolListCreated
        ToolListHash    = $r.ToolListHash
        ToolListAdded   = @($r.ToolListAdded)
    }
    MPL-WriteText $MPL.Record ($out | ConvertTo-Json -Depth 6)
}


# ==========================================================================
#  The script library  (the "scripts master folder")
# ==========================================================================

# The column and name in a package's launcher.txt, or $null if it has none
function MPL-ReadLabel([string]$packageFolder) {
    $file = Join-Path $packageFolder $MPL.Label
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $line = Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue |
            Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') } |
            Select-Object -First 1
    if (-not $line -or -not $line.Contains('|')) { return @{ Column = ''; Name = ''; Bad = $true } }
    $parts = $line.Split('|', 2)
    return @{ Column = $parts[0].Trim(); Name = $parts[1].Trim(); Bad = $false }
}

function MPL-WriteLabel([string]$packageFolder, [string]$column, [string]$name) {
    MPL-WriteText (Join-Path $packageFolder $MPL.Label) ("$column | $name`r`n")
}

# The folder inside a package that holds tool\, menu\, utility\ ... (the package may wrap it in extra folders)
function MPL-PackageRoot([string]$dir) {
    $candidates = @(Get-Item -LiteralPath $dir) +
                  @(Get-ChildItem -LiteralPath $dir -Directory -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object { $_.FullName.Length })                  # shallowest first
    foreach ($candidate in $candidates) {
        $subNames = @(Get-ChildItem -LiteralPath $candidate.FullName -Directory -ErrorAction SilentlyContinue |
                      ForEach-Object { $_.Name })
        foreach ($sub in $subNames) {
            if ($MPL.ScriptDirs -contains $sub) { return $candidate.FullName }
        }
    }
    return $null
}

# Every package in the library: Key, Name, Group (column), Path, Loose (a single .lua file)
function MPL-ReadMaster($s) {
    $items = @()
    $seen = @{}
    if (-not (MPL-Exists $s.MasterFolder)) { return $items }

    $entries = @(Get-ChildItem -LiteralPath $s.MasterFolder -Directory) +
               @(Get-ChildItem -LiteralPath $s.MasterFolder -File -Filter '*.lua')

    foreach ($entry in ($entries | Sort-Object LastWriteTime -Descending)) {     # newest first
        if ($entry.Name.StartsWith('_')) { continue }                          # _archive and the like

        $key = MPL-Key $entry.Name
        if ($seen.ContainsKey($key)) {
            MPL-Warn "Two copies of '$key' in your script library. Using the newer: $($seen[$key])"
            continue
        }
        $seen[$key] = $entry.Name

        $column = 'Unsorted'
        $name = $entry.Name -replace "$([regex]::Escape($MPL.Suffix))$", '' -replace '^moho-script_', '' -replace '\.lua$', ''
        if ($entry.PSIsContainer) {
            $label = MPL-ReadLabel $entry.FullName
            if ($label -and $label.Bad) {
                MPL-Warn "$($entry.Name)\$($MPL.Label) should read: Column | Name   (e.g. Animate | Key Tools (AE))"
            } elseif ($label) {
                if ($label.Column) { $column = $label.Column }
                if ($label.Name)   { $name = $label.Name }
            }
        }
        $items += [pscustomobject]@{
            Key   = $key
            Name  = $name
            Group = $column
            Path  = $entry.FullName
            Loose = -not $entry.PSIsContainer
        }
    }
    return $items
}

# The files one package puts in the scripts folder: a list of @{ Src; Rel }
function MPL-PackageFiles($s, $item) {
    $out = @()
    if ($item.Loose) {
        $file = Get-Item -LiteralPath $item.Path
        $out += @{ Src = $file.FullName; Rel = (Join-Path (Join-Path 'menu' $s.LooseMenuFolder) $file.Name) }
        return $out
    }

    $root = MPL-PackageRoot $item.Path
    if (-not $root) {
        MPL-Warn "$($item.Name): no tool, menu or utility folder inside its package. Skipped."
        return $out
    }
    $base = $root.TrimEnd('\', '/')
    foreach ($file in (Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
        if ($file.Name -eq $MPL.Label) { continue }
        $rel = $file.FullName.Substring($base.Length).TrimStart('\', '/')
        # files loose at the top of a package (readme, licence, backups) don't belong in scripts
        if (-not $rel.Contains('\') -and -not $rel.Contains('/')) { continue }
        $out += @{ Src = $file.FullName; Rel = $rel }
    }
    return $out
}


# ==========================================================================
#  Putting the chosen scripts in place
# ==========================================================================
#  Removes what the launcher installed last time and is no longer wanted,
#  then copies in the chosen packages. Never removes or overwrites a file
#  it did not install. Returns a one-line summary.

function MPL-Apply($s, $chosenItems) {
    $scripts = MPL-ScriptsFolder $s
    if (-not (Test-Path -LiteralPath $scripts)) { New-Item -ItemType Directory -Path $scripts -Force | Out-Null }
    # --- 0. This computer filled a different content folder last time: take the launcher's
    #        files out of that one first (using that folder's own record)
    $last = [string]$s.LastContentFolder
    if ($last -and -not (MPL-SameFolder $last $s.ContentFolder) -and (MPL-Exists $last)) {
        $oldSettings = @{}
        foreach ($k in $s.Keys) { $oldSettings[$k] = $s[$k] }
        $oldSettings.ContentFolder = $last
        MPL-UseShared $last
        try { MPL-Log ("Content folder changed. Old folder: " + (MPL-RemoveAll $oldSettings)) }
        finally { MPL-UseShared $s.ContentFolder }
    }
    MPL-UseShared $s.ContentFolder
    $rec = MPL-LoadRecord
    $script:MPLLibraryItems = $null                  # read the library afresh for this launch

    # --- 1. What the chosen packages want in scripts (rel path -> source).
    #        If two packages carry the same file with different contents, the newer copy wins.
    $want = @{}
    foreach ($item in $chosenItems) {
        foreach ($f in (MPL-PackageFiles $s $item)) {
            $k = $f.Rel.ToLower()
            $candidate = @{ Src = $f.Src; Rel = $f.Rel; Package = $item.Name; Key = $item.Key }
            if (-not $want.ContainsKey($k)) { $want[$k] = $candidate; continue }

            $first = $want[$k]
            if ((MPL-Hash $first.Src) -eq (MPL-Hash $f.Src)) { continue }     # same file: nothing to decide
            $firstTime = (Get-Item -LiteralPath $first.Src).LastWriteTime
            $thisTime  = (Get-Item -LiteralPath $f.Src).LastWriteTime
            if ($thisTime -gt $firstTime) {
                MPL-Warn "'$($f.Rel)' is in both $($first.Package) and $($item.Name). Used the newer copy from $($item.Name)."
                $want[$k] = $candidate
            } else {
                MPL-Warn "'$($f.Rel)' is in both $($first.Package) and $($item.Name). Used the newer copy from $($first.Package)."
            }
        }
    }

    # --- 2. Take out what the launcher installed before, unless it's wanted again unchanged
    $removed = 0
    $kept = 0
    if (-not $rec.Broken) {
        foreach ($k in @($rec.Files.Keys)) {
            $entry = $rec.Files[$k]
            $dest = Join-Path $scripts $entry.Rel

            if (-not (Test-Path -LiteralPath $dest)) {           # already gone
                $rec.Files.Remove($k)
                continue
            }
            $hashNow = MPL-Hash $dest
            if ($hashNow -ne $entry.Hash) {
                # You edited it in Moho's scripts folder. Save the edit into your library, so the
                # launcher keeps your version from now on. Never overwrite anything without a backup.
                $libraryCopy = MPL-FindLibrarySource $s $entry
                if (-not $libraryCopy) {
                    MPL-Warn "You changed '$($entry.Rel)', and its package is no longer in your library, so it's yours now: the launcher won't remove or replace it."
                    $rec.Files.Remove($k)
                    MPL-SaveRecord $rec
                    continue
                }
                if ((MPL-Hash $libraryCopy) -eq $entry.Hash) {
                    try {
                        [void](MPL-BackupLibraryFile $s $libraryCopy 'before-your-edit')
                        Copy-Item -LiteralPath $dest -Destination $libraryCopy -Force -ErrorAction Stop
                        $entry.Hash = $hashNow
                        MPL-SaveRecord $rec
                        MPL-Note "Saved your changes to $(Split-Path -Leaf $entry.Rel) ($($entry.Package)) in your library."
                    } catch {
                        MPL-Warn "You changed '$($entry.Rel)' but it couldn't be saved to your library ($($_.Exception.Message)). It's yours now: the launcher won't remove or replace it."
                        $rec.Files.Remove($k)
                        MPL-SaveRecord $rec
                        continue
                    }
                } else {
                    # Both changed: your edit here, and the library copy (a newer download?). Keep both.
                    $saved = MPL-BackupLibraryFile $s $dest 'your-edit' $libraryCopy
                    MPL-Warn ("You changed '$($entry.Rel)', and the library copy changed too. Both are kept: your edit stays in Moho " +
                              "(and a copy is in $saved); the library has the other version. The launcher won't remove or replace your edit.")
                    $rec.Files.Remove($k)
                    MPL-SaveRecord $rec
                    continue
                }
            }
            if ($want.ContainsKey($k) -and (MPL-Hash $want[$k].Src) -eq $hashNow) {
                $kept++                                          # wanted again, same version: leave it
                continue
            }
            if (MPL-RemoveWithRetry $dest) {
                $rec.Files.Remove($k)
                $removed++
                MPL-SaveRecord $rec
            } else {
                MPL-Warn "Couldn't remove '$($entry.Rel)': it's open in another program. It stays until next launch."
            }
        }

        # folders the launcher made that are now empty, deepest first
        foreach ($d in @($rec.Dirs | Sort-Object { $_.Length } -Descending)) {
            if (MPL-RemoveIfEmpty (Join-Path $scripts $d)) { [void]$rec.Dirs.Remove($d) }
        }
    }

    # --- 3. Copy in the chosen packages
    $added = 0
    $alreadyYours = 0
    $skipped = 0
    foreach ($k in $want.Keys) {
        if ($rec.Files.ContainsKey($k)) { continue }             # kept in step 2
        $w = $want[$k]
        $dest = Join-Path $scripts $w.Rel
        $sourceHash = MPL-Hash $w.Src

        if (Test-Path -LiteralPath $dest) {
            # A file the launcher didn't put there. It's yours, so it's left exactly as it is
            # (and not recorded, so unticking never removes it).
            if ((MPL-Hash $dest) -eq $sourceHash) {
                $alreadyYours++
            } else {
                MPL-Warn "Kept your own '$($w.Rel)'. $($w.Package) has a different version of it, so that file was not installed."
                $skipped++
            }
            continue
        }

        # make the folders, remembering the ones the launcher creates
        $parts = $w.Rel.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)
        $relDir = ''
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            if ($relDir) { $relDir = Join-Path $relDir $parts[$i] } else { $relDir = $parts[$i] }
            $full = Join-Path $scripts $relDir
            if (-not (Test-Path -LiteralPath $full)) {
                New-Item -ItemType Directory -Path $full -Force | Out-Null
                if (-not $rec.Dirs.Contains($relDir)) { $rec.Dirs.Add($relDir) }
            }
        }

        try {
            Copy-Item -LiteralPath $w.Src -Destination $dest -Force -ErrorAction Stop
        } catch {
            MPL-Warn "Couldn't copy '$($w.Rel)' from $($w.Package): $($_.Exception.Message)"
            $skipped++
            continue
        }
        $rec.Files[$k] = @{ Rel = $w.Rel; Hash = $sourceHash; Package = $w.Package; Key = $w.Key }
        $added++
        MPL-SaveRecord $rec                                      # recorded at once, so a crash can't orphan it
    }
    MPL-SaveRecord $rec

    # remember which content folder this computer filled, to tidy it if the folder changes
    if (-not (MPL-SameFolder ([string]$s.LastContentFolder) $s.ContentFolder) -or -not $s.LastContentFolder) {
        $s.LastContentFolder = $s.ContentFolder
        MPL-SaveSettings $s
    }

    $summary = "Scripts: $added added, $kept already in place, $removed removed"
    if ($alreadyYours) { $summary += ", $alreadyYours already there as your own" }
    if ($skipped)      { $summary += ", $skipped skipped (yours kept)" }
    $summary += '.'
    MPL-Log $summary
    return $summary
}

# The library file a launcher-installed file came from, or '' if its package is gone
function MPL-FindLibrarySource($s, $entry) {
    if (-not $script:MPLLibraryItems) { $script:MPLLibraryItems = @(MPL-ReadMaster $s) }
    foreach ($item in $script:MPLLibraryItems) {
        $same = ($entry.Key -and $item.Key -eq $entry.Key) -or (-not $entry.Key -and $item.Name -eq $entry.Package)
        if (-not $same) { continue }
        foreach ($f in (MPL-PackageFiles $s $item)) {
            if ($f.Rel -ieq $entry.Rel) { return $f.Src }
        }
    }
    return ''
}

# Copy a file into <library>\_backups\<package folder>\..., named with the date and a reason.
# $libraryFile says which package it belongs to (defaults to $file itself). Returns the backup's path.
function MPL-BackupLibraryFile($s, [string]$file, [string]$reason, [string]$libraryFile = '') {
    if (-not $libraryFile) { $libraryFile = $file }
    $library = $s.MasterFolder.TrimEnd('\', '/')
    $inside = $libraryFile.Substring($library.Length).TrimStart('\', '/')
    $folder = Join-Path (Join-Path $library '_backups') (Split-Path -Parent $inside)
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $name = [IO.Path]::GetFileNameWithoutExtension($libraryFile) + ("_{0}_{1:yyyy-MM-dd_HHmmss}" -f $reason, (Get-Date)) + [IO.Path]::GetExtension($libraryFile)
    $backup = Join-Path $folder $name
    Copy-Item -LiteralPath $file -Destination $backup -Force
    return $backup
}

# Take every launcher-installed file out of the scripts folder (Uninstall, or a changed content folder).
# Your own files stay.
function MPL-RemoveAll($s) {
    $scripts = MPL-ScriptsFolder $s
    $rec = MPL-LoadRecord
    if ($rec.Broken) { return 'The install record could not be read, so nothing was removed.' }

    $count = 0
    foreach ($k in @($rec.Files.Keys)) {
        $entry = $rec.Files[$k]
        $dest = Join-Path $scripts $entry.Rel
        $unchanged = (Test-Path -LiteralPath $dest) -and ((MPL-Hash $dest) -eq $entry.Hash)
        if ($unchanged -and (MPL-RemoveWithRetry $dest)) { $count++ }
        $rec.Files.Remove($k)
    }
    MPL-ToolbarRestore $s $rec                                   # before the folders: it may empty tool\
    foreach ($d in @($rec.Dirs | Sort-Object { $_.Length } -Descending)) {
        [void](MPL-RemoveIfEmpty (Join-Path $scripts $d))
        [void]$rec.Dirs.Remove($d)
    }
    MPL-SaveRecord $rec
    return "Removed $count launcher-installed files. Your own scripts were not touched."
}

# Hand files you installed yourself (with Moho's Scripts > Install Script) over to the launcher,
# after Install script... has copied them into your library. Only identical files are taken over.
function MPL-Adopt($s, [string]$package, $files, [string]$key = '') {
    $scripts = MPL-ScriptsFolder $s
    $rec = MPL-LoadRecord
    if ($rec.Broken) { return }
    foreach ($f in $files) {
        $dest = Join-Path $scripts $f.Rel
        if (-not (Test-Path -LiteralPath $dest)) { continue }
        $hash = MPL-Hash $dest
        if ($hash -eq (MPL-Hash $f.Src)) {
            $rec.Files[$f.Rel.ToLower()] = @{ Rel = $f.Rel; Hash = $hash; Package = $package; Key = $key }
        }
    }
    MPL-SaveRecord $rec
}


# ==========================================================================
#  Packages, and scripts installed through Moho
# ==========================================================================

# Suggested display name: words capitalised, the maker's initials as a tag
#   mr_key_motion  ->  Key Motion (MR)
function MPL-SuggestName([string]$fileName) {
    $tag = ''
    if ($fileName -match '^([A-Za-z]{2})_(.+)$') {
        $tag = ' (' + $Matches[1].ToUpper() + ')'
        $fileName = $Matches[2]
    }
    $words = ($fileName -replace '_', ' ').Split(' ') |
             Where-Object { $_ } |
             ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }
    return (($words -join ' ') + $tag)
}

# A script's icons sit next to it: name.png, name@2x.png, name_large.png, name_cursor.png
function MPL-IconFiles([string]$folder, [string]$scriptName) {
    $icons = @()
    foreach ($suffix in $MPL.IconSuffixes) {
        $path = Join-Path $folder ($scriptName + $suffix)
        if (Test-Path -LiteralPath $path) { $icons += Get-Item -LiteralPath $path }
    }
    return $icons
}

# Try something a few times: Dropbox, OneDrive or antivirus often hold a new file or folder
# for a moment while they look at it ("being used by another process").
function MPL-Retry([scriptblock]$action, [string]$what, [int]$tries = 10) {
    for ($attempt = 1; ; $attempt++) {
        try {
            & $action
            return
        } catch {
            if ($attempt -ge $tries) { throw "$what failed: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 500
        }
    }
}

# Build a package in the library safely. It's put together in Windows' temp folder first
# (outside Dropbox, so nothing grabs it half-made), then copied into the library. An old
# package of the same name is moved aside first and only deleted once the new one is in.
# $files: @{ Src; Rel } list. Returns the package folder.
function MPL-WritePackage($s, [string]$packagePath, $files, [string]$column, [string]$name) {
    $library = $s.MasterFolder
    $staging = Join-Path ([IO.Path]::GetTempPath()) ('MPL_package_' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($f in $files) {
            $dest = Join-Path $staging $f.Rel
            $parent = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $f.Src -Destination $dest -Force
        }
        if (-not (Test-Path -LiteralPath $staging)) { New-Item -ItemType Directory -Path $staging -Force | Out-Null }
        MPL-WriteLabel $staging $column $name

        # move any old package aside
        $oldAside = $null
        if (Test-Path -LiteralPath $packagePath) {
            $oldAside = Join-Path $library ('_replaced_' + [guid]::NewGuid().ToString('N'))
            MPL-Retry { Rename-Item -LiteralPath $packagePath -NewName (Split-Path -Leaf $oldAside) -ErrorAction Stop } 'Moving the old package aside'
        }

        # copy the new one in (copying, not renaming: a fresh folder in Dropbox can be held while it syncs)
        try {
            MPL-Retry {
                if (-not (Test-Path -LiteralPath $packagePath)) { New-Item -ItemType Directory -Path $packagePath -Force | Out-Null }
                Get-ChildItem -LiteralPath $staging -Force | Copy-Item -Destination $packagePath -Recurse -Force -ErrorAction Stop
            } 'Copying the package into your library'
        } catch {
            # put things back as they were
            Remove-Item -LiteralPath $packagePath -Recurse -Force -ErrorAction SilentlyContinue
            if ($oldAside) {
                try { MPL-Retry { Rename-Item -LiteralPath $oldAside -NewName (Split-Path -Leaf $packagePath) -ErrorAction Stop } 'Putting the old package back' }
                catch { MPL-Warn "The old package is kept as $oldAside" }
            }
            throw
        }
        if ($oldAside) {
            try { MPL-Retry { Remove-Item -LiteralPath $oldAside -Recurse -Force -ErrorAction Stop } 'Removing the old package' }
            catch { MPL-Log "Couldn't remove $oldAside yet (it's ignored by the launcher; delete it any time)." }
        }
    } finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $packagePath
}

# Scripts in Moho's scripts folder (put there by Moho's own Scripts > Install Script, or by hand)
# that the launcher doesn't know yet: not installed by the launcher, not in the library,
# and not on the "leave these alone" list.
function MPL-FindMohoInstalled($s) {
    $scripts = MPL-ScriptsFolder $s
    $rec = MPL-LoadRecord
    if ($rec.Broken -or -not (MPL-Exists $s.MasterFolder)) { return @() }

    $inLibrary = @{}                       # package keys and every .lua name in the library
    foreach ($entry in @(Get-ChildItem -LiteralPath $s.MasterFolder -Directory) + @(Get-ChildItem -LiteralPath $s.MasterFolder -File -Filter '*.lua')) {
        $inLibrary[(MPL-Key $entry.Name)] = $true
        if ($entry.PSIsContainer) {
            Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Filter '*.lua' -ErrorAction SilentlyContinue |
                ForEach-Object { $inLibrary[$_.BaseName.ToLower()] = $true }
        }
    }
    $leaveAlone = @{}
    foreach ($r in (MPL-Flatten $s.LeaveAlone)) { $leaveAlone[$r.ToLower()] = $true }

    $found = @()
    foreach ($kind in @('tool', 'button', 'menu', 'layer')) {
        $dir = Join-Path $scripts $kind
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.lua')) {
            $rel = $file.FullName.Substring($scripts.Length).TrimStart('\', '/')
            if ($file.Name.StartsWith('_')) { continue }
            if ($rec.Files.ContainsKey($rel.ToLower())) { continue }
            if ($inLibrary.ContainsKey($file.BaseName.ToLower())) { continue }
            if ($leaveAlone.ContainsKey($rel.ToLower())) { continue }
            $found += [pscustomobject]@{ Name = $file.BaseName; File = $file; Rel = $rel }
        }
    }
    return @($found | Sort-Object Name)
}

# Add those scripts to the library, ticked, in the Unsorted column. Nothing changes in Moho:
# they're already there and stay there; the launcher just knows about them now.
# Returns what was added: @{ Key; Name; Rel; Package }.
function MPL-AddMohoInstalled($s, $found) {
    $scripts = MPL-ScriptsFolder $s
    $added = @()
    foreach ($script in $found) {
        $files = @(@{ Src = $script.File.FullName; Rel = $script.Rel })
        $relDir = Split-Path -Parent $script.Rel
        foreach ($icon in (MPL-IconFiles $script.File.DirectoryName $script.Name)) {
            $files += @{ Src = $icon.FullName; Rel = (Join-Path $relDir $icon.Name) }
        }
        foreach ($resourceName in @($script.Name, $script.Name.ToLower())) {
            $resources = Join-Path (Join-Path $scripts 'ScriptResources') $resourceName
            if (-not (Test-Path -LiteralPath $resources)) { continue }
            foreach ($r in (Get-ChildItem -LiteralPath $resources -Recurse -File)) {
                $files += @{ Src = $r.FullName; Rel = $r.FullName.Substring($scripts.Length).TrimStart('\', '/') }
            }
            break
        }
        $name = MPL-SuggestName $script.Name
        $key = $script.Name.ToLower()
        $package = Join-Path $s.MasterFolder ($script.Name + $MPL.Suffix)
        try {
            [void](MPL-WritePackage $s $package $files 'Unsorted' $name)
            $inPackage = @($files | ForEach-Object { @{ Src = (Join-Path $package $_.Rel); Rel = $_.Rel } })
            MPL-Adopt $s $name $inPackage $key
            $added += [pscustomobject]@{ Key = $key; Name = $name; Rel = $script.Rel; Package = $package }
            MPL-Log "Added '$name' (installed through Moho) to the library."
        } catch {
            MPL-Warn "Couldn't add '$($script.Name)' to your library: $($_.Exception.Message)"
        }
    }
    # ticked, so nothing leaves Moho at the next launch
    if ($added.Count -gt 0) {
        $settings = MPL-LoadSettings
        $ticked = New-Object System.Collections.Generic.List[string]
        foreach ($k in $settings.Selected) { $ticked.Add($k) }
        foreach ($a in $added) { if (-not $ticked.Contains($a.Key)) { $ticked.Add($a.Key) } }
        $settings.Selected = $ticked.ToArray()
        MPL-SaveSettings $settings
    }
    return $added
}

# "Not these": undo adding them. The launcher lets go of the files (they stay in Moho, untouched),
# removes the library copies it just made, and never asks about them again.
function MPL-LeaveAlone($s, $added) {
    $rec = MPL-LoadRecord
    $settings = MPL-LoadSettings
    $leaveAlone = New-Object System.Collections.Generic.List[string]
    foreach ($r in (MPL-Flatten $settings.LeaveAlone)) { $leaveAlone.Add($r) }
    $ticked = New-Object System.Collections.Generic.List[string]
    foreach ($k in $settings.Selected) { $ticked.Add($k) }

    foreach ($a in $added) {
        foreach ($k in @($rec.Files.Keys)) {
            if ($rec.Files[$k].Key -eq $a.Key) { $rec.Files.Remove($k) }
        }
        if (Test-Path -LiteralPath $a.Package) { Remove-Item -LiteralPath $a.Package -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not $leaveAlone.Contains($a.Rel.ToLower())) { $leaveAlone.Add($a.Rel.ToLower()) }
        [void]$ticked.Remove($a.Key)
        MPL-Log "Left alone: '$($a.Name)' stays in Moho; the launcher won't manage it."
    }
    MPL-SaveRecord $rec
    $settings.LeaveAlone = $leaveAlone.ToArray()
    $settings.Selected = $ticked.ToArray()
    MPL-SaveSettings $settings
}


# ==========================================================================
#  Tools-panel groups  (scripts\tool\_tool_list.txt)
# ==========================================================================
#  toolbar.json lists which group each add-on tool sits in, in order
#  (edited with Sort toolbar...). The launcher writes those tools into
#  Moho's tool list inside marked blocks, so they can be taken out exactly.

function MPL-LoadToolbarMap {
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $MPL.Toolbar)) { return $map }
    try {
        $json = MPL-ReadJson $MPL.Toolbar
        # MPL-Flatten already returns a plain list of names. (Wrapping it in @() nested the list,
        # so a group with two or more tools matched none of them: issue #3.)
        foreach ($g in $json.Groups) { $map[[string]$g.Name] = MPL-Flatten $g.Tools }

        # A tool can sit in one group only. If an older save put it in several, the last one wins
        # (that's the one Sort toolbar shows).
        $finalGroup = @{}
        foreach ($group in $map.Keys) { foreach ($tool in $map[$group]) { $finalGroup[$tool.ToLower()] = $group } }
        foreach ($group in @($map.Keys)) {
            $map[$group] = [string[]]@($map[$group] | Where-Object { $finalGroup[$_.ToLower()] -eq $group } | Select-Object -Unique)
        }
    } catch {
        MPL-Warn "toolbar.json could not be read: tools stay in Moho's Other group."
    }
    return $map
}

function MPL-SaveToolbarMap($map) {
    MPL-EnsureFolderOf $MPL.Toolbar
    $groups = @()
    foreach ($name in $map.Keys) { $groups += [pscustomobject]@{ Name = $name; Tools = @($map[$name]) } }
    $out = [pscustomobject]@{ Note = 'Tools-panel groups for add-on tools. Edit with Sort toolbar.'; Groups = $groups }
    MPL-WriteText $MPL.Toolbar ($out | ConvertTo-Json -Depth 5)
}

# A group name Moho's list can hold: letters, digits, - and _ only.
# (A quote, = or bracket would break the line Moho reads.)
function MPL-GroupName([string]$name) {
    $clean = ($name.Trim() -replace '[^A-Za-z0-9_-]+', '-').Trim('-')
    return $clean
}

# The group names in a tool list
function MPL-ListGroups([string[]]$lines) {
    $out = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*group\s+MOHO\.Localize\("/Tools/Group/[^=]*=([^"]*)"\)') { $out += $Matches[1] }
    }
    return $out
}

# 'tool' if the script works on the canvas (it handles mouse clicks), otherwise 'button'
function MPL-ToolKind([string]$path) {
    if (Select-String -LiteralPath $path -Pattern 'OnMouseDown' -Quiet) { return 'tool' }
    return 'button'
}

# A tool list without the lines the launcher added:
#  - the lines listed in the record (ToolListAdded), and the blank line before a group it added
#  - blocks between the 1.0.0 markers  /* Moho Power Launcher: begin */ ... end */
function MPL-StripOurs([string[]]$lines, $rec) {
    $added = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($rec) { foreach ($line in $rec.ToolListAdded) { [void]$added.Add($line) } }

    $out = New-Object System.Collections.Generic.List[string]
    $insideMarkers = $false
    foreach ($line in $lines) {
        if ($line.Trim() -eq $MPL.TBBegin) { $insideMarkers = $true;  continue }
        if ($line.Trim() -eq $MPL.TBEnd)   { $insideMarkers = $false; continue }
        if ($insideMarkers) { continue }
        if ($added.Contains($line)) {
            $isGroup = $line -match '^\s*group\s'
            if ($isGroup -and $out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
            continue
        }
        $out.Add($line)
    }
    return ,($out.ToArray())
}

# Is the tool list the launcher's own copy, unchanged since it wrote it? Only then may it delete it.
function MPL-ToolListIsOurs($rec, [string]$listPath) {
    if (-not $rec.ToolListCreated) { return $false }
    if (-not (Test-Path -LiteralPath $listPath)) { return $true }
    if (-not $rec.ToolListHash) { return $true }                # record from before the hash was kept
    return ((MPL-Hash $listPath) -eq $rec.ToolListHash)
}

# Rebuild scripts\tool\_tool_list.txt: your own list (or Moho's built-in one) plus the
# add-on tools in their groups. Lines are written exactly the way Moho's own list writes them
# (no comment markers): into the end of a group Moho already has, or as a new group at the end
# of the list after a blank line. Every added line is kept in the record so it can be taken out
# exactly. Your own lines are never changed.
function MPL-ToolbarApply($s) {
    MPL-UseShared $s.ContentFolder
    $toolDir = Join-Path (MPL-ScriptsFolder $s) 'tool'
    $listPath = Join-Path $toolDir '_tool_list.txt'
    $rec = MPL-LoadRecord

    # --- the starting list
    if (Test-Path -LiteralPath $listPath) {
        $ours = MPL-ToolListIsOurs $rec $listPath
        if ($rec.ToolListCreated -and -not $ours) {
            MPL-Log "You edited the tool list the launcher made, so it's yours now: it won't be deleted."
        }
        $created = $ours
        $format = MPL-ReadLines $listPath
        $baseLines = MPL-StripOurs $format.Lines $rec
    } else {
        $builtIn = MPL-BuiltInToolList $s
        if (-not $builtIn) { return "Toolbar: Moho's tool list not found - add-on tools stay in Other." }
        $created = $true
        $format = MPL-ReadLines $builtIn
        $baseLines = $format.Lines
    }

    # --- add-on tools: .lua files in scripts\tool that the list doesn't already name
    $listed = @{}
    foreach ($line in $baseLines) {
        if ($line -match '^\s*(tool|button)\s+(\S+)') { $listed[$Matches[2].ToLower()] = $true }
    }
    $addOns = @{}
    if (Test-Path -LiteralPath $toolDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $toolDir -Filter '*.lua' -File)) {
            $k = $f.BaseName.ToLower()
            if (-not $listed.ContainsKey($k)) { $addOns[$k] = $f }
        }
    }

    # --- which group each one goes in: toolbar.json first, then AutoGroups by name prefix
    $map = MPL-LoadToolbarMap
    $placed = @{}
    $groups = [ordered]@{}
    function Add-ToGroup([string]$group, $file) {
        $name = MPL-GroupName $group                 # a name Moho's list can hold
        if (-not $name) { $name = 'AddOns' }
        if (-not $groups.Contains($name)) { $groups[$name] = New-Object System.Collections.Generic.List[object] }
        $groups[$name].Add($file)
        $placed[$file.BaseName.ToLower()] = $true
    }
    foreach ($group in $map.Keys) {
        foreach ($tool in $map[$group]) {
            $k = $tool.ToLower()
            if ($addOns.ContainsKey($k) -and -not $placed.ContainsKey($k)) { Add-ToGroup $group $addOns[$k] }
        }
    }
    foreach ($prefix in $s.AutoGroups.Keys) {
        foreach ($k in ($addOns.Keys | Sort-Object)) {
            if (-not $placed.ContainsKey($k) -and $k.StartsWith($prefix.ToLower())) {
                Add-ToGroup ([string]$s.AutoGroups[$prefix]) $addOns[$k]
            }
        }
    }

    # --- add the lines
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $baseLines) { $lines.Add($line) }
    $existingGroups = MPL-ListGroups $baseLines
    $added = New-Object System.Collections.Generic.List[string]
    $count = 0
    $newGroups = @()
    foreach ($group in $groups.Keys) {
        $entries = @($groups[$group] | ForEach-Object { "$(MPL-ToolKind $_.FullName)`t$($_.BaseName)`t..." })
        $count += $entries.Count
        foreach ($e in $entries) { $added.Add($e) }

        if ($existingGroups -contains $group) {
            # at the end of that group's tools: before the next group, and before any blank lines
            $start = -1
            $groupPattern = '^\s*group\s+MOHO\.Localize\("/Tools/Group/[^=]*=' + [regex]::Escape($group) + '"\)'
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $groupPattern) { $start = $i; break }
            }
            $end = $lines.Count
            for ($i = $start + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*group\s') { $end = $i; break }
            }
            while ($end - 1 -gt $start -and $lines[$end - 1].Trim() -eq '') { $end-- }
            foreach ($e in $entries) { $lines.Insert($end, $e); $end++ }
        } else {
            # a new group at the end, after a blank line - the same way Moho's list does it
            $header = 'group MOHO.Localize("/Tools/Group/' + $group + '=' + $group + '")'
            $added.Add($header)
            $lines.Add('')
            $lines.Add($header)
            foreach ($e in $entries) { $lines.Add($e) }
            $newGroups += $group
        }
    }

    # --- nothing to add, and the list is only the launcher's copy: delete it, so Moho uses its own again
    if ($count -eq 0 -and $created) {
        if (Test-Path -LiteralPath $listPath) { [void](MPL-RemoveWithRetry $listPath) }
        if ($rec.Dirs.Contains('tool') -and (MPL-RemoveIfEmpty $toolDir)) { [void]$rec.Dirs.Remove('tool') }
        $rec.ToolListCreated = $false
        $rec.ToolListHash = ''
        $rec.ToolListAdded.Clear()
        MPL-SaveRecord $rec
        return 'Toolbar: no add-on tools to sort.'
    }

    if (-not (Test-Path -LiteralPath $toolDir)) { New-Item -ItemType Directory -Path $toolDir -Force | Out-Null }
    MPL-WriteLines $listPath $lines $format
    $rec.ToolListCreated = $created
    $rec.ToolListHash = ''
    if ($created) { $rec.ToolListHash = MPL-Hash $listPath }
    $rec.ToolListAdded.Clear()
    foreach ($a in $added) { $rec.ToolListAdded.Add($a) }
    MPL-SaveRecord $rec

    if ($newGroups.Count -gt 0) { MPL-Log ("Toolbar: new groups written: " + ($newGroups -join ', ')) }
    $leftInOther = @($addOns.Keys | Where-Object { -not $placed.ContainsKey($_) }).Count
    return "Toolbar: $count add-on tools in $($groups.Count) groups; $leftInOther left in Other."
}

# Undo the toolbar changes: delete the list if it's the launcher's own unchanged copy,
# otherwise take out just the lines the launcher added.
function MPL-ToolbarRestore($s, $rec) {
    $listPath = Join-Path (Join-Path (MPL-ScriptsFolder $s) 'tool') '_tool_list.txt'
    if (Test-Path -LiteralPath $listPath) {
        if (MPL-ToolListIsOurs $rec $listPath) {
            [void](MPL-RemoveWithRetry $listPath)
        } else {
            $format = MPL-ReadLines $listPath
            MPL-WriteLines $listPath (MPL-StripOurs $format.Lines $rec) $format
        }
    }
    $rec.ToolListCreated = $false
    $rec.ToolListHash = ''
    $rec.ToolListAdded.Clear()
}


# ==========================================================================
#  Only one launcher at a time
# ==========================================================================

# True while a launcher window is open (used by Setup)
function MPL-LauncherRunning {
    $mutex = $null
    if ([System.Threading.Mutex]::TryOpenExisting($MPL.MutexName, [ref]$mutex)) {
        $mutex.Dispose()
        return $true
    }
    return $false
}


# ==========================================================================
#  Search  (Doug's build only, for now: issue #9)
# ==========================================================================
#  Each script gets one line of lower-case text to search: its launcher name, column, folder
#  name, file names, toolbar group, and the name and description Moho shows for it (read from
#  the script's UILabel and Description). Reading every .lua file is the slow part, so what
#  each file gave is kept in search-cache.json and read again only when the file changes.

# The name and description a Moho script gives itself
function MPL-ScriptDescription([string]$path) {
    $out = @()
    try { $text = [System.IO.File]::ReadAllText($path) } catch { return '' }
    $found = [regex]::Matches($text, ':(?:Description|UILabel)\s*\(\s*\)\s*return\s+([^\r\n]+)')
    foreach ($m in $found) {
        foreach ($q in [regex]::Matches($m.Groups[1].Value, '"((?:[^"\\]|\\.)*)"')) {
            $v = $q.Groups[1].Value
            if ($v -match '^/[^=]*=(.*)$') { $v = $Matches[1] }      # MOHO.Localize("/Scripts/.../Description=Text")
            if ($v.Trim()) { $out += $v.Trim() }
        }
    }
    return (($out | Select-Object -Unique) -join ' ')
}

# Key -> searchable text, for every item in the library
function MPL-SearchIndex($s, $items) {
    $cacheFile = Join-Path $MPL.DataDir 'search-cache.json'
    $old = @{}
    if (Test-Path -LiteralPath $cacheFile) {
        try { foreach ($p in (MPL-ReadJson $cacheFile).PSObject.Properties) { $old[$p.Name] = $p.Value } } catch {}
    }
    $toolGroup = @{}
    try {
        $map = MPL-LoadToolbarMap
        foreach ($g in $map.Keys) { foreach ($t in $map[$g]) { $toolGroup[$t.ToLower()] = $g } }
    } catch {}

    $new = @{}
    $changed = $false
    $index = @{}
    foreach ($item in $items) {
        $words = New-Object System.Collections.Generic.List[string]
        $words.Add([string]$item.Name); $words.Add([string]$item.Group); $words.Add((Split-Path $item.Path -Leaf))
        $files = @()
        try {
            if ($item.Loose) { $files = @(Get-Item -LiteralPath $item.Path) }
            else { $files = @(Get-ChildItem -LiteralPath $item.Path -Recurse -File -Force -ErrorAction SilentlyContinue) }
        } catch {}
        foreach ($file in $files) {
            if ($file.Name -eq $MPL.Label) { continue }
            $words.Add($file.Name)
            if ($file.Extension -ne '.lua') { continue }
            $stem = $file.BaseName.ToLower()
            if ($toolGroup.ContainsKey($stem)) { $words.Add($toolGroup[$stem]) }
            $stamp = "$($file.Length)|$($file.LastWriteTimeUtc.Ticks)"
            $cached = $old[$file.FullName]
            if ($cached -and $cached.Stamp -eq $stamp) {
                $text = [string]$cached.Text
            } else {
                $text = MPL-ScriptDescription $file.FullName
                $changed = $true
            }
            $new[$file.FullName] = [pscustomobject]@{ Stamp = $stamp; Text = $text }
            if ($text) { $words.Add($text) }
        }
        $index[$item.Key] = ($words -join ' ').ToLower()
    }
    if ($changed -or $old.Count -ne $new.Count) {
        try { MPL-EnsureDataDir; MPL-WriteText $cacheFile ($new | ConvertTo-Json -Depth 3 -Compress) } catch {}
    }
    return $index
}

# What was typed, as @{ Want; Not }: words must all appear (any order, part words count);
# -word hides matches; "two words" matches the phrase. Capital letters don't matter.
function MPL-ParseSearch([string]$typed) {
    $want = @(); $not = @()
    foreach ($m in [regex]::Matches(([string]$typed).ToLower(), '(-?)"([^"]*)"?|(\S+)')) {
        if ($m.Groups[3].Success) {
            $t = $m.Groups[3].Value
            if ($t.Length -gt 1 -and $t.StartsWith('-')) { $not += $t.Substring(1) } elseif ($t -ne '-') { $want += $t }
        } else {
            $t = $m.Groups[2].Value.Trim()
            if (-not $t) { continue }
            if ($m.Groups[1].Value -eq '-') { $not += $t } else { $want += $t }
        }
    }
    return @{ Want = $want; Not = $not }
}

function MPL-SearchMatch([string]$text, $search) {
    foreach ($w in $search.Want) { if (-not $text.Contains($w)) { return $false } }
    foreach ($w in $search.Not)  { if ($text.Contains($w)) { return $false } }
    return $true
}
