# #10 tests: a script copy in Moho the launcher didn't install, with a different library version.
$ErrorActionPreference = 'Stop'
$Root = Join-Path ([IO.Path]::GetTempPath()) ('mplr_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $Root | Out-Null
$env:LOCALAPPDATA = Join-Path $Root 'lad'; $env:APPDATA = Join-Path $Root 'ad'
. (Join-Path $PSScriptRoot '../app/MPL-Common.ps1')
$script:fails = 0
function Check([string]$what, [bool]$ok) { if ($ok) { Write-Host "  PASS  $what" } else { Write-Host "  FAIL  $what"; $script:fails++ } }
function Put([string]$p, [string]$t) { New-Item -ItemType Directory (Split-Path -Parent $p) -Force | Out-Null; [IO.File]::WriteAllText($p, $t) }
function Body($rel) { (Get-Content -Raw (Join-Path $Scripts $rel)).Trim() }
$Moho = Join-Path $Root 'Moho/Moho.exe'; Put $Moho ''
$Content = Join-Path $Root 'content'; $Scripts = Join-Path $Content 'scripts'; $Lib = Join-Path $Content 'scripts master folder'
$P = Join-Path $Lib 'zz_tool_for-moho-install-script-command'
$Q = Join-Path $Lib 'yy_tool_for-moho-install-script-command'
Put (Join-Path $P 'tool/zz_tool.lua') '-- v1.3'
Put (Join-Path $Q 'tool/yy_tool.lua') '-- v1.3'
Put (Join-Path $Scripts 'tool/yy_tool.lua') '-- v1.3'
$S = MPL-LoadSettings; $S.MohoPath = $Moho; $S.ContentFolder = $Content; $S.MasterFolder = $Lib
[void](MPL-Apply $S @(MPL-ReadMaster $S))
Check 'first launch: identical copy, no question' ($script:MPLConflicts.Count -eq 0)
Put (Join-Path $P 'tool/zz_tool.lua') '-- v1.5'
Put (Join-Path $Q 'tool/yy_tool.lua') '-- v1.5'
[void](MPL-Apply $S @(MPL-ReadMaster $S))
Check 'launcher-installed script updated' ((Body 'tool/zz_tool.lua') -eq '-- v1.5')
Check 'other copy: one question, nothing changed yet' ($script:MPLConflicts.Count -eq 1 -and (Body 'tool/yy_tool.lua') -eq '-- v1.3')
# "No": keep mine
MPL-KeepMine $S $script:MPLConflicts.ToArray(); $script:MPLConflicts.Clear()
$S = MPL-LoadSettings; $S.MohoPath = $Moho; $S.ContentFolder = $Content; $S.MasterFolder = $Lib
[void](MPL-Apply $S @(MPL-ReadMaster $S))
Check 'kept mine: not asked again, copy unchanged' ($script:MPLConflicts.Count -eq 0 -and (Body 'tool/yy_tool.lua') -eq '-- v1.3')
Put (Join-Path $Q 'tool/yy_tool.lua') '-- v1.6'
[void](MPL-Apply $S @(MPL-ReadMaster $S))
Check 'newer library version asks again' ($script:MPLConflicts.Count -eq 1)
# "Yes": replace
$n = MPL-Replace $S $script:MPLConflicts.ToArray(); $script:MPLConflicts.Clear()
Check 'replaced with library version' ($n -eq 1 -and (Body 'tool/yy_tool.lua') -eq '-- v1.6')
$bk = @(Get-ChildItem -Recurse -File (Join-Path $Lib '_backups') -Filter 'yy_tool_replaced_*')
Check 'old copy backed up first' ($bk.Count -eq 1 -and (Get-Content -Raw $bk[0].FullName).Trim() -eq '-- v1.3')
Put (Join-Path $Q 'tool/yy_tool.lua') '-- v1.7'
[void](MPL-Apply $S @(MPL-ReadMaster $S))
Check 'after replacing, later updates install by themselves' ($script:MPLConflicts.Count -eq 0 -and (Body 'tool/yy_tool.lua') -eq '-- v1.7')
[void](MPL-Apply $S @())
Check 'unticked: launcher now removes it' (-not (Test-Path (Join-Path $Scripts 'tool/yy_tool.lua')))
Remove-Item -Recurse -Force $Root
if ($script:fails) { Write-Host "$($script:fails) FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
