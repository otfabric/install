# Install every tool in the registry through the live service with
# `irm | iex` in Windows PowerShell 5.1, each into its own directory, and run
# it. Writes "<tool> <ok|fail> <version or reason>" lines to -Out and exits 1
# if any tool failed.
#
#   pwsh tests/all_tools.ps1 -Out results.txt
param(
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$Base = 'https://get.otfabric.io'
)

$work = Join-Path ([IO.Path]::GetTempPath()) ('otf-all-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Set-Content -Path $Out -Value $null

$registry = Invoke-RestMethod "$Base/tools.json"
$tools = $registry.PSObject.Properties.Name | Sort-Object
$failed = $false

foreach ($tool in $tools) {
  Write-Output "::group::$tool"
  $dir = Join-Path $work $tool
  $env:OTF_UNMANAGED_INSTALL = $dir
  & powershell -NoProfile -NonInteractive -Command "irm '$Base/$tool.ps1' | iex"
  $exe = Join-Path $dir "$tool.exe"
  $line = "$tool fail see log"
  if (Test-Path $exe) {
    $ver = & $exe version 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -eq 0) { $line = "$tool ok $ver" }
  }
  if ($line -like '* fail *') { $failed = $true }
  Add-Content -Path $Out -Value $line
  Write-Output '::endgroup::'
}

Remove-Item Env:OTF_UNMANAGED_INSTALL
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
Get-Content $Out
if ($failed) { exit 1 }
