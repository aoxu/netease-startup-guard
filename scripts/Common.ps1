$ErrorActionPreference = 'Stop'
function Open-UserKey([string]$Path, [bool]$Write = $false) {
 $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
 try { if ($Write) { return $base.CreateSubKey($Path) }; return $base.OpenSubKey($Path) } finally { $base.Dispose() }
}
function Save-Value([string]$Path, [string]$Name) {
 $key = Open-UserKey $Path
 try {
  $exists = $key -and ($key.GetValueNames() -contains $Name)
  $kind = if ($exists) { $key.GetValueKind($Name).ToString() } else { $null }
  $data = if ($exists) { $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
  if ($kind -eq 'Binary') { $data = [Convert]::ToBase64String([byte[]]$data) }
  [pscustomobject]@{ Path=$Path; Name=$Name; Exists=[bool]$exists; Kind=$kind; Data=$data }
 } finally { if ($key) { $key.Dispose() } }
}
function Restore-Value($Entry) {
 $key = Open-UserKey $Entry.Path $true
 try {
  if (-not $Entry.Exists) { $key.DeleteValue($Entry.Name, $false); return }
  $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$Entry.Kind)
  if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) {
   $key.SetValue($Entry.Name, [Convert]::FromBase64String($Entry.Data), $kind)
  } else { $key.SetValue($Entry.Name, [string]$Entry.Data, $kind) }
 } finally { $key.Dispose() }
}
function Read-Json([string]$Path) { Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json }
function Write-Json($Value, [string]$Path) { $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8 }
