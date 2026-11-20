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
    $baseLines = MPL-StripOurs (MPL-ReadLines $listPath).Lines
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

$tools = [ordered]@{}            # lower-case name -> @{ Name; From }
function Add-ToolsFrom([string]$dir, [string]$from) {
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.lua' -File)) {
        $key = $file.BaseName.ToLower()
        if ($mohoTools.ContainsKey($key) -or $tools.Contains($key)) { continue }
        $tools[$key] = @{ Name = $file.BaseName; From = $from }
    }
}
Add-ToolsFrom (Join-Path $Scripts 'tool') 'installed'
if (MPL-Exists $S.MasterFolder) {
    foreach ($toolDir in (Get-ChildItem -LiteralPath $S.MasterFolder -Recurse -Directory -Filter 'tool')) {
        Add-ToolsFrom $toolDir.FullName ('library: ' + $toolDir.Parent.Name)
    }
}
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
$info.Text = "Pick a Tools-panel group for each add-on tool. Up / Down sets its place in the group.`n'New group...' makes one of your own. (Other) = Moho's Other group."
$info.Location = New-Object System.Drawing.Point(12, 8)
$info.Size = New-Object System.Drawing.Size(636, 36)
$form.Controls.Add($info)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(12, 48)
$grid.Size = New-Object System.Drawing.Size(530, 460)
$grid.Anchor = 'Top,Bottom,Left,Right'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'

$toolColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$toolColumn.HeaderText = 'Tool'
$toolColumn.ReadOnly = $true
$toolColumn.FillWeight = 40
$fromColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$fromColumn.HeaderText = 'Found in'
$fromColumn.ReadOnly = $true
$fromColumn.FillWeight = 35
$groupColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
$groupColumn.HeaderText = 'Group'
$groupColumn.FillWeight = 25
$groupColumn.FlatStyle = 'Flat'
foreach ($group in $script:Groups) { [void]$groupColumn.Items.Add($group) }
[void]$grid.Columns.Add($toolColumn)
[void]$grid.Columns.Add($fromColumn)
[void]$grid.Columns.Add($groupColumn)
$form.Controls.Add($grid)

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
        Name     = $tools[$key].Name
        From     = $tools[$key].From
        Group    = $group
        GroupNo  = [array]::IndexOf($script:Groups, $group)
        Position = $position
    }
}
foreach ($row in ($rows | Sort-Object GroupNo, Position, Name)) {
    [void]$grid.Rows.Add($row.Name, $row.From, $row.Group)
}


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

function Move-Row([int]$step) {
    if ($grid.SelectedRows.Count -eq 0) { return }
    $from = $grid.SelectedRows[0].Index
    $to = $from + $step
    if ($to -lt 0 -or $to -ge $grid.Rows.Count) { return }
    $cells = $grid.Rows[$from].Cells
    $values = @($cells[0].Value, $cells[1].Value, $cells[2].Value)
    $grid.Rows.RemoveAt($from)
    $grid.Rows.Insert($to, $values[0], $values[1], $values[2])
    $grid.ClearSelection()
    $grid.Rows[$to].Selected = $true
    $grid.CurrentCell = $grid.Rows[$to].Cells[0]
}

$upButton = New-SideButton 'Up' 48
$upButton.Add_Click({ Move-Row -1 })
$downButton = New-SideButton 'Down' 84
$downButton.Add_Click({ Move-Row 1 })

$newGroupButton = New-SideButton 'New group...' 132
$newGroupButton.Add_Click({
    $typed = [Microsoft.VisualBasic.Interaction]::InputBox('Name for the new Tools-panel group:', 'New group', '')
    if (-not $typed) { return }
    $name = MPL-GroupName $typed                 # letters, digits, - and _ only
    if (-not $name -or $groupColumn.Items.Contains($name)) { return }
    $groupColumn.Items.Insert($groupColumn.Items.Count - 1, $name)       # before (Other)
    $script:Groups = @($script:Groups | Where-Object { $_ -ne $OTHER }) + @($name, $OTHER)
    if ($grid.SelectedRows.Count -gt 0) { $grid.SelectedRows[0].Cells[2].Value = $name }
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
        $fromGrid[$group].Add([string]$row.Cells[0].Value)
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

$saveNowButton = New-Object System.Windows.Forms.Button
$saveNowButton.Text = 'Save and update now'
$saveNowButton.Size = New-Object System.Drawing.Size(170, 32)
$saveNowButton.Location = New-Object System.Drawing.Point(130, 518)
$saveNowButton.Anchor = 'Bottom,Left'

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Size = New-Object System.Drawing.Size(110, 32)
$cancelButton.Location = New-Object System.Drawing.Point(538, 518)
$cancelButton.Anchor = 'Bottom,Right'
$cancelButton.DialogResult = 'Cancel'

$form.Controls.AddRange(@($saveButton, $saveNowButton, $cancelButton))
$form.CancelButton = $cancelButton

$saveButton.Add_Click({
    $grid.EndEdit()
    MPL-SaveToolbarMap (Get-GridMap)
    [void][System.Windows.Forms.MessageBox]::Show('Saved. The launcher applies it next time it starts Moho.', $Title)
    $form.DialogResult = 'OK'
    $form.Close()
})

$saveNowButton.Add_Click({
    $grid.EndEdit()
    if (Get-Process -Name 'Moho' -ErrorAction SilentlyContinue) {
        [void][System.Windows.Forms.MessageBox]::Show('Close Moho first: it reads the Tools-panel list when it starts.', $Title, 'OK', 'Warning')
        return
    }
    MPL-SaveToolbarMap (Get-GridMap)
    $summary = MPL-ToolbarApply $S
    MPL-Log $summary
    MPL-SaveLog
    [void][System.Windows.Forms.MessageBox]::Show("Saved and updated.`n$summary`nStart Moho to see it.", $Title)
    $form.DialogResult = 'OK'
    $form.Close()
})

[void]$form.ShowDialog()
$form.Dispose()
