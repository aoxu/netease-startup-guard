param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){throw '.NET Framework x64 C# compiler not available. Do not fall back to a visible PowerShell guard.'}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
& $compiler /nologo /target:winexe /platform:x64 /reference:System.Web.Extensions.dll ('/out:'+(Join-Path $OutputDirectory 'NetEaseStartupGuard.exe')) (Join-Path $PSScriptRoot 'GuardHost.cs')
if($LASTEXITCODE -ne 0){throw 'Guard compilation failed'}
& $compiler /nologo /target:winexe /platform:x64 ('/out:'+(Join-Path $OutputDirectory 'WindowlessRunner.exe')) (Join-Path $PSScriptRoot 'WindowlessRunner.cs')
if($LASTEXITCODE -ne 0){throw 'Setup runner compilation failed'}
