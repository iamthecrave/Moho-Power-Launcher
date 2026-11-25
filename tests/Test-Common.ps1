# Tests for MPL-Common.ps1. Builds a fresh fake Moho setup in a temp folder each run.
# Run:  pwsh -NoProfile -File Test-Common.ps1
$ErrorActionPreference = 'Stop'
$Root = Join-Path ([IO.Path]::GetTempPath()) ('mpltest_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $Root | Out-Null
$env:LOCALAPPDATA = Join-Path $Root 'localappdata'
$env:APPDATA      = Join-Path $Root 'appdata'
. (Join-Path $PSScriptRoot '../app/MPL-Common.ps1')

$script:fails = 0
function Check([string]$what, [bool]$ok) {
    if ($ok) { Write-Host "  PASS  $what" } else { Write-Host "  FAIL  $what" -ForegroundColor Red; $script:fails++ }
}
function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text)
}
function Has([string]$rel) { Test-Path -LiteralPath (Join-Path $Scripts $rel) }
function Warnings { $w = @($script:MPLWarnings); $script:MPLWarnings.Clear(); return $w }

# ---------- the fake setup ----------
$Moho    = Join-Path $Root 'Program Files/Moho 14/Moho.exe'
Put $Moho ''
$builtIn = "/* built in */`r`ngroup MOHO.Localize(`"/Tools/Group/Draw=Draw`")`r`ntool`tlm_select_points`t...`r`n`r`ngroup MOHO.Localize(`"/Tools/Group/Bone=Bone`")`r`ntool`tlm_select_bone`t...`r`n"
Put (Join-Path $Root 'Program Files/Moho 14/Resources/Support/Scripts/Tool/_tool_list.txt') $builtIn
$Content = Join-Path $Root 'content'
$Scripts = Join-Path $Content 'scripts'
$Lib     = Join-Path $Content 'scripts master folder'

Put (Join-Path $Scripts 'utility/shared.lua') '-- the user''s own shared file'
Put (Join-Path $Scripts 'utility/common_util.lua') '-- common util v1'          # same as the packages' copy

$A = Join-Path $Lib 'ab_a_tool_for-moho-install-script-command'
Put (Join-Path $A 'wrapper/tool/ab_a_tool.lua') 'function AB:OnMouseDown() end'
Put (Join-Path $A 'wrapper/tool/ab_a_tool.png') 'png'
Put (Join-Path $A 'wrapper/utility/shared.lua') '-- a different shared file'
Put (Join-Path $A 'wrapper/readme.txt') 'readme'
Put (Join-Path $A 'launcher.txt') 'Rig | A Tool (AB)'
$B = Join-Path $Lib 'moho-script_cd_menu_thing'
Put (Join-Path $B 'menu/Extra/cd_menu_thing.lua') '-- menu'
[IO.File]::WriteAllText((Join-Path $B 'launcher.txt'), "Animate | Menü Thing", (New-Object Text.UTF8Encoding($false)))
$C = Join-Path $Lib 'ef_btn'
Put (Join-Path $C 'tool/ef_btn.lua') '-- a button'
Put (Join-Path $C 'utility/common_util.lua') '-- common util v1'
Put (Join-Path $Lib 'loose_one.lua') '-- loose'
Put (Join-Path $Lib '_archive/old/tool/old.lua') '-- ignored'

$S = MPL-LoadSettings
$S.MohoPath = $Moho; $S.ContentFolder = $Content; $S.MasterFolder = $Lib

Write-Host "`n== helpers"
Check 'MPL-Exists is false for empty, null and missing' ((-not (MPL-Exists '')) -and (-not (MPL-Exists $null)) -and (-not (MPL-Exists (Join-Path $Root 'nope'))))
Check 'MPL-SameFolder ignores case and trailing slash' (MPL-SameFolder '/tmp/A/b/' '/tmp/A/b')
Check 'MPL-GroupName makes names safe' ((MPL-GroupName 'My "Cool" = Tools') -eq 'My-Cool-Tools')
Check 'data folder not made just by loading' (-not (Test-Path $MPL.DataDir))

Write-Host "`n== reading the library"
$items = @(MPL-ReadMaster $S)
$byKey = @{}; foreach ($i in $items) { $byKey[$i.Key] = $i }
Check 'four packages, _archive ignored' ($items.Count -eq 4)
Check 'label read: Rig | A Tool (AB)' ($byKey['ab_a_tool'].Group -eq 'Rig' -and $byKey['ab_a_tool'].Name -eq 'A Tool (AB)')
Check 'UTF-8 label name survives' ($byKey['cd_menu_thing'].Name -eq 'Menü Thing')
Check 'no label -> Unsorted' ($byKey['ef_btn'].Group -eq 'Unsorted')
Check 'loose .lua found' ($byKey['loose_one'].Loose)

Write-Host "`n== launch 1: everything ticked"
$r = MPL-Apply $S $items; Write-Host "  $r"
$w = Warnings
Check 'tool copied (wrapper folder found)' (Has 'tool/ab_a_tool.lua')
Check 'readme at package top not copied' (-not (Has 'readme.txt'))
Check 'menu subfolder copied' (Has 'menu/Extra/cd_menu_thing.lua')
Check 'loose .lua goes to menu/Downloaded' (Has 'menu/Downloaded/loose_one.lua')
Check "user's different shared.lua kept" ((Get-Content (Join-Path $Scripts 'utility/shared.lua')) -eq '-- the user''s own shared file')
Check 'warned about the kept shared.lua' (@($w | Where-Object { $_ -like '*shared.lua*' }).Count -eq 1)
$rec = MPL-LoadRecord
Check 'identical file already there is NOT taken over' (-not $rec.Files.ContainsKey('utility/common_util.lua'))
Check 'record lists the copied files' ($rec.Files.ContainsKey('tool/ab_a_tool.lua'))
Check 'data folder made on first save' (Test-Path $MPL.DataDir)

$t = MPL-ToolbarApply $S; Write-Host "  $t"
Check 'no map: tool list not written' (-not (Has 'tool/_tool_list.txt'))

Write-Host "`n== toolbar: A Tool in Bone, button in a new group with an unsafe name"
MPL-SaveToolbarMap ([ordered]@{ 'Bone' = @('ab_a_tool'); 'My Stuff!' = @('ef_btn') })
1..3 | ForEach-Object { [void](MPL-ToolbarApply $S) }
$list = Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')
Check 'applying 3 times adds each tool once' ((@($list | Where-Object { $_ -eq "tool`tab_a_tool`t..." }).Count -eq 1) -and (@($list | Where-Object { $_ -like '*My-Stuff*' }).Count -eq 1))
Check 'no comment markers written (#3: Moho-proven format)' (@($list | Where-Object { $_ -like '/`* Moho Power Launcher*' }).Count -eq 0)
$h = [array]::IndexOf($list, 'group MOHO.Localize("/Tools/Group/My-Stuff=My-Stuff")')
Check 'new group has a blank line before it, then its tool' (($list[$h - 1] -eq '') -and ($list[$h + 1] -eq "button`tef_btn`t..."))
$i = [array]::IndexOf($list, "tool`tab_a_tool`t...")
Check 'A Tool listed as a tool, inside Bone' ($i -gt [array]::IndexOf($list, 'group MOHO.Localize("/Tools/Group/Bone=Bone")'))
Check 'ef_btn listed as a button' ($list -contains "button`tef_btn`t...")
Check 'new group name made safe' ($list -contains 'group MOHO.Localize("/Tools/Group/My-Stuff=My-Stuff")')

Write-Host "`n== #3: a group with several tools, saved and read back"
MPL-SaveToolbarMap ([ordered]@{ 'Several' = @('nothing_here', 'ab_a_tool', 'ef_btn') })
$back = MPL-LoadToolbarMap
Check 'read back as three separate names' ((@($back['Several']).Count -eq 3) -and (@($back['Several'])[1] -eq 'ab_a_tool'))
[void](MPL-ToolbarApply $S)
$list = Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')
$h = [array]::IndexOf($list, 'group MOHO.Localize("/Tools/Group/Several=Several")')
Check 'both tools land in the group, in order' (($h -ge 0) -and ($list[$h + 1] -eq "tool`tab_a_tool`t...") -and ($list[$h + 2] -eq "button`tef_btn`t..."))
Check 'old groups taken out when the map changes' (@($list | Where-Object { $_ -like '*My-Stuff*' }).Count -eq 0)

Write-Host "`n== #3: a tool saved in two groups goes in the last one only"
MPL-SaveToolbarMap ([ordered]@{ 'First' = @('ab_a_tool', 'ef_btn'); 'Second' = @('ab_a_tool') })
$back = MPL-LoadToolbarMap
Check 'kept in Second, dropped from First' ((@($back['Second']) -contains 'ab_a_tool') -and -not (@($back['First']) -contains 'ab_a_tool') -and (@($back['First']) -contains 'ef_btn'))

Write-Host "`n== launch 2: nothing ticked"
$r = MPL-Apply $S @(); Write-Host "  $r"; $t = MPL-ToolbarApply $S; Write-Host "  $t"
[void](Warnings)
Check 'launcher files removed' (-not (Has 'tool/ab_a_tool.lua') -and -not (Has 'menu/Extra/cd_menu_thing.lua'))
Check "user's own files still there" ((Has 'utility/shared.lua') -and (Has 'utility/common_util.lua'))
Check 'tool list it made is deleted' (-not (Has 'tool/_tool_list.txt'))
Check 'empty tool folder it made is deleted' (-not (Has 'tool'))
Check 'empty menu folders it made are deleted' (-not (Has 'menu'))

Write-Host "`n== an edited file whose package is gone becomes yours"
[void](MPL-Apply $S @($byKey['ab_a_tool']))
Add-Content (Join-Path $Scripts 'tool/ab_a_tool.lua') '-- my tweak'
$recX = MPL-LoadRecord; $recX.Files['tool/ab_a_tool.lua'].Key = 'gone'; $recX.Files['tool/ab_a_tool.lua'].Package = 'Gone'; MPL-SaveRecord $recX
[void](MPL-Apply $S @()); $w = Warnings
Check 'edited file kept' (Has 'tool/ab_a_tool.lua')
Check 'and warned' (@($w | Where-Object { $_ -like '*yours now*' }).Count -eq 1)
Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== your own tool list: blocks added, then removed byte for byte"
$own = $builtIn.Replace("`r`n", "`n") + "group MOHO.Localize(`"/Tools/Group/Mine=Mine`")`ntool`tmy_own`t...`n"
Put (Join-Path $Scripts 'tool/_tool_list.txt') $own
$before = (Get-FileHash (Join-Path $Scripts 'tool/_tool_list.txt')).Hash
[void](MPL-Apply $S @($byKey['ab_a_tool'])); [void](MPL-ToolbarApply $S)
Check 'tool added to your list' ((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains "tool`tab_a_tool`t...")
Check 'your own line kept' ((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains "tool`tmy_own`t...")
$msg = MPL-RemoveAll $S; Write-Host "  $msg"
Check 'your list restored exactly (LF endings kept)' ((Get-FileHash (Join-Path $Scripts 'tool/_tool_list.txt')).Hash -eq $before)
Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== the launcher's own list, edited by you, is not deleted"
[void](MPL-Apply $S @($byKey['ab_a_tool'])); [void](MPL-ToolbarApply $S)
Add-Content (Join-Path $Scripts 'tool/_tool_list.txt') '/* my note */'
[void](MPL-Apply $S @()); [void](MPL-ToolbarApply $S)
Check 'edited list kept' (Has 'tool/_tool_list.txt')
Check 'your note kept, launcher lines gone' (((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains '/* my note */') -and -not ((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains "tool`tab_a_tool`t..."))
Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== Adopt: handing over a script you installed yourself"
Put (Join-Path $Scripts 'menu/Extra/cd_menu_thing.lua') '-- menu'
MPL-Adopt $S 'Menu Thing' @(@{ Src = (Join-Path $B 'menu/Extra/cd_menu_thing.lua'); Rel = 'menu/Extra/cd_menu_thing.lua' })
[void](MPL-Apply $S @())
Check 'adopted file removed when unticked' (-not (Has 'menu/Extra/cd_menu_thing.lua'))
Check 'folder it did not make is kept' (Has 'menu/Extra')

Write-Host "`n== broken record: nothing removed"
[void](MPL-Apply $S @($byKey['ab_a_tool']))
'{ broken' | Set-Content $MPL.Record
[void](MPL-Apply $S @()); $w = Warnings
Check 'file not removed' (Has 'tool/ab_a_tool.lua')
Check 'warned, and broken file kept' ((@($w | Where-Object { $_ -like '*could not be read*' }).Count -ge 1) -and (@(Get-ChildItem (Split-Path $MPL.Record) -Filter 'installed.broken-*').Count -eq 1))
Remove-Item $MPL.Record; Get-ChildItem (Split-Path $MPL.Record) -Filter 'installed.broken-*' | Remove-Item
Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== content folder changed: old one cleaned"
[void](MPL-Apply $S @($byKey['ab_a_tool'], $byKey['cd_menu_thing']))
$S2 = MPL-LoadSettings; foreach ($k in @($S.Keys)) { $S2[$k] = $S[$k] }
$S2.ContentFolder = Join-Path $Root 'content2'; New-Item -ItemType Directory $S2.ContentFolder | Out-Null
[void](MPL-Apply $S2 @($byKey['ab_a_tool']))
Check 'old folder: launcher files gone' (-not (Has 'tool/ab_a_tool.lua') -and -not (Has 'menu/Extra/cd_menu_thing.lua'))
Check "old folder: user's files stay" ((Has 'utility/shared.lua') -and (Has 'menu/Extra'))
Check 'new folder has the ticked script' (Test-Path (Join-Path $S2.ContentFolder 'scripts/tool/ab_a_tool.lua'))

Write-Host "`n== #6: shared data lives in the content folder"
$sharedDir = Join-Path $S2.ContentFolder 'Moho Power Launcher'
Check 'record is in the content folder' (Test-Path (Join-Path $sharedDir 'installed.json'))
Check 'choices.json is there, this computer keeps only paths' ((Test-Path (Join-Path $sharedDir 'choices.json')) -and -not ((Get-Content $MPL.Settings -Raw) -match 'Selected'))

Write-Host "`n== #6: a second computer removes what the first one installed"
$machineA = @{ DataDir = $MPL.DataDir; Settings = $MPL.Settings; Log = $MPL.Log }
$MPL.DataDir = Join-Path $Root 'computerB'; $MPL.Settings = Join-Path $MPL.DataDir 'settings.json'; $MPL.Log = Join-Path $MPL.DataDir 'log.txt'
$SB = MPL-LoadSettings; $SB.MohoPath = $Moho; $SB.ContentFolder = $S2.ContentFolder; $SB.MasterFolder = $Lib
[void](MPL-Apply $SB @())
Check 'computer B unticked it: gone' (-not (Test-Path (Join-Path $S2.ContentFolder 'scripts/tool/ab_a_tool.lua')))

Write-Host "`n== #6: a fresh install on a second computer keeps the shared choices"
$cA = MPL-LoadSettings; $cA.ContentFolder = $S2.ContentFolder; $cA.Selected = @('ab_a_tool'); $cA['__ChoicesFrom'] = (Join-Path $S2.ContentFolder 'Moho Power Launcher'); MPL-SaveSettings $cA
Remove-Item $MPL.Settings -ErrorAction SilentlyContinue
$fresh = MPL-LoadSettings; $fresh.ContentFolder = $S2.ContentFolder; MPL-SaveSettings $fresh      # what Setup does
$again = MPL-LoadSettings
Check 'shared ticks not wiped by the new computer' (@($again.Selected) -contains 'ab_a_tool')

Write-Host "`n== #6: updating from 1.0.0 moves this computer's data into the shared folder"
$MPL.DataDir = Join-Path $Root 'computerC'; $MPL.Settings = Join-Path $MPL.DataDir 'settings.json'; $MPL.Log = Join-Path $MPL.DataDir 'log.txt'
$C3 = Join-Path $Root 'content3'; New-Item -ItemType Directory (Join-Path $C3 'scripts/tool') -Force | Out-Null
Put (Join-Path $C3 'scripts/tool/old_tool.lua') '-- put there by 1.0.0'
$oldHash = (Get-FileHash (Join-Path $C3 'scripts/tool/old_tool.lua')).Hash
$legacyList = $builtIn + "/* Moho Power Launcher: begin */`r`n`r`ngroup MOHO.Localize(`"/Tools/Group/Old=Old`")`r`ntool`told_tool`t...`r`n/* Moho Power Launcher: end */`r`n"
Put (Join-Path $C3 'scripts/tool/_tool_list.txt') $legacyList
New-Item -ItemType Directory $MPL.DataDir | Out-Null
@{ MohoPath = $Moho; ContentFolder = $C3; MasterFolder = $Lib; Selected = @('ab_a_tool'); Configurations = @{ 'My Set' = @('ab_a_tool') } } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MPL.DataDir 'settings.json')
@{ ScriptsFolder = (Join-Path $C3 'scripts'); Files = @{ 'tool/old_tool.lua' = @{ Rel = 'tool/old_tool.lua'; Hash = $oldHash; Package = 'Old' } }; Dirs = @(); ToolListCreated = $false } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MPL.DataDir 'installed.json')
@{ Groups = @(@{ Name = 'Old'; Tools = @('old_tool') }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MPL.DataDir 'toolbar.json')
$up = MPL-LoadSettings
$shared3 = Join-Path $C3 'Moho Power Launcher'
Check 'record moved to the shared folder' ((Test-Path (Join-Path $shared3 'installed.json')) -and (Test-Path (Join-Path $MPL.DataDir 'installed.moved.json')))
Check 'toolbar groups moved' (Test-Path (Join-Path $shared3 'toolbar.json'))
Check 'ticks and saved sets moved' (((Get-Content (Join-Path $shared3 'choices.json') -Raw) -match 'My Set') -and (@($up.Selected) -contains 'ab_a_tool'))
[void](MPL-Apply $up @()); [void](MPL-ToolbarApply $up)
Check "1.0.0's file still removed after the move" (-not (Test-Path (Join-Path $C3 'scripts/tool/old_tool.lua')))
$listNow = Get-Content (Join-Path $C3 'scripts/tool/_tool_list.txt') -Raw
Check "1.0.0's marked block taken out of the tool list" ($listNow -eq $builtIn)

Write-Host "`n== content folder switched on this computer: the old one is tidied"
$up = MPL-LoadSettings
[void](MPL-Apply $up @($byKey['ab_a_tool']))
Check 'installed in content3' (Test-Path (Join-Path $C3 'scripts/tool/ab_a_tool.lua'))
$up.ContentFolder = $S2.ContentFolder
[void](MPL-Apply $up @())
Check 'switching folders took it out of content3' (-not (Test-Path (Join-Path $C3 'scripts/tool/ab_a_tool.lua')))
$MPL.DataDir = $machineA.DataDir; $MPL.Settings = $machineA.Settings; $MPL.Log = $machineA.Log

Write-Host "`n== scripts installed through Moho join the launcher by themselves"
$S4 = MPL-LoadSettings; $S4.ContentFolder = $S2.ContentFolder; $S4.MasterFolder = $Lib; $S4.MohoPath = $Moho
$sc4 = Join-Path $S4.ContentFolder 'scripts'
Put (Join-Path $sc4 'tool/zz_moho_made.lua') 'function ZZ:OnMouseDown() end'
Put (Join-Path $sc4 'tool/zz_moho_made.png') 'icon'
Put (Join-Path $sc4 'ScriptResources/zz_moho_made/thing.png') 'res'
Put (Join-Path $sc4 'menu/Mine/wip_script.lua') '-- work in progress'
$found = @(MPL-FindMohoInstalled $S4)
Check 'both found' (($found.Name -contains 'zz_moho_made') -and ($found.Name -contains 'wip_script'))
$added = @(MPL-AddMohoInstalled $S4 $found)
$S4 = MPL-LoadSettings
$pkg = Join-Path $Lib 'zz_moho_made_for-moho-install-script-command'
Check 'package made with script, icon, resources and Unsorted label' ((Test-Path (Join-Path $pkg 'tool/zz_moho_made.lua')) -and (Test-Path (Join-Path $pkg 'tool/zz_moho_made.png')) -and (Test-Path (Join-Path $pkg 'ScriptResources/zz_moho_made/thing.png')) -and ((MPL-ReadLabel $pkg).Column -eq 'Unsorted'))
Check 'added ticked' ((@($S4.Selected) -contains 'zz_moho_made') -and (@($S4.Selected) -contains 'wip_script'))
Check 'not found again' (@(MPL-FindMohoInstalled $S4).Count -eq 0)
$items4 = @(MPL-ReadMaster $S4)
[void](MPL-Apply $S4 @($items4 | Where-Object { @($S4.Selected) -contains $_.Key }))
Check 'nothing left Moho at the next launch' ((Test-Path (Join-Path $sc4 'tool/zz_moho_made.lua')) -and (Test-Path (Join-Path $sc4 'menu/Mine/wip_script.lua')))

Write-Host "`n== Not these: left alone for good"
MPL-LeaveAlone $S4 @($added | Where-Object { $_.Key -eq 'wip_script' })
$S4 = MPL-LoadSettings
Check 'its library copy is gone, the original stays in Moho' ((-not (Test-Path (Join-Path $Lib 'wip_script_for-moho-install-script-command'))) -and (Test-Path (Join-Path $sc4 'menu/Mine/wip_script.lua')))
Check 'not ticked, not managed' ((@($S4.Selected) -notcontains 'wip_script') -and -not ((MPL-LoadRecord).Files.ContainsKey('menu/mine/wip_script.lua')))
Check 'never offered again' (@(MPL-FindMohoInstalled $S4).Count -eq 0)
[void](MPL-Apply $S4 @())
Check 'unticking everything leaves it alone' (Test-Path (Join-Path $sc4 'menu/Mine/wip_script.lua'))
$items4 = @(MPL-ReadMaster $S4)
[void](MPL-Apply $S4 @($items4 | Where-Object { $_.Key -eq 'zz_moho_made' }))

Write-Host "`n== an edit in Moho's scripts folder is saved back to the library"
Add-Content (Join-Path $sc4 'tool/zz_moho_made.lua') '-- my edit'
$script:MPLNotes.Clear(); [void](Warnings)
[void](MPL-Apply $S4 @($items4 | Where-Object { $_.Key -eq 'zz_moho_made' }))
$w = Warnings
Check 'library copy now has the edit' ((Get-Content (Join-Path $pkg 'tool/zz_moho_made.lua') -Raw) -match 'my edit')
Check 'old library version backed up' (@(Get-ChildItem (Join-Path $Lib '_backups') -Recurse -Filter 'zz_moho_made_before-your-edit_*').Count -eq 1)
Check 'a note, no warning' ((@($script:MPLNotes) -join ' ') -match 'Saved your changes' -and $w.Count -eq 0)
[void](MPL-Apply $S4 @())
Check 'unticked: removed from Moho (the edit is safe in the library)' (-not (Test-Path (Join-Path $sc4 'tool/zz_moho_made.lua')))
[void](MPL-Apply $S4 @($items4 | Where-Object { $_.Key -eq 'zz_moho_made' }))
Check 'ticked again: your edited version comes back' ((Get-Content (Join-Path $sc4 'tool/zz_moho_made.lua') -Raw) -match 'my edit')

Write-Host "`n== both changed: nothing overwritten, both kept"
Add-Content (Join-Path $sc4 'tool/zz_moho_made.lua') '-- edit two'
Add-Content (Join-Path $pkg 'tool/zz_moho_made.lua') '-- newer download'
[void](MPL-Apply $S4 @($items4 | Where-Object { $_.Key -eq 'zz_moho_made' }))
$w = Warnings
Check 'your edit stays in Moho' ((Get-Content (Join-Path $sc4 'tool/zz_moho_made.lua') -Raw) -match 'edit two')
Check 'library keeps the newer version' ((Get-Content (Join-Path $pkg 'tool/zz_moho_made.lua') -Raw) -match 'newer download')
Check 'your edit also backed up, and warned' ((@(Get-ChildItem (Join-Path $Lib '_backups') -Recurse -Filter 'zz_moho_made_your-edit_*').Count -eq 1) -and (($w -join ' ') -match 'Both are kept'))
Check '_backups is not shown as a script' (@(MPL-ReadMaster $S4 | Where-Object { $_.Key -like '*backup*' }).Count -eq 0)

Write-Host "`n== log"
MPL-Log 'tést'; MPL-SaveLog
Check 'log written as UTF-8' ((Get-Content $MPL.Log -Encoding UTF8 | Select-Object -Last 1) -like '*tést')

Remove-Item $Root -Recurse -Force
Write-Host ''
if ($script:fails) { Write-Host "$($script:fails) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASSED' }
