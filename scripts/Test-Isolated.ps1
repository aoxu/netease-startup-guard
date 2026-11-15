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
 & "$PSScriptRoot\Build-Hosts.ps1" -OutputDirectory $dir
 $proc=Start-Process -FilePath "$dir\NetEaseStartupGuard.exe" -ArgumentList ('"'+$dir+'\config.json"') -WindowStyle Hidden -PassThru
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
 $heartbeat=Read-Json "$dir\heartbeat.json"
 $proc.Refresh()
 if($heartbeat.ConsoleHandle -ne 0 -or $heartbeat.Host -ne 'native-winexe' -or $proc.MainWindowHandle -ne 0){throw 'Windowless host check failed'}
 # No console can be allocated by this Windows-subsystem executable.
 $binaryBytes=[IO.File]::ReadAllBytes("$dir\NetEaseStartupGuard.exe")
 $pe=[BitConverter]::ToInt32($binaryBytes,0x3c)
 if([BitConverter]::ToUInt16($binaryBytes,$pe+24+68) -ne 2){throw 'Executable is not Windows GUI subsystem'}
 $key.SetValue('cloudmusic','temporary')
 Restore-Value $absent
 if($null -ne $key.GetValue('cloudmusic')){throw 'Absent value restoration failed'}
 $result=[pscustomobject]@{WindowlessHost='PASS';InitialCleanup='PASS';RepeatedEvents='PASS';NonmatchingCommand='PASS';UnrelatedValue='PASS';BinaryRestore='PASS';AbsentRestore='PASS';Evidence=$dir}
 Write-Json $result "$dir\test-result.json"
 $result|ConvertTo-Json
}finally{
 if($proc -and -not $proc.HasExited){Stop-Process -Id $proc.Id; $proc.WaitForExit()}
 $key.Dispose()
 $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
 try {if($root -ne ('Software\CodexNcmGuardTests\'+$token)){throw 'Test cleanup scope mismatch'};$base.DeleteSubKeyTree($root,$false)}finally{$base.Dispose()}
}
