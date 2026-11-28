# ==========================================================================
#  Moho Power Launcher - Setup (install, update, uninstall)
#
#  Install: copies the launcher to your user programs folder, finds Moho and
#  its Custom Content Folder, makes a script library folder, adds Start-menu
#  and desktop shortcuts, and lists itself in Windows' Installed apps.
#  No admin rights needed.
#
#  Uninstall (-Uninstall): takes out only the scripts the launcher put in
#  Moho's scripts folder. Your own scripts and your script library are left
#  exactly as they are.
#
#  Copyright (C) 2026 Cheesoid: Doug Craven and Claude (an AI model by Anthropic)
#  PolyForm Noncommercial License 1.0.0 - see LICENSE
# ==========================================================================
param([switch]$Uninstall)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'

# Runs from the unzipped download (app\MPL-Setup.ps1, via 'Install Moho Power Launcher.cmd') or from the installed copy
$AppFiles = $PSScriptRoot                                   # the app folder
$Download = Split-Path -Parent $AppFiles                    # the unzipped download (the Install .cmd, README, LICENSE)
if (-not (Get-ChildItem -LiteralPath $Download -Filter 'Install*.cmd' -File -ErrorAction SilentlyContinue)) { $Download = $AppFiles }
. (Join-Path $AppFiles 'MPL-Common.ps1')

$Name        = $MPL.Name
$InstallDir  = Join-Path $env:LOCALAPPDATA 'Programs\Moho Power Launcher'
$StartMenu   = Join-Path ([Environment]::GetFolderPath('Programs')) $Name
$DesktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) "$Name.lnk"
$AppsEntry   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MohoPowerLauncher'
$PowerShell  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$RepoUrl     = 'https://github.com/iamthecrave/Moho-Power-Launcher'
$LicenseUrl  = "$RepoUrl/blob/main/LICENSE"
$Email       = 'mohovibecoding@gmail.com'

function Box([string]$message, [string]$icon = 'Information', [string]$buttons = 'OK') {
    return [System.Windows.Forms.MessageBox]::Show($message, $Name, $buttons, $icon)
}

# A shortcut that runs one of the launcher's scripts with PowerShell, without a console window
function New-Shortcut([string]$path, [string]$script, [string]$arguments, [string]$description) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $PowerShell
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" $arguments".Trim()
    $link.WorkingDirectory = $InstallDir
    $link.IconLocation = (Join-Path $InstallDir 'MohoPowerLauncher.ico') + ',0'
    $link.WindowStyle = 7                      # start minimised: no console flash
    $link.Description = $description
    $link.Save()
}


# ==========================================================================
#  Uninstall
# ==========================================================================

if ($Uninstall) {
    $answer = Box ("Remove ${Name}?`n`nEvery script stays in Moho exactly as it is now, with its Tools-panel place.`n" +
                   "Your script library stays too.") 'Question' 'YesNo'
    if ($answer -ne 'Yes') { exit 0 }
    if (Get-Process -Name 'Moho' -ErrorAction SilentlyContinue) {
        [void](Box 'Close Moho first, then run Uninstall again.' 'Warning')
        exit 1
    }
    if (MPL-LauncherRunning) {
        [void](Box "Close the $Name window first, then run Uninstall again." 'Warning')
        exit 1
    }

    # 1.2.0 (Doug, 27 Nov): uninstalling leaves Moho's scripts folder alone. Taking the ticked
    # scripts out made them vanish from Moho. The install record stays in the shared folder, so a
    # reinstall (or another computer that uses this folder) carries on looking after them.
    $settings = MPL-LoadSettings
    $library = $settings.MasterFolder
    $report = "Your scripts are still in Moho, as they were."
    $keepData = $false

    foreach ($path in @($DesktopLink, $StartMenu)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -Path $AppsEntry -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $keepData) { Remove-Item -LiteralPath $MPL.DataDir -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

    $done = "$Name is removed.`n`n$report"
    if ($settings.ContentFolder) {
        $sharedDir = MPL-SharedDir $settings.ContentFolder
        if (Test-Path -LiteralPath $sharedDir) {
            $done += "`n`nYour ticks and saved sets are kept in:`n$sharedDir`n(other computers using this folder still need them; delete it if none do)"
        }
    }
    if (MPL-Exists $library) { $done += "`n`nYour script library is still here, untouched:`n$library" }
    [void](Box $done)
    exit 0
}


# ==========================================================================
#  Install: the splash screen
# ==========================================================================
#  The banner, with the title, credits, licence and contact. Continue or Cancel.

function Show-Splash {
    $imagePath = Join-Path $AppFiles 'splash.png'
    if (-not (Test-Path -LiteralPath $imagePath)) { return $true }

    $splash = New-Object System.Windows.Forms.Form
    $splash.Text = "Install $Name"
    $splash.FormBorderStyle = 'None'
    $splash.StartPosition = 'CenterScreen'
    $splash.ClientSize = New-Object System.Drawing.Size(688, 384)
    $splash.ShowInTaskbar = $true
    try { $splash.Icon = New-Object System.Drawing.Icon (Join-Path $AppFiles 'MohoPowerLauncher.ico') } catch {}

    $picture = New-Object System.Windows.Forms.PictureBox
    $picture.Dock = 'Fill'
    $picture.SizeMode = 'StretchImage'
    $picture.Image = [System.Drawing.Image]::FromFile($imagePath)
    $splash.Controls.Add($picture)

    $ink = [System.Drawing.Color]::FromArgb(43, 26, 0)            # dark brown on the orange
    $linkInk = [System.Drawing.Color]::FromArgb(110, 20, 30)

    # Text sits on the picture (Parent = picture) so its background shows through
    function Add-Text([string]$text, [int]$top, [int]$height, [float]$size, [bool]$bold) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $text
        $label.Parent = $picture
        $label.BackColor = 'Transparent'
        $label.ForeColor = $ink
        $style = [System.Drawing.FontStyle]::Regular
        if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
        $label.Font = New-Object System.Drawing.Font('Segoe UI', $size, $style)
        $label.Location = New-Object System.Drawing.Point(300, $top)
        $label.Size = New-Object System.Drawing.Size(300, $height)
    }
    function Add-Link([string]$text, [string]$url, [int]$top) {
        $link = New-Object System.Windows.Forms.LinkLabel
        $link.Text = $text
        $link.Parent = $picture
        $link.BackColor = 'Transparent'
        $link.Tag = $url
        $link.LinkColor = $linkInk
        $link.ActiveLinkColor = $linkInk
        $link.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $link.Location = New-Object System.Drawing.Point(300, $top)
        $link.AutoSize = $true
        $link.Add_LinkClicked({ param($sender, $e) try { Start-Process ([string]$sender.Tag) } catch {} })
    }

    Add-Text $Name 78 40 20 $true
    Add-Text "Version $($MPL.Version)" 118 22 10 $false
    Add-Text 'By Cheesoid: Doug Craven, who designed it, and Claude, an AI model by Anthropic, who wrote the code.' 152 62 10 $false
    Add-Text 'Free for non-commercial use.' 218 22 10 $false
    Add-Link 'Licence: PolyForm Noncommercial 1.0.0' $LicenseUrl 242
    Add-Link $Email "mailto:$Email" 266

    $continue = New-Object System.Windows.Forms.Button
    $continue.Text = 'Continue'
    $continue.Parent = $picture
    $continue.Size = New-Object System.Drawing.Size(110, 32)
    $continue.Location = New-Object System.Drawing.Point(300, 320)
    $continue.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $continue.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Parent = $picture
    $cancel.Size = New-Object System.Drawing.Size(110, 32)
    $cancel.Location = New-Object System.Drawing.Point(418, 320)
    $cancel.DialogResult = 'Cancel'
    $splash.AcceptButton = $continue
    $splash.CancelButton = $cancel           # Esc cancels too

    $result = $splash.ShowDialog()
    $picture.Image.Dispose()                 # FromFile keeps the file open until disposed
    $splash.Dispose()
    return ($result -eq 'OK')
}


# ==========================================================================
#  Install: check the three places
# ==========================================================================
#  One window with Moho, the Custom Content Folder and the script library,
#  found automatically. Returns $null on Cancel, else @{ Desktop; StartNow }.

function Show-PlacesDialog($s, [bool]$updating) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Install $Name $($MPL.Version)"
    $dialog.StartPosition = 'CenterScreen'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $dialog.ClientSize = New-Object System.Drawing.Size(640, 390)
    try { $dialog.Icon = New-Object System.Drawing.Icon (Join-Path $AppFiles 'MohoPowerLauncher.ico') } catch {}

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(14, 12)
    $intro.Size = New-Object System.Drawing.Size(612, 44)
    $intro.Text = "Check these three places, then click Install. They were found automatically; Browse... changes one.`n" +
                  "In Moho, File > Open Custom Content Folder shows where yours is."
    $dialog.Controls.Add($intro)

    $rows = @(
        @{ Key = 'MohoPath';      Label = 'Moho program (Moho.exe):';                                         IsFile = $true  },
        @{ Key = 'ContentFolder'; Label = "Moho's Custom Content Folder (it holds the 'scripts' folder):";    IsFile = $false },
        @{ Key = 'MasterFolder';  Label = 'Your script library: one folder per script (made for you if new):'; IsFile = $false }
    )
    $boxes = @{}
    $y = 62
    foreach ($row in $rows) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $row.Label
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point(14, $y)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Text = [string]$s[$row.Key]
        $box.Location = New-Object System.Drawing.Point(14, ($y + 24))
        $box.Size = New-Object System.Drawing.Size(510, 26)

        $browse = New-Object System.Windows.Forms.Button
        $browse.Text = 'Browse...'
        $browse.Location = New-Object System.Drawing.Point(532, ($y + 22))
        $browse.Size = New-Object System.Drawing.Size(94, 30)
        $isFile = $row.IsFile
        $browse.Add_Click({
            if ($isFile) {
                $picker = New-Object System.Windows.Forms.OpenFileDialog
                $picker.Filter = 'Moho (Moho.exe)|Moho.exe|Programs (*.exe)|*.exe'
                if ($picker.ShowDialog() -eq 'OK') { $box.Text = $picker.FileName }
            } else {
                $picker = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($box.Text -and (Test-Path -LiteralPath $box.Text -ErrorAction SilentlyContinue)) { $picker.SelectedPath = $box.Text }
                if ($picker.ShowDialog() -eq 'OK') { $box.Text = $picker.SelectedPath }
            }
        }.GetNewClosure())

        $dialog.Controls.AddRange(@($label, $box, $browse))
        $boxes[$row.Key] = $box
        $y += 76
    }

    # The library follows the content folder, unless you've typed a library of your own
    $boxes.ContentFolder.Add_TextChanged({
        $content = $boxes.ContentFolder.Text.Trim()
        $library = $boxes.MasterFolder.Text
        $followsContent = ($library -eq '' -or $library -like '*\scripts master folder')
        if ($content -and $followsContent) {
            $boxes.MasterFolder.Text = $content.TrimEnd('\') + '\scripts master folder'
        }
    })

    $desktop = New-Object System.Windows.Forms.CheckBox
    $desktop.Text = 'Desktop shortcut'
    $desktop.AutoSize = $true
    $desktop.Checked = $true
    $desktop.Location = New-Object System.Drawing.Point(14, ($y + 4))
    $startNow = New-Object System.Windows.Forms.CheckBox
    $startNow.Text = 'Start it when done'
    $startNow.AutoSize = $true
    $startNow.Checked = $true
    $startNow.Location = New-Object System.Drawing.Point(180, ($y + 4))

    $ok = New-Object System.Windows.Forms.Button
    if ($updating) { $ok.Text = 'Update' } else { $ok.Text = 'Install' }
    $ok.Size = New-Object System.Drawing.Size(120, 34)
    $ok.Location = New-Object System.Drawing.Point(380, ($y + 44))
    $ok.DialogResult = 'OK'
    $ok.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Size = New-Object System.Drawing.Size(120, 34)
    $cancel.Location = New-Object System.Drawing.Point(506, ($y + 44))
    $cancel.DialogResult = 'Cancel'

    $dialog.Controls.AddRange(@($desktop, $startNow, $ok, $cancel))
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel

    if ($dialog.ShowDialog() -ne 'OK') { return $null }
    foreach ($key in $boxes.Keys) { $s[$key] = $boxes[$key].Text.Trim() }
    return @{ Desktop = $desktop.Checked; StartNow = $startNow.Checked }
}


# ==========================================================================
#  Install
# ==========================================================================

try {
    if (MPL-LauncherRunning) {
        [void](Box "$Name is open. Close its window, then run Install again." 'Warning')
        exit 1
    }
    if (-not (Show-Splash)) { exit 0 }

    # Files from the internet are marked "blocked": clear that so Windows lets them run quietly
    Get-ChildItem -LiteralPath $Download -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    # An update keeps your settings; anything missing is found automatically
    $S = MPL-LoadSettings
    $updating = Test-Path -LiteralPath (Join-Path $InstallDir 'MohoPowerLauncher.ps1')
    if (-not (MPL-Exists $S.MohoPath))      { $S.MohoPath = MPL-FindMoho }
    if (-not (MPL-Exists $S.ContentFolder)) { $S.ContentFolder = MPL-FindContentFolder }
    if (-not $S.MasterFolder -and $S.ContentFolder) { $S.MasterFolder = Join-Path $S.ContentFolder 'scripts master folder' }

    $choices = Show-PlacesDialog $S $updating
    if (-not $choices) { exit 0 }

    # ---------- check what was chosen ----------
    if (-not (MPL-Exists $S.MohoPath)) {
        $answer = Box "Moho.exe isn't at that path. Install anyway? (You can set it later in the launcher's Settings.)" 'Warning' 'YesNo'
        if ($answer -ne 'Yes') { exit 0 }
    }
    if (-not (MPL-Exists $S.ContentFolder)) {
        [void](Box "That Custom Content Folder doesn't exist:`n$($S.ContentFolder)`n`nIn Moho: File > Open Custom Content Folder shows where yours is. Nothing was installed." 'Error')
        exit 1
    }
    if (-not $S.MasterFolder) { $S.MasterFolder = Join-Path $S.ContentFolder 'scripts master folder' }
    $mohoReads = MPL-MohoContentFolder
    if (-not (MPL-SameFolder $mohoReads $S.ContentFolder)) {
        $answer = Box ("Moho is set to read scripts from:`n$mohoReads`n`nYou picked:`n$($S.ContentFolder)`n`n" +
                       "Moho won't see scripts put there. Use your pick anyway?") 'Warning' 'YesNo'
        if ($answer -ne 'Yes') { exit 0 }
    }

    # ---------- copy the program ----------
    if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    $runningFromInstall = (MPL-SameFolder $AppFiles $InstallDir)
    if (-not $runningFromInstall) {
        foreach ($file in (Get-ChildItem -LiteralPath $AppFiles -File)) {
            Copy-Item -LiteralPath $file.FullName -Destination $InstallDir -Force
        }
    }
    # 1.2.0: the program files got launcher-specific names; take out the old generic ones
    if (-not $runningFromInstall) {
        foreach ($old in @('Setup.ps1', 'InstallScript.ps1', 'SortToolbar.ps1')) {
            $oldPath = Join-Path $InstallDir $old
            if (Test-Path -LiteralPath $oldPath) { Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue }
        }
    }
    foreach ($extra in @('LICENSE', 'README.md')) {
        $path = Join-Path $Download $extra
        if ((Test-Path -LiteralPath $path) -and -not $runningFromInstall) { Copy-Item -LiteralPath $path -Destination $InstallDir -Force }
    }
    Get-ChildItem -LiteralPath $InstallDir -File | Unblock-File -ErrorAction SilentlyContinue

    # ---------- the script library ----------
    if (-not (Test-Path -LiteralPath $S.MasterFolder)) { New-Item -ItemType Directory -Path $S.MasterFolder -Force | Out-Null }
    $aboutFile = Join-Path $S.MasterFolder '_About this folder.txt'
    if (-not (Test-Path -LiteralPath $aboutFile)) {
        MPL-WriteText $aboutFile (
            "This is your Moho Power Launcher script library.`r`n`r`n" +
            "Each script lives in its own folder here. The launcher copies the ones you tick into Moho's`r`n" +
            "scripts folder when it starts Moho, and takes them out again when you untick them.`r`n`r`n" +
            "Add scripts with the launcher's 'Install script...' button. A label file (launcher.txt) in each`r`n" +
            "folder says which column and name it shows under:  Animate | Key Tools (AE)`r`n`r`n" +
            "Folders and files whose names start with _ are ignored.`r`n")
    }
    MPL-SaveSettings $S

    # ---------- shortcuts and the Installed apps entry ----------
    $launcher = Join-Path $InstallDir 'MohoPowerLauncher.ps1'
    $setup    = Join-Path $InstallDir 'MPL-Setup.ps1'
    if (-not (Test-Path -LiteralPath $StartMenu)) { New-Item -ItemType Directory -Path $StartMenu -Force | Out-Null }
    New-Shortcut (Join-Path $StartMenu "$Name.lnk") $launcher '' 'Choose your Moho scripts, then start Moho'
    # No Uninstall shortcut: Windows hides Start menu shortcuts named "Uninstall ..." by design.
    # Uninstalling is in Windows Settings > Apps > Installed apps (the entry below). 1.2.0 takes
    # out the hidden one older versions made.
    $oldUninstall = Join-Path $StartMenu "Uninstall $Name.lnk"
    if (Test-Path -LiteralPath $oldUninstall) { Remove-Item -LiteralPath $oldUninstall -Force -ErrorAction SilentlyContinue }
    if ($choices.Desktop) {
        New-Shortcut $DesktopLink $launcher '' 'Choose your Moho scripts, then start Moho'
    } elseif (Test-Path -LiteralPath $DesktopLink) {
        Remove-Item -LiteralPath $DesktopLink -Force
    }

    if (-not (Test-Path -Path $AppsEntry)) { New-Item -Path $AppsEntry -Force | Out-Null }
    $values = @{
        DisplayName     = $Name
        DisplayVersion  = $MPL.Version
        Publisher       = 'Cheesoid'
        DisplayIcon     = (Join-Path $InstallDir 'MohoPowerLauncher.ico')
        InstallLocation = $InstallDir
        UninstallString = "`"$PowerShell`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$setup`" -Uninstall"
        URLInfoAbout    = $RepoUrl
    }
    foreach ($key in $values.Keys) {
        New-ItemProperty -Path $AppsEntry -Name $key -Value $values[$key] -PropertyType String -Force | Out-Null
    }
    foreach ($key in @('NoModify', 'NoRepair')) {
        New-ItemProperty -Path $AppsEntry -Name $key -Value 1 -PropertyType DWord -Force | Out-Null
    }

    # ---------- done ----------
    if ($choices.StartNow) {
        Start-Process -FilePath $PowerShell -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$launcher`"")
    } else {
        $verb = 'installed'
        if ($updating) { $verb = 'updated' }
        $where = 'the Start menu'
        if ($choices.Desktop) { $where = 'the Start menu or the desktop' }
        [void](Box "$Name is $verb.`n`nStart it from $where.")
    }
} catch {
    [void](Box ("Setup didn't finish: " + $_.Exception.Message + "`n`nNothing in your Moho folders was changed.") 'Error')
    exit 1
}
