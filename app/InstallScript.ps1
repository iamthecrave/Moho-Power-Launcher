# ==========================================================================
#  Moho Power Launcher - Install script
#  Adds a script you downloaded (.zip or .lua) to your script library, so the
#  launcher lists it. You pick the file first, then its column and name.
#  It makes one package folder in the library, labels it (launcher.txt), and can
#  tick it for the next launch. A download of a script you already have replaces
#  the old package (keeping its column and name).
#
#  Scripts you install with Moho's own Scripts > Install Script don't need this:
#  the launcher adds those by itself when it opens.
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
$Columns = @($MPL.FixedColumns | Where-Object { $_ -ne 'Unsorted' }) + @($S.MyColumns) + @('Unsorted')
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
#  The download (.zip or .lua)
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
$defaultName = MPL-SuggestName $baseName
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
            foreach ($icon in (MPL-IconFiles $lua.DirectoryName $lua.BaseName)) {
                $files += @{ Src = $icon.FullName; Rel = (Join-Path $targetDir $icon.Name) }
            }
        }
    }
    [void](MPL-WritePackage $S $packagePath $files $column $name)
    if ($tickBox.Checked) { Tick-ForNextLaunch $key }
} catch {
    MPL-Log ("Install script failed: " + $_.Exception.Message)
    MPL-SaveLog
    Say ("Couldn't finish: " + $_.Exception.Message + "`n`nYour library was not changed. If Dropbox is busy syncing, wait a moment and try again.") 'Error'
    return
} finally {
    Remove-TempFolder
}

$message = "Installed '$name' in the $column column."
if ($tickBox.Checked) { $message += "`n`nIt's ticked: click Launch Moho and it's there." }
else                  { $message += "`n`nTick it in the launcher when you want it." }
Say $message
