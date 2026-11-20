# ==========================================================================
#  Moho Power Launcher
#  Pick the scripts you want for this session - by column, one by one, or a
#  saved configuration - and start Moho with exactly those.
#
#  Scripts live in your script library (the "scripts master folder", one
#  package per script). The launcher copies the ticked ones into Moho's
#  scripts folder and takes them out again when they're unticked.
#  It never removes or changes anything it didn't put there itself.
#
#  Copyright (C) 2026 Cheesoid: Doug Craven and Claude (an AI model by Anthropic)
#  PolyForm Noncommercial License 1.0.0 - see LICENSE
# ==========================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic          # for InputBox and AppActivate
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'

$Self = $MyInvocation.MyCommand.Path
. (Join-Path $PSScriptRoot 'MPL-Common.ps1')
$Icon = $null
try { $Icon = New-Object System.Drawing.Icon (Join-Path $PSScriptRoot 'MohoPowerLauncher.ico') } catch {}


# ==========================================================================
#  Only one launcher at a time
# ==========================================================================
#  The launcher reopens itself in this same process after Install script...,
#  Sort toolbar..., Settings... or moving a script; it already holds the lock then.

if (-not $global:MPLMutex) {
    $mutex = New-Object System.Threading.Mutex($false, $MPL.MutexName)
    $gotIt = $false
    try {
        $gotIt = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $gotIt = $true                       # the last launcher crashed without letting go
    }
    if (-not $gotIt) {
        [void](MPL-Box "$($MPL.Name) is already running.`n`nUse the window that's open (it may be behind another one)." 'Information')
        try { [Microsoft.VisualBasic.Interaction]::AppActivate($MPL.Name) } catch {}   # bring it to the front
        exit 0
    }
    $global:MPLMutex = $mutex                # held until this launcher closes
}

# Close this window's leftovers and open the launcher again (same process)
function Reopen-Launcher {
    & $Self
    exit 0
}

$S = MPL-LoadSettings


# ==========================================================================
#  Settings window (first run, or the Settings... button)
# ==========================================================================

function Show-SettingsDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "$($MPL.Name) - Settings"
    $dialog.StartPosition = 'CenterScreen'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $dialog.ClientSize = New-Object System.Drawing.Size(620, 300)
    if ($Icon) { $dialog.Icon = $Icon }

    $rows = @(
        @{ Key = 'MohoPath';      Label = 'Moho program (Moho.exe):';                                    IsFile = $true  },
        @{ Key = 'ContentFolder'; Label = "Moho's Custom Content Folder (holds the 'scripts' folder):"; IsFile = $false },
        @{ Key = 'MasterFolder';  Label = 'Your script library (one folder per script):';               IsFile = $false }
    )
    $boxes = @{}
    $y = 14
    foreach ($row in $rows) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $row.Label
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point(14, $y)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Text = [string]$S[$row.Key]
        $box.Location = New-Object System.Drawing.Point(14, ($y + 24))
        $box.Size = New-Object System.Drawing.Size(490, 26)

        $browse = New-Object System.Windows.Forms.Button
        $browse.Text = 'Browse...'
        $browse.Location = New-Object System.Drawing.Point(512, ($y + 22))
        $browse.Size = New-Object System.Drawing.Size(94, 30)
        $isFile = $row.IsFile
        $browse.Add_Click({
            if ($isFile) {
                $picker = New-Object System.Windows.Forms.OpenFileDialog
                $picker.Filter = 'Moho (Moho.exe)|Moho.exe|Programs (*.exe)|*.exe'
                if ($picker.ShowDialog() -eq 'OK') { $box.Text = $picker.FileName }
            } else {
                $picker = New-Object System.Windows.Forms.FolderBrowserDialog
                if (MPL-Exists $box.Text) { $picker.SelectedPath = $box.Text }
                if ($picker.ShowDialog() -eq 'OK') { $box.Text = $picker.SelectedPath }
            }
        }.GetNewClosure())

        $dialog.Controls.AddRange(@($label, $box, $browse))
        $boxes[$row.Key] = $box
        $y += 76
    }

    $save = New-Object System.Windows.Forms.Button
    $save.Text = 'Save'
    $save.Size = New-Object System.Drawing.Size(110, 32)
    $save.Location = New-Object System.Drawing.Point(380, 252)
    $save.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Size = New-Object System.Drawing.Size(110, 32)
    $cancel.Location = New-Object System.Drawing.Point(496, 252)
    $cancel.DialogResult = 'Cancel'
    $dialog.Controls.AddRange(@($save, $cancel))
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel

    if ($dialog.ShowDialog() -ne 'OK') { return $false }

    foreach ($key in $boxes.Keys) { $S[$key] = $boxes[$key].Text.Trim() }
    if (-not (MPL-Exists $S.MohoPath)) {
        [void](MPL-Box "Moho.exe was not found at:`n$($S.MohoPath)" 'Warning')
    }
    if (-not (MPL-Exists $S.ContentFolder)) {
        [void](MPL-Box "That Custom Content Folder doesn't exist:`n$($S.ContentFolder)`n`nIn Moho: File > Open Custom Content Folder shows where yours is." 'Warning')
    }
    if ($S.MasterFolder -and -not (MPL-Exists $S.MasterFolder)) {
        try { New-Item -ItemType Directory -Path $S.MasterFolder -Force | Out-Null }
        catch { [void](MPL-Box "Couldn't make the script library folder:`n$($S.MasterFolder)" 'Warning') }
    }
    MPL-SaveSettings $S
    return $true
}

# First run without the installer, or folders gone: fill in what can be found, then ask
if (-not (MPL-Exists $S.MohoPath))      { $S.MohoPath = MPL-FindMoho }
if (-not (MPL-Exists $S.ContentFolder)) { $S.ContentFolder = MPL-FindContentFolder }
if (-not $S.MasterFolder -and $S.ContentFolder) {
    $S.MasterFolder = Join-Path $S.ContentFolder 'scripts master folder'
}
if (-not $S.MohoPath -or -not (MPL-Exists $S.ContentFolder) -or -not $S.MasterFolder) {
    if (-not (Show-SettingsDialog)) { exit 0 }
    if (-not (MPL-Exists $S.ContentFolder) -or -not $S.MasterFolder) { exit 0 }
}
if (-not (MPL-Exists $S.MasterFolder)) { New-Item -ItemType Directory -Path $S.MasterFolder -Force | Out-Null }


# ==========================================================================
#  The library and what's ticked
# ==========================================================================

$Items = @(MPL-ReadMaster $S)
$PreviouslyTicked = @($S.Selected)
$script:Configs = $S.Configurations
$script:LastConfig = [string]$S.LastConfiguration

function Save-Choices([string[]]$tickedKeys) {
    $S.Selected = MPL-Flatten $tickedKeys
    $S.Configurations = $script:Configs
    $S.LastConfiguration = $script:LastConfig
    MPL-SaveSettings $S
}

# Columns: the ones in settings, then any new ones named in labels, then Unsorted if needed
$Columns = @($S.Columns)
foreach ($column in ($Items | ForEach-Object { $_.Group } | Sort-Object -Unique)) {
    if ($column -ne 'Unsorted' -and $Columns -notcontains $column) { $Columns += $column }
}
if ($Items | Where-Object { $_.Group -eq 'Unsorted' }) { $Columns += 'Unsorted' }

# Scripts named "... (AI)" (or whatever SplitTag says) get a second box in their column
$SplitTag = [string]$S.SplitTag
function Test-Tagged($item) {
    if (-not $SplitTag) { return $false }
    return ($item.Name -match ('\(' + [regex]::Escape($SplitTag) + '\)\s*$'))
}


# ==========================================================================
#  The window
# ==========================================================================

$ColumnWidth = 230
$BoxHeight   = 560
$TopBarHeight = 44

$form = New-Object System.Windows.Forms.Form
$form.Text = "$($MPL.Name)  $($MPL.Version)"
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$formWidth = [Math]::Max(940, 12 + $Columns.Count * ($ColumnWidth + 8))
$form.ClientSize = New-Object System.Drawing.Size($formWidth, ($BoxHeight + 70 + $TopBarHeight))
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
if ($Icon) { $form.Icon = $Icon }

$State = @{ Busy = $false }       # true while a whole column is being ticked at once
$Panels = @{}                     # panel title -> @{ List; Items }
$PanelOrder = @()


# ---------- moving a script to another column (drag it, or right-click > Move to) ----------
# The column lives in the script's launcher.txt ("Column | Name"); the launcher reopens to show the change.

$Drag = @{ From = $null; Index = -1; Start = $null; WasTicked = $null; Item = $null; LastCheck = $null }

function Move-ToColumn($item, [string]$column) {
    if (-not $item -or -not $column -or $item.Group -eq $column) { return }
    if ($item.Loose) {
        [void](MPL-Box "'$($item.Name)' is a single .lua file, so it has no label to change.`n`nUse Install script... on it to make it a full package, then it can be moved." 'Information')
        return
    }
    try {
        MPL-WriteLabel $item.Path $column $item.Name
    } catch {
        [void](MPL-Box ("Couldn't move it: " + $_.Exception.Message) 'Error')
        return
    }
    MPL-Log "Moved '$($item.Name)' from $($item.Group) to $column."
    MPL-SaveLog
    Save-Choices (Get-TickedKeys)
    $form.Tag = 'refresh'
    $form.DialogResult = 'Retry'
    $form.Close()
}

function Enable-Moving($list) {
    $list.AllowDrop = $true

    # A click can flip a tick before MouseDown arrives; remember each flip so a drag can undo it
    $list.Add_ItemCheck({
        param($sender, $e)
        $Drag.LastCheck = @{ List = $sender; Index = $e.Index; Old = $e.CurrentValue; Time = [Environment]::TickCount }
    })

    $list.Add_MouseDown({
        param($sender, $e)
        $Drag.Index = -1
        if ($e.Button -ne 'Left') { return }
        $index = $sender.IndexFromPoint($e.Location)
        if ($index -lt 0) { return }
        $Drag.From = $sender
        $Drag.Index = $index
        $Drag.Start = $e.Location
        $last = $Drag.LastCheck
        $justFlipped = $last -and $last.List -eq $sender -and $last.Index -eq $index -and
                       ([Environment]::TickCount - $last.Time) -lt 500
        if ($justFlipped) { $Drag.WasTicked = ($last.Old -eq 'Checked') }
        else              { $Drag.WasTicked = $sender.GetItemChecked($index) }
    })

    $list.Add_MouseMove({
        param($sender, $e)
        if ($e.Button -ne 'Left' -or $Drag.From -ne $sender -or $Drag.Index -lt 0) { return }
        $distance = [Math]::Abs($e.X - $Drag.Start.X) + [Math]::Abs($e.Y - $Drag.Start.Y)
        if ($distance -lt 10) { return }                   # a click, not a drag yet
        $index = $Drag.Index
        $Drag.Index = -1
        $sender.SetItemChecked($index, [bool]$Drag.WasTicked)  # dragging must not change the tick
        $Drag.Item = $Panels[$sender.Tag.Title].Items[$index]
        [void]$sender.DoDragDrop('mpl-move', [System.Windows.Forms.DragDropEffects]::Move)
        $Drag.Item = $null
    })

    $list.Add_DragOver({
        param($sender, $e)
        if ($Drag.Item -and $Drag.Item.Group -ne $sender.Tag.Column) { $e.Effect = 'Move' }
        else { $e.Effect = 'None' }
    })

    $list.Add_DragDrop({
        param($sender, $e)
        $item = $Drag.Item
        $Drag.Item = $null
        Move-ToColumn $item $sender.Tag.Column
    })

    # Right-click > Move to
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Tag = $list
    $list.ContextMenuStrip = $menu
    $menu.Add_Opening({
        param($sender, $e)
        $theList = $sender.Tag
        $index = $theList.IndexFromPoint($theList.PointToClient([System.Windows.Forms.Cursor]::Position))
        $sender.Items.Clear()
        if ($index -lt 0) { $e.Cancel = $true; return }
        $item = $Panels[$theList.Tag.Title].Items[$index]

        $moveTo = New-Object System.Windows.Forms.ToolStripMenuItem ("Move '" + $item.Name + "' to")
        foreach ($column in ($Columns | Where-Object { $_ -ne 'Unsorted' -and $_ -ne $item.Group })) {
            $choice = New-Object System.Windows.Forms.ToolStripMenuItem $column
            $choice.Tag = @{ Item = $item; Column = $column }
            $choice.Add_Click({ param($clicked, $ev) Move-ToColumn $clicked.Tag.Item $clicked.Tag.Column })
            [void]$moveTo.DropDownItems.Add($choice)
        }
        $newColumn = New-Object System.Windows.Forms.ToolStripMenuItem 'New column...'
        $newColumn.Tag = $item
        $newColumn.Add_Click({
            param($clicked, $ev)
            $name = [Microsoft.VisualBasic.Interaction]::InputBox('Name for the new column:', 'New column', '')
            if ($name -and $name.Trim()) { Move-ToColumn $clicked.Tag ($name.Trim() -replace '\|', '-') }
        })
        [void]$moveTo.DropDownItems.Add($newColumn)
        [void]$sender.Items.Add($moveTo)
    })
}


# ---------- one framed box: the column's tick box as its title, a list of scripts, All / None ----------

function Add-Panel([string]$title, $items, [int]$left, [int]$top, [int]$height, [string]$column) {
    $State = $script:State                     # captured by the closures below

    $frame = New-Object System.Windows.Forms.GroupBox
    $frame.Text = ''
    $frame.Location = New-Object System.Drawing.Point($left, $top)
    $frame.Size = New-Object System.Drawing.Size($ColumnWidth, $height)

    $header = New-Object System.Windows.Forms.CheckBox
    $header.Text = $title
    $header.AutoSize = $true
    $header.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $header.BackColor = [System.Drawing.SystemColors]::Control
    $header.Location = New-Object System.Drawing.Point(8, 0)

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.CheckOnClick = $true
    $list.IntegralHeight = $false
    $list.Location = New-Object System.Drawing.Point(8, 28)
    $list.Size = New-Object System.Drawing.Size(($ColumnWidth - 16), ($height - 74))
    foreach ($item in $items) { [void]$list.Items.Add($item.Name, ($PreviouslyTicked -contains $item.Key)) }
    $list.Tag = @{ Title = $title; Column = $column }

    $all = New-Object System.Windows.Forms.Button
    $all.Text = 'All'
    $all.Location = New-Object System.Drawing.Point(8, ($height - 40))
    $all.Size = New-Object System.Drawing.Size(70, 28)
    $all.Add_Click({ for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $true) } }.GetNewClosure())

    $none = New-Object System.Windows.Forms.Button
    $none.Text = 'None'
    $none.Location = New-Object System.Drawing.Point(84, ($height - 40))
    $none.Size = New-Object System.Drawing.Size(70, 28)
    $none.Add_Click({ for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $false) } }.GetNewClosure())

    $frame.Controls.AddRange(@($header, $list, $all, $none))
    $header.BringToFront()
    $form.Controls.Add($frame)
    $script:Panels[$title] = @{ List = $list; Items = $items }
    $script:PanelOrder += $title
    Enable-Moving $list

    # the title box is ticked when every script in the box is
    $header.Checked = ($list.Items.Count -gt 0 -and $list.CheckedItems.Count -eq $list.Items.Count)
    $header.Add_Click({
        $State.Busy = $true
        for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $header.Checked) }
        $State.Busy = $false
    }.GetNewClosure())
    $list.Add_ItemCheck({
        param($sender, $e)
        if ($State.Busy) { return }
        $tickedAfter = $list.CheckedItems.Count
        if ($e.NewValue -eq 'Checked') { $tickedAfter++ } else { $tickedAfter-- }
        $header.Checked = ($tickedAfter -eq $list.Items.Count)
    }.GetNewClosure())
}

# Lay out the columns. A column with both plain and tagged scripts gets two boxes.
$x = 12
$top = 10 + $TopBarHeight
foreach ($column in $Columns) {
    $inColumn = @($Items | Where-Object { $_.Group -eq $column } | Sort-Object Name)
    $plain    = @($inColumn | Where-Object { -not (Test-Tagged $_) })
    $tagged   = @($inColumn | Where-Object { Test-Tagged $_ })
    if ($plain.Count -gt 0 -and $tagged.Count -gt 0) {
        $gap = 8
        $rowHeight = 19
        $minimum = 74 + $rowHeight * 3 + 6
        $upper = 74 + $rowHeight * [Math]::Max(3, $plain.Count) + 6      # room for the plain scripts...
        $upper = [Math]::Min($upper, [int](($BoxHeight - $gap) * 0.55))    # ...but at most 55%
        $upper = [Math]::Max($upper, $minimum)
        Add-Panel $column $plain $x $top $upper $column
        Add-Panel ($SplitTag + ' ' + $column) $tagged $x ($top + $upper + $gap) ($BoxHeight - $upper - $gap) $column
    } else {
        Add-Panel $column $inColumn $x $top $BoxHeight $column
    }
    $x += $ColumnWidth + 8
}

if ($Items.Count -eq 0) {
    $empty = New-Object System.Windows.Forms.Label
    $empty.Text = "Your script library is empty.`n`nClick  Install script...  (top right) to add a script you downloaded, or one you already installed with Moho's own Scripts > Install Script."
    $empty.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $empty.TextAlign = 'MiddleCenter'
    $empty.BackColor = [System.Drawing.SystemColors]::Control
    $empty.Location = New-Object System.Drawing.Point(40, ($top + 180))
    $empty.Size = New-Object System.Drawing.Size(($form.ClientSize.Width - 80), 120)
    $form.Controls.Add($empty)
    $empty.BringToFront()
}


# ---------- ticks ----------

function Get-TickedKeys {
    $keys = @()
    foreach ($title in $PanelOrder) {
        $panel = $Panels[$title]
        foreach ($i in $panel.List.CheckedIndices) { $keys += $panel.Items[$i].Key }
    }
    return ,$keys
}

function Set-TickedKeys($keys) {
    $wanted = MPL-Flatten $keys
    foreach ($title in $PanelOrder) {
        $panel = $Panels[$title]
        for ($i = 0; $i -lt $panel.List.Items.Count; $i++) {
            $panel.List.SetItemChecked($i, ($wanted -contains $panel.Items[$i].Key))
        }
    }
}


# ---------- top bar: configurations, Settings..., Sort toolbar..., Install script... ----------

function New-Button([string]$text, [int]$width, [int]$left, [int]$top, [int]$height = 30) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size($width, $height)
    $b.Location = New-Object System.Drawing.Point($left, $top)
    return $b
}

$configLabel = New-Object System.Windows.Forms.Label
$configLabel.Text = 'Configuration:'
$configLabel.AutoSize = $true
$configLabel.Location = New-Object System.Drawing.Point(14, 16)

$configList = New-Object System.Windows.Forms.ComboBox
$configList.DropDownStyle = 'DropDownList'
$configList.Location = New-Object System.Drawing.Point(115, 12)
$configList.Size = New-Object System.Drawing.Size(220, 28)

$saveConfig   = New-Button 'Save as...' 96 343 10
$deleteConfig = New-Button 'Delete'     76 445 10
$form.Controls.AddRange(@($configLabel, $configList, $saveConfig, $deleteConfig))

$W = $form.ClientSize.Width
$installButton  = New-Button 'Install script...' 130 ($W - 146) 10
$sortButton     = New-Button 'Sort toolbar...'   120 ($W - 274) 10
$settingsButton = New-Button 'Settings...'        96 ($W - 378) 10
$form.Controls.AddRange(@($installButton, $sortButton, $settingsButton))

$script:LoadingConfigs = $false
function Refresh-ConfigList([string]$select) {
    $script:LoadingConfigs = $true
    $configList.Items.Clear()
    foreach ($name in ($script:Configs.Keys | Sort-Object)) { [void]$configList.Items.Add($name) }
    $configList.SelectedIndex = $configList.Items.IndexOf($select)
    $deleteConfig.Enabled = ($configList.SelectedIndex -ge 0)
    $script:LoadingConfigs = $false
}

# These three close the window, run their tool in this same PowerShell, then reopen the launcher
function Close-For([string]$what) {
    Save-Choices (Get-TickedKeys)
    $form.Tag = $what
    $form.DialogResult = 'Retry'
    $form.Close()
}
$installButton.Add_Click({  Close-For 'install' })
$sortButton.Add_Click({     Close-For 'sort' })
$settingsButton.Add_Click({ Close-For 'settings' })

$configList.Add_SelectedIndexChanged({
    $deleteConfig.Enabled = ($configList.SelectedIndex -ge 0)
    if ($script:LoadingConfigs -or $configList.SelectedIndex -lt 0) { return }
    $name = [string]$configList.SelectedItem
    Set-TickedKeys $script:Configs[$name]
    $script:LastConfig = $name
})

$saveConfig.Add_Click({
    $suggested = ''
    if ($configList.SelectedIndex -ge 0) { $suggested = [string]$configList.SelectedItem }
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Name for this set of scripts:', 'Save configuration', $suggested)
    if ($null -eq $name) { return }
    $name = $name.Trim()
    if ($name -eq '') { return }
    if ($script:Configs.Contains($name)) {
        $answer = MPL-Box "Replace the saved configuration '$name' with the scripts ticked now?" 'Question' 'YesNo'
        if ($answer -ne 'Yes') { return }
    }
    $script:Configs[$name] = MPL-Flatten (Get-TickedKeys)
    $script:LastConfig = $name
    Refresh-ConfigList $name
    Save-Choices (Get-TickedKeys)
})

$deleteConfig.Add_Click({
    if ($configList.SelectedIndex -lt 0) { return }
    $name = [string]$configList.SelectedItem
    $answer = MPL-Box "Delete the configuration '$name'? (Your scripts are not touched.)" 'Question' 'YesNo'
    if ($answer -ne 'Yes') { return }
    $script:Configs.Remove($name)
    if ($script:LastConfig -eq $name) { $script:LastConfig = '' }
    Refresh-ConfigList ''
    Save-Choices (Get-TickedKeys)
})


# ---------- bottom row: library path, Everything, None, Launch Moho, Cancel ----------

$y = $BoxHeight + 25 + $TopBarHeight
$libraryLabel = New-Object System.Windows.Forms.Label
$libraryLabel.Text = "Library: $($S.MasterFolder)"
$libraryLabel.AutoEllipsis = $true
$libraryLabel.ForeColor = [System.Drawing.SystemColors]::GrayText
$libraryLabel.Location = New-Object System.Drawing.Point(14, ($y + 8))
$libraryLabel.Size = New-Object System.Drawing.Size(($W - 560), 22)

$everything = New-Button 'Everything'  100 ($W - 530) $y 32
$nothing    = New-Button 'None'        100 ($W - 424) $y 32
$launch     = New-Button 'Launch Moho' 140 ($W - 296) $y 32
$cancel     = New-Button 'Cancel'      130 ($W - 146) $y 32
$launch.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$launch.DialogResult = 'OK'
$cancel.DialogResult = 'Cancel'

function Set-AllTicks([bool]$ticked) {
    foreach ($title in $Panels.Keys) {
        $list = $Panels[$title].List
        for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $ticked) }
    }
}
$everything.Add_Click({ Set-AllTicks $true })
$nothing.Add_Click({ Set-AllTicks $false })

$form.Controls.AddRange(@($libraryLabel, $everything, $nothing, $launch, $cancel))
$form.AcceptButton = $launch
$form.CancelButton = $cancel
Refresh-ConfigList $script:LastConfig


# ==========================================================================
#  Show it, then do what was chosen
# ==========================================================================

$result = $form.ShowDialog()

if ($result -eq 'Retry') {
    $what = [string]$form.Tag
    $form.Dispose()
    try {
        switch ($what) {
            'install'  { & (Join-Path $PSScriptRoot 'InstallScript.ps1') }
            'sort'     { & (Join-Path $PSScriptRoot 'SortToolbar.ps1') }
            'settings' { [void](Show-SettingsDialog) }
            'refresh'  { }
        }
    } catch {
        [void](MPL-Box ("That didn't finish: " + $_.Exception.Message) 'Error')
    }
    Reopen-Launcher
}
if ($result -ne 'OK') { exit 0 }

# ---------- Launch Moho ----------

$script:LastConfig = ''
if ($configList.SelectedIndex -ge 0) { $script:LastConfig = [string]$configList.SelectedItem }
$chosen = @()
foreach ($title in $PanelOrder) {
    $panel = $Panels[$title]
    foreach ($i in $panel.List.CheckedIndices) { $chosen += $panel.Items[$i] }
}
Save-Choices @($chosen | ForEach-Object { $_.Key })
$form.Dispose()

# Moho must be closed while its scripts change. Back to the launcher if it isn't.
if (Get-Process -Name 'Moho' -ErrorAction SilentlyContinue) {
    [void](MPL-Box 'Moho is already running. Close it, then click Launch Moho again.' 'Warning')
    Reopen-Launcher
}

if (-not (MPL-Exists $S.MohoPath)) {
    $S.MohoPath = MPL-FindMoho
    if (-not $S.MohoPath) {
        [void](MPL-Box 'Moho.exe was not found. Set it in Settings... - nothing was changed.' 'Error')
        Reopen-Launcher
    }
    MPL-SaveSettings $S
}

# Before changing anything: is Moho reading the folder the launcher fills?
$mohoReads = MPL-MohoContentFolder
if (-not (MPL-SameFolder $mohoReads $S.ContentFolder)) {
    $answer = MPL-Box ("Moho is set to read scripts from:`n$mohoReads`n`nbut the launcher puts them in:`n$($S.ContentFolder)`n`n" +
                       "Moho won't see them. Launch anyway?`n`n(No goes back to the launcher: fix it with Settings..., or in Moho's Preferences.)") 'Warning' 'YesNo'
    if ($answer -ne 'Yes') { Reopen-Launcher }
}

try {
    MPL-Log "Launch: $($chosen.Count) scripts ticked. Moho: $($S.MohoPath)"
    [void](MPL-Apply $S $chosen)
    MPL-Log (MPL-ToolbarApply $S)
} catch {
    MPL-Log ("ERROR: " + $_.Exception.Message)
    MPL-SaveLog
    [void](MPL-Box ("Setting up the scripts failed: " + $_.Exception.Message + "`n`nNothing of yours was removed. Details: $($MPL.Log)") 'Error')
    exit 1
}
MPL-SaveLog

if ($script:MPLWarnings.Count -gt 0) {
    $message = ($script:MPLWarnings | Select-Object -First 10) -join "`n`n"
    if ($script:MPLWarnings.Count -gt 10) { $message += "`n`n(and $($script:MPLWarnings.Count - 10) more in the log)" }
    $answer = MPL-Box ($message + "`n`nStart Moho anyway?") 'Warning' 'YesNo'
    if ($answer -ne 'Yes') { exit 0 }
}
Start-Process -FilePath $S.MohoPath
