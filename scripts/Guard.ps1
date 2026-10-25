param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1"
$config=Read-Json $ConfigPath
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
if ($id.User.Value -ne $config.Sid) { throw 'Wrong user SID' }
$runtime=Split-Path -Parent $ConfigPath
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NcmRegistryNotify {
 [DllImport("advapi32.dll", SetLastError=true)]
 public static extern int RegNotifyChangeKeyValue(Microsoft.Win32.SafeHandles.SafeRegistryHandle key, bool subtree, uint filter, IntPtr signal, bool asynchronous);
}
'@
$mutex=New-Object System.Threading.Mutex($false, ('Local\'+$config.TaskName))
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit }
try {
 $key=Open-UserKey $config.RunPath $true
 $signal=New-Object System.Threading.AutoResetEvent($false)
 Add-Content "$runtime\guard.log" ((Get-Date -Format o)+' Started')
 while ($true) {
  $result=[NcmRegistryNotify]::RegNotifyChangeKeyValue($key.Handle,$false,4,$signal.SafeWaitHandle.DangerousGetHandle(),$true)
  if ($result -ne 0) { throw "Registry notification failed: $result" }
  $command=$key.GetValue($config.ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  if ($command -is [string] -and $command -ceq $config.Command) {
   $key.DeleteValue($config.ValueName,$false)
   if ((Test-Path "$runtime\guard.log") -and (Get-Item "$runtime\guard.log").Length -gt 262144) { Clear-Content "$runtime\guard.log" }
   Add-Content "$runtime\guard.log" ((Get-Date -Format o)+' Removed verified autorun value')
  }
  Write-Json ([pscustomobject]@{Pid=$PID;Sid=$id.User.Value;At=(Get-Date -Format o)}) "$runtime\heartbeat.json"
  while (-not $signal.WaitOne(60000)) { Write-Json ([pscustomobject]@{Pid=$PID;Sid=$id.User.Value;At=(Get-Date -Format o)}) "$runtime\heartbeat.json" }
 }
} catch { Add-Content "$runtime\guard.log" ((Get-Date -Format o)+' ERROR '+$_.Exception.Message); exit 1 }
finally { if($key){$key.Dispose()};if($signal){$signal.Dispose()};$mutex.ReleaseMutex();$mutex.Dispose() }
