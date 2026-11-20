# ==========================================================================
#  Moho Power Launcher - Install script
#  Adds a script to your script library, so the launcher lists it:
#   A. a script you already installed with Moho's own Scripts > Install Script, or
#   B. a download (.zip or .lua).
#  It makes one package folder per script in the library, labels it with its
#  column and name (launcher.txt), and can tick it for the next launch.
#  A download of a script you already have replaces the old package.
#
#  Copyright (C) 2026 Cheesoid: Doug Craven and Claude (an AI model by Anthropic)
#  PolyForm Noncommercial License 1.0.0 - see LICENSE
# ==========================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MPL-Common.ps1')
$Icon = $null
try { $Icon = New-Object System.Drawing.Icon (Join-Path $PSScriptRoot 'MohoPowerLauncher.ico') } catch {}

$S = MPL-LoadSettings
$Scripts = MPL-ScriptsFolder $S
$Library = $S.MasterFolder
$Title   = "$($MPL.Name) - Install script"

function Say([string]$message, [string]$icon = 'Information') {
    [void][System.Windows.Forms.MessageBox]::Show($message, $Title, 'OK', $icon)
}
function Ask([string]$question) {
    return [System.Windows.Forms.MessageBox]::Show($question, $Title, 'YesNo', 'Question')
}

if (-not $Library) { Say 'Set your script library in Settings... first.' 'Warning'; return }
if (-not (MPL-Exists $Library)) { New-Item -ItemType Directory -Path $Library -Force | Out-Null }


# ==========================================================================
#  Shared helpers
# ==========================================================================

# Suggested display name: words capitalised, the maker's initials as a tag
#   mr_key_motion  ->  Key Motion (MR)
function Suggest-Name([string]$fileName) {
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

function Tick-ForNextLaunch([string]$key) {
    $settings = MPL-LoadSettings
    $ticked = @($settings.Selected)
    if ($ticked -notcontains $key) { $ticked += $key }
    $settings.Selected = $ticked
    MPL-SaveSettings $settings
}

# Column and name must be filled in and can't hold '|' (the label's separator)
function Test-Label([string]$column, [string]$name) {
    if (-not $column -or -not $name) { Say 'Column and name cannot be empty.' 'Error'; return $false }
    if ($column.Contains('|') -or $name.Contains('|')) { Say "Column and name can't contain '|'." 'Error'; return $false }
    return $true
}

# A script's icons sit next to it: name.png, name@2x.png, name_large.png, name_cursor.png
function Get-IconFiles([string]$folder, [string]$scriptName) {
    $icons = @()
    foreach ($suffix in $MPL.IconSuffixes) {
        $path = Join-Path $folder ($scriptName + $suffix)
        if (Test-Path -LiteralPath $path) { $icons += Get-Item -LiteralPath $path }
    }
    return $icons
}

# Build a package safely: copy into a hidden folder first (names starting with _ are ignored
# by the launcher), and only when that worked, swap it in for the old package.
# $files: @{ Src; Rel } list. Returns the package folder.
function Write-Package([string]$packagePath, $files, [string]$column, [string]$name) {
    $staging = Join-Path $Library ('_installing_' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($f in $files) {
            $dest = Join-Path $staging $f.Rel
            $parent = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $f.Src -Destination $dest -Force
        }
        MPL-WriteLabel $staging $column $name
    } catch {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    # Swap: move the old package aside (a rename fails cleanly if something has it open),
    # put the new one in its place, then delete the old one.
    $oldAside = $null
    if (Test-Path -LiteralPath $packagePath) {
        $oldAside = Join-Path $Library ('_replaced_' + [guid]::NewGuid().ToString('N'))
        try {
            Rename-Item -LiteralPath $packagePath -NewName (Split-Path -Leaf $oldAside)
        } catch {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
            throw "The old package is in use (is a file from it open?): $($_.Exception.Message)"
        }
    }
    Rename-Item -LiteralPath $staging -NewName (Split-Path -Leaf $packagePath)
    if ($oldAside) { Remove-Item -LiteralPath $oldAside -Recurse -Force -ErrorAction SilentlyContinue }
    return $packagePath
}

function Lbl([string]$text, [int]$top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(20, $top)
    return $label
}

function New-Form([string]$text, [int]$height) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $text
    $f.ClientSize = New-Object System.Drawing.Size(470, $height)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    if ($Icon) { $f.Icon = $Icon }
    return $f
}

function New-ColumnBox([int]$top, [string]$value) {
    $box = New-Object System.Windows.Forms.ComboBox          # editable: type a new name for a new column
    $box.Location = New-Object System.Drawing.Point(20, $top)
    $box.Size = New-Object System.Drawing.Size(430, 28)
    foreach ($c in $Columns) { [void]$box.Items.Add($c) }
    $box.Text = $value
    return $box
}

function New-TickBox([int]$top) {
    $tick = New-Object System.Windows.Forms.CheckBox
    $tick.Text = 'Tick it in the launcher for the next launch'
    $tick.AutoSize = $true
    $tick.Checked = $true
    $tick.Location = New-Object System.Drawing.Point(20, $top)
    return $tick
}

function New-DialogButton([string]$text, [int]$left, [int]$top, [string]$result, [int]$width = 140) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size($width, 32)
    $b.Location = New-Object System.Drawing.Point($left, $top)
    $b.DialogResult = $result
    return $b
}


# ==========================================================================
#  What the library has, and the columns it uses
# ==========================================================================

$inLibrary = @{}                 # package keys and every .lua name in the library
$Columns = @($S.Columns)
foreach ($entry in @(Get-ChildItem -LiteralPath $Library -Directory) + @(Get-ChildItem -LiteralPath $Library -File -Filter '*.lua')) {
    $inLibrary[(MPL-Key $entry.Name)] = $true
    if (-not $entry.PSIsContainer) { continue }
    Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Filter '*.lua' -ErrorAction SilentlyContinue |
        ForEach-Object { $inLibrary[$_.BaseName.ToLower()] = $true }
    $label = MPL-ReadLabel $entry.FullName
    if ($label -and $label.Column -and $Columns -notcontains $label.Column) { $Columns += $label.Column }
}
if ($Columns.Count -eq 0) { $Columns = @('Unsorted') }


# ==========================================================================
#  Scripts in Moho's scripts folder that aren't in the library yet
# ==========================================================================

$record = MPL-LoadRecord
$Candidates = @()
foreach ($kind in @('tool', 'button', 'menu', 'layer')) {
    $dir = Join-Path $Scripts $kind
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.lua')) {
        $rel = $file.FullName.Substring($Scripts.Length).TrimStart('\', '/')
        if ($record.Files.ContainsKey($rel.ToLower())) { continue }        # put there by the launcher
        if ($inLibrary.ContainsKey($file.BaseName.ToLower())) { continue } # already in the library
        $Candidates += [pscustomobject]@{ Kind = $kind; Name = $file.BaseName; File = $file; Rel = $rel }
    }
}
$Candidates = @($Candidates | Sort-Object Name)

$Mode = 'existing'
if ($Candidates.Count -eq 0) {
    if ((Ask "Every script in Moho's scripts folder is already in your library.`n`nInstall a script you downloaded?") -ne 'Yes') { return }
    $Mode = 'download'
}


# ==========================================================================
#  A. A script already in Moho's scripts folder
# ==========================================================================

if ($Mode -eq 'existing') {
    $form = New-Form $Title 330

    $scriptList = New-Object System.Windows.Forms.ComboBox
    $scriptList.DropDownStyle = 'DropDownList'
    $scriptList.Location = New-Object System.Drawing.Point(20, 42)
    $scriptList.Size = New-Object System.Drawing.Size(430, 28)
    foreach ($c in $Candidates) { [void]$scriptList.Items.Add("$($c.Name)   [$($c.Rel)]") }

    $columnBox = New-ColumnBox 110 $Columns[0]
    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Location = New-Object System.Drawing.Point(20, 178)
    $nameBox.Size = New-Object System.Drawing.Size(430, 28)
    $tickBox = New-TickBox 222

    $scriptList.Add_SelectedIndexChanged({ $nameBox.Text = Suggest-Name $Candidates[$scriptList.SelectedIndex].Name })
    $scriptList.SelectedIndex = 0

    $fromDownload = New-DialogButton 'From a download...' 20  276 'Retry'
    $addButton    = New-DialogButton 'Add to library'     170 276 'OK'
    $cancelButton = New-DialogButton 'Cancel'             320 276 'Cancel' 130
    $form.Controls.AddRange(@(
        (Lbl "A script in Moho's scripts folder, not in your library yet:" 18), $scriptList,
        (Lbl 'Launcher column:' 86), $columnBox,
        (Lbl 'Name shown in the launcher:' 154), $nameBox,
        $tickBox, $fromDownload, $addButton, $cancelButton))
    $form.AcceptButton = $addButton
    $form.CancelButton = $cancelButton

    $answer = $form.ShowDialog()
    if ($answer -eq 'Retry') {
        $Mode = 'download'
    } elseif ($answer -ne 'OK') {
        return
    } else {
        $chosen = $Candidates[$scriptList.SelectedIndex]
        $column = $columnBox.Text.Trim()
        $name = $nameBox.Text.Trim()
        if (-not (Test-Label $column $name)) { return }

        $packagePath = Join-Path $Library ($chosen.Name + $MPL.Suffix)
        if ((Test-Path -LiteralPath $packagePath) -and (Ask "A package for '$($chosen.Name)' already exists.`nReplace it?") -ne 'Yes') { return }

        # the script where it sits (keeps menu subfolders), its icons, and its own resources folder
        $files = @(@{ Src = $chosen.File.FullName; Rel = $chosen.Rel })
        $relDir = Split-Path -Parent $chosen.Rel
        foreach ($icon in (Get-IconFiles $chosen.File.DirectoryName $chosen.Name)) {
            $files += @{ Src = $icon.FullName; Rel = (Join-Path $relDir $icon.Name) }
        }
        foreach ($resourceName in @($chosen.Name, $chosen.Name.ToLower())) {
            $resources = Join-Path (Join-Path $Scripts 'ScriptResources') $resourceName
            if (-not (Test-Path -LiteralPath $resources)) { continue }
            foreach ($r in (Get-ChildItem -LiteralPath $resources -Recurse -File)) {
                $files += @{ Src = $r.FullName; Rel = $r.FullName.Substring($Scripts.Length).TrimStart('\', '/') }
            }
            break
        }

        try {
            [void](Write-Package $packagePath $files $column $name)
            # the copies in Moho's scripts folder are now the launcher's to manage (identical files only)
            $inPackage = @($files | ForEach-Object { @{ Src = (Join-Path $packagePath $_.Rel); Rel = $_.Rel } })
            MPL-Adopt $S $name $inPackage
            if ($tickBox.Checked) { Tick-ForNextLaunch $chosen.Name.ToLower() }
        } catch {
            Say ("Couldn't finish: " + $_.Exception.Message) 'Error'
            return
        }

        $message = "Added '$name' to the $column column.`n`nIt's in your library now, so the launcher installs it when it's ticked and removes it when it isn't."
        if (-not $tickBox.Checked) { $message += "`n`nIt's not ticked: next launch takes it out of Moho until you tick it." }
        Say $message
        return
    }
}


# ==========================================================================
#  B. A download (.zip or .lua)
# ==========================================================================

$picker = New-Object System.Windows.Forms.OpenFileDialog
$picker.Title  = 'Find the Moho script you downloaded'
$picker.Filter = 'Moho script downloads (*.zip;*.lua)|*.zip;*.lua|All files (*.*)|*.*'
$downloads = Join-Path $env:USERPROFILE 'Downloads'
if (Test-Path -LiteralPath $downloads) { $picker.InitialDirectory = $downloads }
if ($picker.ShowDialog() -ne 'OK') { return }
$download = $picker.FileName
$isZip = [IO.Path]::GetExtension($download) -ieq '.zip'

$TempFolder = $null
function Remove-TempFolder {
    if ($TempFolder) { Remove-Item -LiteralPath $TempFolder -Recurse -Force -ErrorAction SilentlyContinue }
}

# What's in it: a ready-made package ($PackageFiles), or bare .lua files ($LooseScripts)
$PackageFiles = @()
$LooseScripts = @()
try {
    if ($isZip) {
        $TempFolder = Join-Path $env:TEMP ('MPL_' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -LiteralPath $download -DestinationPath $TempFolder -Force
        $root = MPL-PackageRoot $TempFolder
        if ($root) {
            $base = $root.TrimEnd('\', '/')
            foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object { $_.Name -ne $MPL.Label })) {
                $PackageFiles += @{ Src = $f.FullName; Rel = $f.FullName.Substring($base.Length).TrimStart('\', '/') }
            }
        } else {
            $LooseScripts = @(Get-ChildItem -LiteralPath $TempFolder -Recurse -File -Filter '*.lua')
        }
    } else {
        $LooseScripts = @(Get-Item -LiteralPath $download)
    }
    if ($PackageFiles.Count -eq 0 -and $LooseScripts.Count -eq 0) {
        throw "No Moho script (.lua) found in $([IO.Path]::GetFileName($download))."
    }
} catch {
    Remove-TempFolder
    Say ("Couldn't read the download: " + $_.Exception.Message) 'Error'
    return
}

# Package name from the file name, without "moho-script_", the install-command suffix, or a browser's " (1)"
$baseName = [IO.Path]::GetFileNameWithoutExtension($download)
$baseName = $baseName -replace '^moho-script_', ''
$baseName = $baseName -replace "$([regex]::Escape($MPL.Suffix))$", ''
$baseName = $baseName -replace '\s*\(\d+\)$', ''
if ($PackageFiles.Count -eq 0 -and $LooseScripts.Count -eq 1) { $baseName = $LooseScripts[0].BaseName }
$key = MPL-Key $baseName
$packagePath = Join-Path $Library ($baseName + $MPL.Suffix)

# Already in the library: this is an update. Keep its column and name as the defaults.
$defaultColumn = $Columns[0]
$defaultName = Suggest-Name $baseName
$existing = @(Get-ChildItem -LiteralPath $Library -Directory | Where-Object { (MPL-Key $_.Name) -eq $key })
if ($existing.Count -gt 0) {
    if ((Ask "'$baseName' is already in your library ($($existing[0].Name)).`n`nReplace it with this download?") -ne 'Yes') {
        Remove-TempFolder
        return
    }
    $packagePath = $existing[0].FullName
    $label = MPL-ReadLabel $packagePath
    if ($label -and $label.Column) { $defaultColumn = $label.Column }
    if ($label -and $label.Name)   { $defaultName = $label.Name }
}

# ---------- the dialog ----------
$form = New-Form "$Title - from a download" 0
if ($PackageFiles.Count -gt 0) { $what = "$($PackageFiles.Count) files, ready-made package" }
else                           { $what = "$($LooseScripts.Count) script file(s), no folders" }
$columnBox = New-ColumnBox 66 $defaultColumn
$nameBox = New-Object System.Windows.Forms.TextBox
$nameBox.Location = New-Object System.Drawing.Point(20, 130)
$nameBox.Size = New-Object System.Drawing.Size(430, 28)
$nameBox.Text = $defaultName
$controls = @(
    (Lbl ("Download: " + [IO.Path]::GetFileName($download) + "   ($what)") 18),
    (Lbl 'Launcher column:' 44), $columnBox,
    (Lbl 'Name shown in the launcher:' 108), $nameBox)

$y = 172
$kindBox = $null
if ($PackageFiles.Count -eq 0) {
    # Bare .lua files: a tool (it handles mouse clicks) goes in the Tools panel, anything else in the Scripts menu
    $looksLikeTool = $false
    foreach ($lua in $LooseScripts) {
        if (Select-String -LiteralPath $lua.FullName -Pattern 'OnMouseDown' -Quiet) { $looksLikeTool = $true }
    }
    $kindBox = New-Object System.Windows.Forms.ComboBox
    $kindBox.DropDownStyle = 'DropDownList'
    $kindBox.Location = New-Object System.Drawing.Point(20, ($y + 22))
    $kindBox.Size = New-Object System.Drawing.Size(430, 28)
    [void]$kindBox.Items.Add('Tools panel (tool folder)')
    [void]$kindBox.Items.Add("Scripts menu (Scripts > $($S.LooseMenuFolder))")
    if ($looksLikeTool) { $kindBox.SelectedIndex = 0 } else { $kindBox.SelectedIndex = 1 }
    $controls += @((Lbl 'Install as:' $y), $kindBox)
    $y += 64
}
$tickBox = New-TickBox $y
$installButton = New-DialogButton 'Install' 170 ($y + 44) 'OK'
$cancelButton  = New-DialogButton 'Cancel'  320 ($y + 44) 'Cancel' 130
$form.ClientSize = New-Object System.Drawing.Size(470, ($y + 92))
$form.Controls.AddRange(@($controls + @($tickBox, $installButton, $cancelButton)))
$form.AcceptButton = $installButton
$form.CancelButton = $cancelButton

if ($form.ShowDialog() -ne 'OK') { Remove-TempFolder; return }
$column = $columnBox.Text.Trim()
$name = $nameBox.Text.Trim()
if (-not (Test-Label $column $name)) { Remove-TempFolder; return }

# ---------- install it ----------
try {
    $files = $PackageFiles
    if ($files.Count -eq 0) {
        $targetDir = Join-Path 'menu' $S.LooseMenuFolder
        if ($kindBox.SelectedIndex -eq 0) { $targetDir = 'tool' }
        foreach ($lua in $LooseScripts) {
            $files += @{ Src = $lua.FullName; Rel = (Join-Path $targetDir $lua.Name) }
            foreach ($icon in (Get-IconFiles $lua.DirectoryName $lua.BaseName)) {
                $files += @{ Src = $icon.FullName; Rel = (Join-Path $targetDir $icon.Name) }
            }
        }
    }
    [void](Write-Package $packagePath $files $column $name)
    if ($tickBox.Checked) { Tick-ForNextLaunch $key }
} catch {
    Say ("Couldn't finish: " + $_.Exception.Message + "`n`nYour library was not changed.") 'Error'
    return
} finally {
    Remove-TempFolder
}

$message = "Installed '$name' in the $column column."
if ($tickBox.Checked) { $message += "`n`nIt's ticked: click Launch Moho and it's there." }
else                  { $message += "`n`nTick it in the launcher when you want it." }
Say $message
