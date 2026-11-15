param(
 [Parameter(Mandatory=$true)][string]$ExpectedSid,
 [Parameter(Mandatory=$true)][ValidateSet('Inspect','Install','Status','Verify','Uninstall')][string]$Action,
 [Parameter(Mandatory=$true)][string]$JobDirectory,
 [string]$ExePath,[string]$ExpectedCommand,[string]$RuntimeDirectory
)
$ErrorActionPreference='Stop'
if($ExpectedSid -notmatch '^S-1-5-21-(\d+-){3}\d+$'){throw 'Supply a verified interactive local/domain user SID'}
$jobRoot=[IO.Path]::GetFullPath($JobDirectory)
if(Test-Path $jobRoot){throw 'Use a new job directory for each run'}
New-Item -ItemType Directory -Path $jobRoot -Force|Out-Null
foreach($f in @('Common.ps1','Manage.ps1','Build-Hosts.ps1','GuardHost.cs','WindowlessRunner.cs')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination (Join-Path $jobRoot $f)}
& "$jobRoot\Build-Hosts.ps1" -OutputDirectory $jobRoot
$params=@{ExpectedSid=$ExpectedSid;Action=$Action}
if($ExePath){$params.ExePath=$ExePath};if($ExpectedCommand){$params.ExpectedCommand=$ExpectedCommand};if($RuntimeDirectory){$params.RuntimeDirectory=$RuntimeDirectory}
$params|ConvertTo-Json|Set-Content -LiteralPath "$jobRoot\request.json" -Encoding UTF8
@'
$ErrorActionPreference='Stop'
try {
 $request=Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\request.json"|ConvertFrom-Json
 $params=@{};foreach($p in $request.PSObject.Properties){$params[$p.Name]=$p.Value}
 & "$PSScriptRoot\Manage.ps1" @params | Out-String | Set-Content "$PSScriptRoot\result.txt" -Encoding UTF8
 '0'|Set-Content "$PSScriptRoot\complete.txt"
}catch{$_|Out-String|Set-Content "$PSScriptRoot\result.txt" -Encoding UTF8;'1'|Set-Content "$PSScriptRoot\complete.txt";exit 1}
'@|Set-Content -LiteralPath "$jobRoot\job.ps1" -Encoding UTF8
$name='Codex-NCMGuard-Setup-'+[Guid]::NewGuid().ToString('N')
$registered=$false
try {
 $actionObject=New-ScheduledTaskAction -Execute (Join-Path $jobRoot 'WindowlessRunner.exe') -Argument ('"'+$jobRoot+'\job.ps1"')
 $principal=New-ScheduledTaskPrincipal -UserId $ExpectedSid -LogonType Interactive -RunLevel Limited
 Register-ScheduledTask -TaskName $name -Action $actionObject -Principal $principal|Out-Null
 $registered=$true;Start-ScheduledTask $name
 $deadline=[DateTime]::UtcNow.AddSeconds(45)
 while(-not(Test-Path "$jobRoot\complete.txt") -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 500}
 if(-not(Test-Path "$jobRoot\complete.txt")){throw "Interactive task timed out. Inspect $jobRoot and task/runtime state; do not assume failure or retry blindly."}
 Get-Content -Raw -Encoding UTF8 "$jobRoot\result.txt"
 if((Get-Content "$jobRoot\complete.txt").Trim() -ne '0'){throw 'Interactive operation failed; see output above'}
}finally{if($registered){Stop-ScheduledTask $name -ErrorAction SilentlyContinue;Unregister-ScheduledTask $name -Confirm:$false}}
