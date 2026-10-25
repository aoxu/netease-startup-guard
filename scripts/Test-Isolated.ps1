param([Parameter(Mandatory=$true)][string]$WorkDirectory)
. "$PSScriptRoot\Common.ps1"
$token=[Guid]::NewGuid().ToString('N')
$root='Software\CodexNcmGuardTests\'+$token
$dir=Join-Path ([IO.Path]::GetFullPath($WorkDirectory)) $token
New-Item -ItemType Directory -Path $dir -Force|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$config=[pscustomobject]@{Sid=$sid;TaskName=('Codex-NCMGuard-Test-'+$token);RunPath=$root;ValueName='cloudmusic';Command='"C:\Test Only\cloudmusic.exe" --orpheus-startup=autorun'}
Write-Json $config "$dir\config.json"
$key=Open-UserKey $root $true
$proc=$null
try {
 $key.SetValue('unrelated','keep this')
 $key.SetValue('cloudmusic',[byte[]](3,0,0,0,255,1,2,3,4,5,6,7),[Microsoft.Win32.RegistryValueKind]::Binary)
 $binary=Save-Value $root 'cloudmusic'
 Write-Json $binary "$dir\binary-backup.json"
 $key.DeleteValue('cloudmusic')
 Restore-Value (Read-Json "$dir\binary-backup.json")
 if((Save-Value $root 'cloudmusic').Data -cne $binary.Data){throw 'Binary restore failed'}
 $key.DeleteValue('cloudmusic')
 $absent=Save-Value $root 'cloudmusic'
 $key.SetValue('cloudmusic',[string]$config.Command)
 $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Guard.ps1" -ConfigPath "'+$dir+'\config.json"'
 $proc=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardError "$dir\stderr.txt"
 $deadline=[DateTime]::UtcNow.AddSeconds(12)
 while($null -ne $key.GetValue('cloudmusic') -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
 if($null -ne $key.GetValue('cloudmusic')){throw 'Initial cleanup failed'}
 $key.SetValue('cloudmusic','"C:\Test Only\cloudmusic.exe" --manual')
 Start-Sleep -Milliseconds 500
 if($key.GetValue('cloudmusic') -notlike '*--manual'){throw 'Nonmatching command was changed'}
 for($i=0;$i -lt 3;$i++){
  $key.SetValue('cloudmusic',[string]$config.Command)
  $deadline=[DateTime]::UtcNow.AddSeconds(5)
  while($null -ne $key.GetValue('cloudmusic') -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50}
  if($null -ne $key.GetValue('cloudmusic')){throw 'Repeated change cleanup failed'}
 }
 if($key.GetValue('unrelated') -cne 'keep this'){throw 'Unrelated value was changed'}
 if($proc.HasExited){throw 'Guard exited unexpectedly'}
 $key.SetValue('cloudmusic','temporary')
 Restore-Value $absent
 if($null -ne $key.GetValue('cloudmusic')){throw 'Absent value restoration failed'}
 $result=[pscustomobject]@{InitialCleanup='PASS';RepeatedEvents='PASS';NonmatchingCommand='PASS';UnrelatedValue='PASS';BinaryRestore='PASS';AbsentRestore='PASS';Evidence=$dir}
 Write-Json $result "$dir\test-result.json"
 $result|ConvertTo-Json
}finally{
 if($proc -and -not $proc.HasExited){Stop-Process -Id $proc.Id; $proc.WaitForExit()}
 $key.Dispose()
 $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
 try {if($root -ne ('Software\CodexNcmGuardTests\'+$token)){throw 'Test cleanup scope mismatch'};$base.DeleteSubKeyTree($root,$false)}finally{$base.Dispose()}
}
