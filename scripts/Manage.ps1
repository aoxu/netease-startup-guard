param(
 [Parameter(Mandatory=$true)][ValidateSet('Inspect','Install','Status','Verify','Uninstall')][string]$Action,
 [Parameter(Mandatory=$true)][string]$ExpectedSid,
 [string]$ExePath, [string]$ExpectedCommand,
 [string]$RuntimeDirectory = (Join-Path $env:LOCALAPPDATA 'Codex\NetEaseStartupGuard')
)
. "$PSScriptRoot\Common.ps1"
$RuntimeDirectory=[IO.Path]::GetFullPath($RuntimeDirectory).TrimEnd('\')
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
if($id.User.Value -ne $ExpectedSid){throw 'Wrong Windows account; use the verified interactive SID.'}
$taskName='Codex-NetEaseStartupGuard-'+$ExpectedSid
$runPath='Software\Microsoft\Windows\CurrentVersion\Run'
$approvedPath='Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$configFile=Join-Path $RuntimeDirectory 'config.json'
$backupFile=Join-Path $RuntimeDirectory 'backup.json'
function Get-GuardStatus {
 $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 [pscustomobject]@{Account=$id.Name;Sid=$ExpectedSid;Runtime=$RuntimeDirectory;TaskName=$taskName;State=if($task){[string]$task.State}else{'Absent'};Run=(Save-Value $runPath 'cloudmusic');Approval=(Save-Value $approvedPath 'cloudmusic');Heartbeat=if(Test-Path "$RuntimeDirectory\heartbeat.json"){Read-Json "$RuntimeDirectory\heartbeat.json"}else{$null}}
}
if($Action -eq 'Inspect') {
 $candidates=@(@("$env:ProgramFiles\NetEase\CloudMusic\cloudmusic.exe", "${env:ProgramFiles(x86)}\NetEase\CloudMusic\cloudmusic.exe", "$env:LOCALAPPDATA\NetEase\CloudMusic\cloudmusic.exe") | Where-Object {Test-Path -LiteralPath $_})
 $candidates+=@(Get-Process cloudmusic -ErrorAction SilentlyContinue | ForEach-Object {$_.Path} | Where-Object {$_})
 [pscustomobject]@{Status=(Get-GuardStatus);ExeCandidates=@($candidates|Select-Object -Unique);OtherGuardTasks=@(Get-ScheduledTask|Where-Object TaskName -match 'NetEaseStartupGuard'|Select-Object TaskName,State)}|ConvertTo-Json -Depth 8
 return
}
if($Action -eq 'Status'){Get-GuardStatus|ConvertTo-Json -Depth 8;return}
if($Action -eq 'Install') {
 if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){
  if(-not(Test-Path $configFile)){throw 'Task name collision; no matching runtime configuration.'}
  Get-GuardStatus|ConvertTo-Json -Depth 8;return
 }
 if(Get-ScheduledTask -TaskName 'NetEaseStartupGuard' -ErrorAction SilentlyContinue){throw 'Legacy guard exists. Inspect and migrate explicitly; do not stack guards.'}
 if(-not $ExePath -or -not(Test-Path -LiteralPath $ExePath -PathType Leaf)){throw 'Provide a verified existing cloudmusic.exe path.'}
 $ExePath=(Get-Item -LiteralPath $ExePath).FullName
 if([IO.Path]::GetFileName($ExePath) -ine 'cloudmusic.exe'){throw 'Not cloudmusic.exe'}
 $existing=Save-Value $runPath 'cloudmusic'
 if(-not $ExpectedCommand){
  if($existing.Exists){throw 'Existing autorun entry: inspect and explicitly supply ExpectedCommand.'}
  $ExpectedCommand='"'+$ExePath+'" --orpheus-startup=autorun'
 }
 $match=[regex]::Match($ExpectedCommand,'^\s*"(?<exe>[^"]+)"\s+--orpheus-startup=autorun\s*$')
 if(-not $match.Success -or $match.Groups['exe'].Value -ine $ExePath){throw 'Only the verified quoted executable plus --orpheus-startup=autorun is supported.'}
 if($existing.Exists -and ($existing.Kind -notin @('String','ExpandString') -or $existing.Data -cne $ExpectedCommand)){throw 'Current value differs from approved command. Stop and inspect.'}
 New-Item -ItemType Directory -Force -Path $RuntimeDirectory|Out-Null
 if(Test-Path $backupFile){
  $old=Read-Json $backupFile
  if($old.Sid -ne $ExpectedSid){throw 'Backup belongs to a different user'}
  if(-not(Test-Path "$RuntimeDirectory\uninstalled.json")){throw 'Existing incomplete install/backup: inspect or uninstall before retrying.'}
 } else {Write-Json ([pscustomobject]@{Sid=$ExpectedSid;Account=$id.Name;At=(Get-Date -Format o);Values=@($existing,(Save-Value $approvedPath 'cloudmusic'))}) $backupFile}
 foreach($file in @('Common.ps1','Guard.ps1','Manage.ps1')) {
  $source=Join-Path $PSScriptRoot $file;$dest=Join-Path $RuntimeDirectory $file
  if([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($dest)){Copy-Item -LiteralPath $source -Destination $dest -Force}
 }
 $config=[pscustomobject]@{Sid=$ExpectedSid;TaskName=$taskName;RunPath=$runPath;ValueName='cloudmusic';Command=$ExpectedCommand;ExePath=$ExePath}
 Write-Json $config $configFile
 $cmd='@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage.ps1" -Action Uninstall -ExpectedSid "'+$ExpectedSid+'" -RuntimeDirectory "%~dp0."'+"`r`n"+'pause'+"`r`n"
 [IO.File]::WriteAllText((Join-Path $RuntimeDirectory 'Uninstall-and-restore.cmd'),$cmd,[Text.Encoding]::ASCII)
 $created=$false
 try {
  $taskAction=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$RuntimeDirectory+'\Guard.ps1" -ConfigPath "'+$configFile+'"') -WorkingDirectory $RuntimeDirectory
  $trigger=New-ScheduledTaskTrigger -AtLogOn -User $ExpectedSid
  $principal=New-ScheduledTaskPrincipal -UserId $ExpectedSid -LogonType Interactive -RunLevel Limited
  $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
  Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description 'Codex NetEase autorun cleanup; exact verified command only.'|Out-Null
  $created=$true;Start-ScheduledTask $taskName;Start-Sleep -Seconds 4
  if((Get-ScheduledTask $taskName).State -ne 'Running'){throw 'Guard did not stay running'}
  if((Save-Value $runPath 'cloudmusic').Exists){throw 'Autorun entry was not removed'}
  if(Test-Path "$RuntimeDirectory\uninstalled.json"){Remove-Item -LiteralPath "$RuntimeDirectory\uninstalled.json"}
 }catch{
  if($created){Stop-ScheduledTask $taskName;Unregister-ScheduledTask $taskName -Confirm:$false}
  foreach($e in (Read-Json $backupFile).Values){Restore-Value $e}
  Write-Json @{At=(Get-Date -Format o);Reason='Install rollback'} "$RuntimeDirectory\uninstalled.json"
  throw
 }
 Get-GuardStatus|ConvertTo-Json -Depth 8;return
}
if(-not(Test-Path $configFile) -or -not(Test-Path $backupFile)){throw 'Missing runtime config or backup'}
$config=Read-Json $configFile;$backup=Read-Json $backupFile
if($config.Sid -ne $ExpectedSid -or $backup.Sid -ne $ExpectedSid -or $config.TaskName -ne $taskName){throw 'Runtime identity mismatch'}
if($Action -eq 'Verify') {
 if((Get-ScheduledTask $taskName).State -ne 'Running'){throw 'Guard is not running'}
 $before=Save-Value $runPath 'cloudmusic'
 $approval=Save-Value $approvedPath 'cloudmusic'
 if($before.Exists){throw 'Unexpected existing value; inspect before simulation'}
 $key=Open-UserKey $runPath $true
 try {
  $key.SetValue('cloudmusic',[string]$config.Command,[Microsoft.Win32.RegistryValueKind]::String)
  $deadline=[DateTime]::UtcNow.AddSeconds(5)
  do {Start-Sleep -Milliseconds 100;$remaining=$key.GetValue('cloudmusic')}while($null -ne $remaining -and [DateTime]::UtcNow -lt $deadline)
  if($null -ne $remaining){throw 'Simulated update was not cleaned'}
  if(($approval|ConvertTo-Json -Compress) -cne ((Save-Value $approvedPath 'cloudmusic')|ConvertTo-Json -Compress)){throw 'Approval record unexpectedly changed'}
  [pscustomobject]@{SimulatedUpdate='PASS';ApprovalPreserved=$true;Status=(Get-GuardStatus)}|ConvertTo-Json -Depth 8
 }finally{$key.Dispose();Restore-Value $before}
 return
}
if($Action -eq 'Uninstall') {
 $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 if($task){
  if(($task.Actions.Arguments -join ' ') -notlike ('*'+$configFile+'*')){throw 'Task action does not match this runtime; refusing to remove it'}
  Disable-ScheduledTask $taskName|Out-Null;Stop-ScheduledTask $taskName;Start-Sleep -Seconds 2
  if((Get-ScheduledTask $taskName).State -eq 'Running'){throw 'Task still running; restore postponed'}
  Unregister-ScheduledTask $taskName -Confirm:$false
 }
 foreach($entry in $backup.Values){Restore-Value $entry}
 foreach($entry in $backup.Values){
  $actual=Save-Value $entry.Path $entry.Name
  if(($actual|ConvertTo-Json -Compress) -cne ($entry|ConvertTo-Json -Compress)){throw 'Restore verification failed'}
 }
 Write-Json @{At=(Get-Date -Format o);Restored=$true} "$RuntimeDirectory\uninstalled.json"
 'Uninstalled; original startup settings restored. Runtime files retained.'
}
