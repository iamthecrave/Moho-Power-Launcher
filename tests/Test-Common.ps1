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
Check 'applying 3 times gives 2 blocks, not 6' (@($list | Where-Object { $_ -eq $MPL.TBBegin }).Count -eq 2)
$i = [array]::IndexOf($list, "tool`tab_a_tool`t...")
Check 'A Tool listed as a tool, inside Bone' ($i -gt [array]::IndexOf($list, 'group MOHO.Localize("/Tools/Group/Bone=Bone")'))
Check 'ef_btn listed as a button' ($list -contains "button`tef_btn`t...")
Check 'new group name made safe' ($list -contains 'group MOHO.Localize("/Tools/Group/My-Stuff=My-Stuff")')

Write-Host "`n== launch 2: nothing ticked"
$r = MPL-Apply $S @(); Write-Host "  $r"; $t = MPL-ToolbarApply $S; Write-Host "  $t"
[void](Warnings)
Check 'launcher files removed' (-not (Has 'tool/ab_a_tool.lua') -and -not (Has 'menu/Extra/cd_menu_thing.lua'))
Check "user's own files still there" ((Has 'utility/shared.lua') -and (Has 'utility/common_util.lua'))
Check 'tool list it made is deleted' (-not (Has 'tool/_tool_list.txt'))
Check 'empty tool folder it made is deleted' (-not (Has 'tool'))
Check 'empty menu folders it made are deleted' (-not (Has 'menu'))

Write-Host "`n== an edited file becomes yours"
[void](MPL-Apply $S @($byKey['ab_a_tool']))
Add-Content (Join-Path $Scripts 'tool/ab_a_tool.lua') '-- my tweak'
[void](MPL-Apply $S @()); $w = Warnings
Check 'edited file kept' (Has 'tool/ab_a_tool.lua')
Check 'and warned' (@($w | Where-Object { $_ -like '*yours now*' }).Count -eq 1)
Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== your own tool list: blocks added, then removed byte for byte"
$own = $builtIn.Replace("`r`n", "`n") + "group MOHO.Localize(`"/Tools/Group/Mine=Mine`")`ntool`tmy_own`t...`n"
Put (Join-Path $Scripts 'tool/_tool_list.txt') $own
$before = (Get-FileHash (Join-Path $Scripts 'tool/_tool_list.txt')).Hash
[void](MPL-Apply $S @($byKey['ab_a_tool'])); [void](MPL-ToolbarApply $S)
Check 'block added to your list' ((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains $MPL.TBBegin)
Check 'your own line kept' ((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains "tool`tmy_own`t...")
$msg = MPL-RemoveAll $S; Write-Host "  $msg"
Check 'your list restored exactly (LF endings kept)' ((Get-FileHash (Join-Path $Scripts 'tool/_tool_list.txt')).Hash -eq $before)
Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== the launcher's own list, edited by you, is not deleted"
[void](MPL-Apply $S @($byKey['ab_a_tool'])); [void](MPL-ToolbarApply $S)
Add-Content (Join-Path $Scripts 'tool/_tool_list.txt') '/* my note */'
[void](MPL-Apply $S @()); [void](MPL-ToolbarApply $S)
Check 'edited list kept' (Has 'tool/_tool_list.txt')
Check 'your note kept, launcher blocks gone' (((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains '/* my note */') -and -not ((Get-Content (Join-Path $Scripts 'tool/_tool_list.txt')) -contains $MPL.TBBegin))
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
Check 'warned, and broken file kept' ((@($w | Where-Object { $_ -like '*could not be read*' }).Count -ge 1) -and (@(Get-ChildItem $MPL.DataDir -Filter 'installed.broken-*').Count -eq 1))
Remove-Item $MPL.Record; Remove-Item (Join-Path $Scripts 'tool') -Recurse -Force

Write-Host "`n== content folder changed: old one cleaned"
[void](MPL-Apply $S @($byKey['ab_a_tool'], $byKey['cd_menu_thing']))
$S2 = MPL-LoadSettings; foreach ($k in @($S.Keys)) { $S2[$k] = $S[$k] }
$S2.ContentFolder = Join-Path $Root 'content2'; New-Item -ItemType Directory $S2.ContentFolder | Out-Null
[void](MPL-Apply $S2 @($byKey['ab_a_tool']))
Check 'old folder: launcher files gone' (-not (Has 'tool/ab_a_tool.lua') -and -not (Has 'menu/Extra/cd_menu_thing.lua'))
Check "old folder: user's files stay" ((Has 'utility/shared.lua') -and (Has 'menu/Extra'))
Check 'new folder has the ticked script' (Test-Path (Join-Path $S2.ContentFolder 'scripts/tool/ab_a_tool.lua'))

Write-Host "`n== log"
MPL-Log 'tést'; MPL-SaveLog
Check 'log written as UTF-8' ((Get-Content $MPL.Log -Encoding UTF8 | Select-Object -Last 1) -like '*tést')

Remove-Item $Root -Recurse -Force
Write-Host ''
if ($script:fails) { Write-Host "$($script:fails) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASSED' }
