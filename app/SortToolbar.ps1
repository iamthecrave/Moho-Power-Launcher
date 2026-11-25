# ==========================================================================
#  Moho Power Launcher - Sort toolbar
#  Puts add-on tools (from your library and from Moho's scripts folder) into
#  Tools-panel groups: one of Moho's own (Draw, Fill, Bone, Layer, ...) or a
#  new group you name. "(Other)" leaves a tool where Moho puts it anyway.
#
#  Saved in toolbar.json; the launcher applies it every launch. Your own lines
#  in Moho's tool list are never changed - the launcher only adds marked blocks.
#
#  Copyright (C) 2026 Cheesoid: Doug Craven and Claude (an AI model by Anthropic)
#  PolyForm Noncommercial License 1.0.0 - see LICENSE
# ==========================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic          # for InputBox
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MPL-Common.ps1')
$Icon = $null
try { $Icon = New-Object System.Drawing.Icon (Join-Path $PSScriptRoot 'MohoPowerLauncher.ico') } catch {}

$S = MPL-LoadSettings
$Scripts = MPL-ScriptsFolder $S
$OTHER = '(Other)'
$Title = "$($MPL.Name) - Sort toolbar"


# ---------- Moho's own groups and tools ----------
# from your tool list without the launcher's blocks, or Moho's built-in list

$listPath = Join-Path (Join-Path $Scripts 'tool') '_tool_list.txt'
$baseLines = @()
if (Test-Path -LiteralPath $listPath) {
    $baseLines = MPL-StripOurs (MPL-ReadLines $listPath).Lines (MPL-LoadRecord)
} else {
    $builtIn = MPL-BuiltInToolList $S
    if ($builtIn) { $baseLines = (MPL-ReadLines $builtIn).Lines }
}
$mohoTools = @{}
foreach ($line in $baseLines) {
    if ($line -match '^\s*(tool|button)\s+(\S+)') { $mohoTools[$Matches[2].ToLower()] = $true }
}


# ---------- the add-on tools ----------
# in the scripts folder now, and in every library package (ticked or not)

$tools = [ordered]@{}            # lower-case file name -> @{ File; Name; Package; Yours }

# Installed = in Moho's scripts folder right now
$installed = @{}
$installedDir = Join-Path $Scripts 'tool'
if (Test-Path -LiteralPath $installedDir) {
    foreach ($file in (Get-ChildItem -LiteralPath $installedDir -Filter '*.lua' -File)) { $installed[$file.BaseName.ToLower()] = $file }
}

# A readable name: the package's launcher name when the package has just this one tool,
# otherwise the file name with _ as spaces
function Get-ShowName([string]$fileName, $label, [int]$toolsInPackage) {
    if ($label -and $label.Name -and $toolsInPackage -eq 1) { return $label.Name }
    return ($fileName -replace '_', ' ')
}

# Package = the library package's key (what the launcher ticks); '' for your own installed script
function Add-Tool([string]$fileName, [string]$showName, [string]$package) {
    $key = $fileName.ToLower()
    if ($mohoTools.ContainsKey($key) -or $tools.Contains($key)) { return }
    $tools[$key] = @{ File = $fileName; Name = $showName; Package = $package }
}

# every package in the library (ticked or not), then anything installed that isn't in the library
if (MPL-Exists $S.MasterFolder) {
    foreach ($package in (Get-ChildItem -LiteralPath $S.MasterFolder -Directory | Where-Object { -not $_.Name.StartsWith('_') })) {
        $label = MPL-ReadLabel $package.FullName
        $packageKey = MPL-Key $package.Name
        foreach ($toolDir in (Get-ChildItem -LiteralPath $package.FullName -Recurse -Directory -Filter 'tool')) {
            $luaFiles = @(Get-ChildItem -LiteralPath $toolDir.FullName -Filter '*.lua' -File)
            foreach ($lua in $luaFiles) { Add-Tool $lua.BaseName (Get-ShowName $lua.BaseName $label $luaFiles.Count) $packageKey }
        }
    }
}
# installed but not in your library: your own script
foreach ($file in $installed.Values) { Add-Tool $file.BaseName ($file.BaseName -replace '_', ' ') '' }
$ticked = @{}
foreach ($k in $S.Selected) { $ticked[$k] = $true }
if ($tools.Count -eq 0) {
    [void][System.Windows.Forms.MessageBox]::Show("No add-on tools found yet.`n`nInstall a Tools-panel script with Install script..., then sort it here.", $Title)
    return
}


# ---------- groups, and where each tool sits now ----------

$map = MPL-LoadToolbarMap
$script:Groups = @(MPL-ListGroups $baseLines)
foreach ($group in $map.Keys)             { if ($script:Groups -notcontains $group) { $script:Groups += $group } }
foreach ($group in $S.AutoGroups.Values)  { if ($script:Groups -notcontains [string]$group) { $script:Groups += [string]$group } }
$script:Groups += $OTHER

$groupOf = @{}                   # tool -> group in toolbar.json
$placeInGroup = @{}              # tool -> its position there
foreach ($group in $map.Keys) {
    $position = 0
    foreach ($tool in $map[$group]) {
        $groupOf[$tool.ToLower()] = $group
        $placeInGroup[$tool.ToLower()] = $position
        $position++
    }
}


# ---------- the window ----------

$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(660, 560)
if ($Icon) { $form.Icon = $Icon }

$info = New-Object System.Windows.Forms.Label
$info.Text = "Pick a Tools-panel group for each add-on tool. Up / Down sets its place in the group. (Other) = Moho's Other group.`n" +
             "Tick = switched on, the same as ticking it in the launcher. A grey tick is your own script: always on."
$info.Location = New-Object System.Drawing.Point(12, 8)
$info.Size = New-Object System.Drawing.Size(636, 48)
$form.Controls.Add($info)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(12, 60)
$grid.Size = New-Object System.Drawing.Size(530, 448)
$grid.Anchor = 'Top,Bottom,Left,Right'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'

# Columns: 0 on/off tick, 1 name, 2 group; hidden: 3 file name (what gets saved), 4 package key
$tickColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$tickColumn.HeaderText = 'On'
$tickColumn.AutoSizeMode = 'None'
$tickColumn.Width = 40
$tickColumn.ToolTipText = 'Ticked = switched on for the next launch (same as the launcher)'
$toolColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$toolColumn.HeaderText = 'Tool'
$toolColumn.ReadOnly = $true
$toolColumn.FillWeight = 62
$groupColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
$groupColumn.HeaderText = 'Group'
$groupColumn.FillWeight = 38
$groupColumn.FlatStyle = 'Flat'
foreach ($group in $script:Groups) { [void]$groupColumn.Items.Add($group) }
$fileColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$fileColumn.Visible = $false
$packageColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$packageColumn.Visible = $false
[void]$grid.Columns.Add($tickColumn)
[void]$grid.Columns.Add($toolColumn)
[void]$grid.Columns.Add($groupColumn)
[void]$grid.Columns.Add($fileColumn)
[void]$grid.Columns.Add($packageColumn)
$form.Controls.Add($grid)

# A pick in the Group drop-down counts straight away (not only when you leave the cell)
$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) { [void]$grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
})

# One row per tool, sorted by group then by its place in the group
$rows = @()
foreach ($key in $tools.Keys) {
    $group = $groupOf[$key]
    if (-not $group) {
        $group = $OTHER
        foreach ($prefix in $S.AutoGroups.Keys) {
            if ($key.StartsWith($prefix.ToLower())) { $group = [string]$S.AutoGroups[$prefix] }
        }
    }
    if ($script:Groups -notcontains $group) { $group = $OTHER }
    $position = 999
    if ($placeInGroup.ContainsKey($key)) { $position = $placeInGroup[$key] }
    $rows += [pscustomobject]@{
        On       = ((-not $tools[$key].Package) -or $ticked.ContainsKey($tools[$key].Package))
        Name     = $tools[$key].Name
        File     = $tools[$key].File
        Package  = $tools[$key].Package
        Group    = $group
        GroupNo  = [array]::IndexOf($script:Groups, $group)
        Position = $position
    }
}
# Switched-on rows are tinted green, so you can see at a glance what's on
$OnColour  = [System.Drawing.Color]::FromArgb(214, 240, 214)
$OffColour = [System.Drawing.SystemColors]::Window
function Paint-Row($row) {
    if ([bool]$row.Cells[0].Value) { $row.DefaultCellStyle.BackColor = $OnColour }
    else { $row.DefaultCellStyle.BackColor = $OffColour }
}

# One grid row. Hovering a name shows the script's file name. Your own scripts get a grey, fixed tick.
function Add-GridRow([int]$at, [bool]$on, [string]$name, [string]$group, [string]$file, [string]$package) {
    if ($at -lt 0) { $at = $grid.Rows.Add($on, $name, $group, $file, $package) }
    else { $grid.Rows.Insert($at, $on, $name, $group, $file, $package) }
    $row = $grid.Rows[$at]
    $row.Cells[1].ToolTipText = "$file.lua"
    if (-not $package) {
        $row.Cells[0].ReadOnly = $true
        $row.Cells[0].Style.ForeColor = [System.Drawing.SystemColors]::GrayText
        $row.Cells[0].ToolTipText = "Your own script (not in your library): always on. The launcher never removes it."
        $row.Cells[1].Style.ForeColor = [System.Drawing.SystemColors]::GrayText
    }
    Paint-Row $row
    return $at
}
foreach ($row in ($rows | Sort-Object GroupNo, Position, Name)) {
    [void](Add-GridRow -1 $row.On $row.Name $row.Group $row.File $row.Package)
}

# Ticking one tool of a package ticks its other tools too: the launcher switches whole packages
$script:Syncing = $false
$grid.Add_CellValueChanged({
    param($sender, $e)
    if ($script:Syncing -or $e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0) { return }
    $package = [string]$grid.Rows[$e.RowIndex].Cells[4].Value
    if (-not $package) { return }
    $value = [bool]$grid.Rows[$e.RowIndex].Cells[0].Value
    $script:Syncing = $true
    foreach ($row in $grid.Rows) {
        if ([string]$row.Cells[4].Value -eq $package) { $row.Cells[0].Value = $value; Paint-Row $row }
    }
    $script:Syncing = $false
})


# ---------- buttons on the right ----------

function New-SideButton([string]$text, [int]$top) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size(100, 30)
    $b.Location = New-Object System.Drawing.Point(550, $top)
    $b.Anchor = 'Top,Right'
    $form.Controls.Add($b)
    return $b
}

# Move the selected tool past the next visible one (hidden rows are skipped)
function Move-Row([int]$step) {
    if ($grid.SelectedRows.Count -eq 0) { return }
    $from = $grid.SelectedRows[0].Index
    $to = $from + $step
    while ($to -ge 0 -and $to -lt $grid.Rows.Count -and -not $grid.Rows[$to].Visible) { $to += $step }
    if ($to -lt 0 -or $to -ge $grid.Rows.Count) { return }
    $cells = $grid.Rows[$from].Cells
    $values = @([bool]$cells[0].Value, $cells[1].Value, $cells[2].Value, $cells[3].Value, $cells[4].Value)
    $grid.Rows.RemoveAt($from)
    [void](Add-GridRow $to $values[0] $values[1] $values[2] $values[3] $values[4])
    $grid.ClearSelection()
    $grid.Rows[$to].Selected = $true
    $grid.CurrentCell = $grid.Rows[$to].Cells[1]
}

$upButton = New-SideButton 'Up' 60
$upButton.Add_Click({ Move-Row -1 })
$downButton = New-SideButton 'Down' 96
$downButton.Add_Click({ Move-Row 1 })

$newGroupButton = New-SideButton 'New group...' 144
$newGroupButton.Add_Click({
    $typed = [Microsoft.VisualBasic.Interaction]::InputBox('Name for the new Tools-panel group:', 'New group', '')
    if (-not $typed) { return }
    $name = MPL-GroupName $typed                 # letters, digits, - and _ only
    if (-not $name -or $groupColumn.Items.Contains($name)) { return }
    $groupColumn.Items.Insert($groupColumn.Items.Count - 1, $name)       # before (Other)
    $script:Groups = @($script:Groups | Where-Object { $_ -ne $OTHER }) + @($name, $OTHER)
    if ($grid.SelectedRows.Count -gt 0) { $grid.SelectedRows[0].Cells[2].Value = $name }
})

# Rename or delete one of your own groups: the group of the selected tool.
# Moho's own groups (Draw, Bone, Layer...) stay as they are.
$MohoGroups = @(MPL-ListGroups $baseLines)
function Get-SelectedOwnGroup([string]$action) {
    if ($grid.SelectedRows.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show("Click a tool in the group you want to $action first.", $Title)
        return ''
    }
    $group = [string]$grid.SelectedRows[0].Cells[2].Value
    if (-not $group -or $group -eq $OTHER -or $MohoGroups -contains $group) {
        [void][System.Windows.Forms.MessageBox]::Show("'$group' is one of Moho's own groups, so it can't be changed here. Only groups you made can be renamed or deleted.", $Title)
        return ''
    }
    return $group
}

$renameGroupButton = New-SideButton 'Rename group...' 192
$renameGroupButton.Add_Click({
    $grid.EndEdit()
    $old = Get-SelectedOwnGroup 'rename'
    if (-not $old) { return }
    $typed = [Microsoft.VisualBasic.Interaction]::InputBox("New name for the group '$old':", 'Rename group', $old)
    if (-not $typed) { return }
    $new = MPL-GroupName $typed
    if (-not $new -or $new -eq $old) { return }
    if ($groupColumn.Items.Contains($new)) {
        [void][System.Windows.Forms.MessageBox]::Show("There's already a group called '$new'.", $Title)
        return
    }
    # add the new name, move the tools to it, then drop the old name
    $groupColumn.Items.Insert($groupColumn.Items.IndexOf($old), $new)
    foreach ($row in $grid.Rows) { if ([string]$row.Cells[2].Value -eq $old) { $row.Cells[2].Value = $new } }
    $groupColumn.Items.Remove($old)
    $script:Groups = @($script:Groups | ForEach-Object { if ($_ -eq $old) { $new } else { $_ } })
    if ($map.Contains($old)) { $map[$new] = $map[$old]; $map.Remove($old) }
})

$deleteGroupButton = New-SideButton 'Delete group...' 228
$deleteGroupButton.Add_Click({
    $grid.EndEdit()
    $group = Get-SelectedOwnGroup 'delete'
    if (-not $group) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show("Delete the group '$group'? Its tools go back to (Other).", $Title, 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    foreach ($row in $grid.Rows) { if ([string]$row.Cells[2].Value -eq $group) { $row.Cells[2].Value = $OTHER } }
    $groupColumn.Items.Remove($group)
    $script:Groups = @($script:Groups | Where-Object { $_ -ne $group })
    if ($map.Contains($group)) { $map.Remove($group) }
})


# ---------- saving ----------

# The grid as a map: group -> tools in order. Tools in toolbar.json that weren't found
# this time (in no package now) keep their place.
function Get-GridMap {
    $fromGrid = [ordered]@{}
    foreach ($row in $grid.Rows) {
        $group = [string]$row.Cells[2].Value
        if (-not $group -or $group -eq $OTHER) { continue }
        if (-not $fromGrid.Contains($group)) { $fromGrid[$group] = New-Object System.Collections.Generic.List[string] }
        $fromGrid[$group].Add([string]$row.Cells[3].Value)          # the file name
    }
    $result = [ordered]@{}
    foreach ($group in $script:Groups) {
        if ($group -eq $OTHER) { continue }
        $list = @()
        if ($fromGrid.Contains($group)) { $list = @($fromGrid[$group]) }
        if ($map.Contains($group)) {
            foreach ($tool in $map[$group]) {
                if (-not $tools.Contains($tool.ToLower()) -and $list -notcontains $tool) { $list += $tool }
            }
        }
        if ($list.Count -gt 0) { $result[$group] = $list }
    }
    return $result
}

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = 'Save'
$saveButton.Size = New-Object System.Drawing.Size(110, 32)
$saveButton.Location = New-Object System.Drawing.Point(12, 518)
$saveButton.Anchor = 'Bottom,Left'


$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Size = New-Object System.Drawing.Size(110, 32)
$cancelButton.Location = New-Object System.Drawing.Point(538, 518)
$cancelButton.Anchor = 'Bottom,Right'
$cancelButton.DialogResult = 'Cancel'

$installedOnly = New-Object System.Windows.Forms.CheckBox
$installedOnly.Text = 'Show ticked only'
$installedOnly.AutoSize = $true
$installedOnly.Location = New-Object System.Drawing.Point(140, 524)
$installedOnly.Anchor = 'Bottom,Left'
$installedOnly.Add_CheckedChanged({
    $grid.ClearSelection()
    $grid.CurrentCell = $null
    foreach ($row in $grid.Rows) {
        $row.Visible = (-not $installedOnly.Checked) -or [bool]$row.Cells[0].Value
    }
})

$form.Controls.AddRange(@($saveButton, $installedOnly, $cancelButton))
$form.CancelButton = $cancelButton

# What was saved, in words: for the message and the log
function Describe-Map($m) {
    if ($m.Count -eq 0) { return '(no tools in groups: all in Other)' }
    return (($m.Keys | ForEach-Object { "$_ : " + (@($m[$_]) -join ', ') }) -join "`n")
}

# Save the ticks the same way the launcher does (whole packages). Returns what changed, in words.
function Save-Ticks {
    $settings = MPL-LoadSettings
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($k in $settings.Selected) { $selected.Add($k) }

    $onNow = @{}
    $showName = @{}
    foreach ($row in $grid.Rows) {
        $package = [string]$row.Cells[4].Value
        if (-not $package) { continue }
        if (-not $showName.ContainsKey($package)) { $showName[$package] = [string]$row.Cells[1].Value }
        if (-not $onNow.ContainsKey($package)) { $onNow[$package] = $false }
        if ([bool]$row.Cells[0].Value) { $onNow[$package] = $true }
    }
    $switchedOn = @()
    $switchedOff = @()
    foreach ($package in $onNow.Keys) {
        if ($onNow[$package] -and -not $selected.Contains($package)) { $selected.Add($package); $switchedOn += $showName[$package] }
        if (-not $onNow[$package] -and $selected.Contains($package)) { [void]$selected.Remove($package); $switchedOff += $showName[$package] }
    }
    if ($switchedOn.Count -eq 0 -and $switchedOff.Count -eq 0) { return '' }
    $settings.Selected = $selected.ToArray()
    MPL-SaveSettings $settings
    $words = @()
    if ($switchedOn.Count)  { $words += "Switched on: "  + ($switchedOn  -join ', ') }
    if ($switchedOff.Count) { $words += "Switched off: " + ($switchedOff -join ', ') }
    return ($words -join "`n")
}

$saveButton.Add_Click({
    $grid.EndEdit()
    $saved = Get-GridMap
    MPL-SaveToolbarMap $saved
    $ticks = Save-Ticks
    MPL-Log ("Sort toolbar saved:`n" + (Describe-Map $saved))
    if ($ticks) { MPL-Log $ticks }
    MPL-SaveLog
    # Short message; the full list of groups goes to the log
    $toolCount = 0
    foreach ($g in $saved.Keys) { $toolCount += @($saved[$g]).Count }
    $message = "Saved: $toolCount tools in $($saved.Count) groups."
    if ($ticks) { $message += "`n`n$ticks" }
    $message += "`n`nClick Launch Moho to see it."
    [void][System.Windows.Forms.MessageBox]::Show($message, $Title)
    $form.DialogResult = 'OK'
    $form.Close()
})

[void]$form.ShowDialog()
$form.Dispose()
