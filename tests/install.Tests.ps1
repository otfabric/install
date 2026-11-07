# Pester 5 tests for install.ps1 against tests/fake_server.py, on Windows.
#
#   Invoke-Pester tests/install.Tests.ps1 -Output Detailed
#
# $env:OTF_TEST_SHELL picks the PowerShell under test (powershell or pwsh;
# default: the current one). Needs python and go on PATH.

BeforeAll {
  $script:Root = Split-Path -Parent $PSScriptRoot
  $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('otf-test-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $Work | Out-Null

  $fake = Join-Path $Root 'tests/fakebin'
  $good = Join-Path $Work 'good.exe'
  $bad = Join-Path $Work 'broken.exe'
  & go -C $fake build -o $good . ; if ($LASTEXITCODE) { throw 'go build failed' }
  & go -C $fake build -ldflags '-X main.broken=1' -o $bad . ; if ($LASTEXITCODE) { throw 'go build failed' }

  $script:Server = Start-Process -PassThru -NoNewWindow python `
    -ArgumentList @('-I', (Join-Path $Root 'tests/fake_server.py'), $Work, $good, $bad)
  $portFile = Join-Path $Work 'port'
  for ($i = 0; -not (Test-Path $portFile) -and $i -lt 100; $i++) { Start-Sleep -Milliseconds 100 }
  $script:Base = 'http://127.0.0.1:' + (Get-Content $portFile)
  $script:Log = Join-Path $Work 'requests.jsonl'

  $script:Shell = $env:OTF_TEST_SHELL
  if (-not $Shell) { $script:Shell = (Get-Process -Id $PID).Path }

  # Served copy of install.ps1, as get.otfabric.io serves it for a tool.
  function script:Get-Served([string]$Tool) {
    $text = Get-Content -Raw (Join-Path $Root 'install.ps1')
    $text = $text.Replace('@@TOOL@@', $Tool).Replace('@@BASE_URL@@', $Base).Replace('@@INSTALLER_VERSION@@', '9.9.9')
    $path = Join-Path $Work "served-$Tool.ps1"
    Set-Content -Path $path -Value $text -Encoding UTF8
    return $path
  }

  # Invoke-Case: like `irm | iex` in a fresh process. Returns output text.
  function script:Invoke-Case([string]$Tool, [hashtable]$Env = @{}) {
    Set-Content -Path $Log -Value '' -NoNewline
    $served = Get-Served $Tool
    $saved = @{}
    $names = @('OTF_VERSION', 'OTF_INSTALL_DIR', 'OTF_UNMANAGED_INSTALL', 'OTF_NO_MODIFY_PATH', 'OTF_TARGET', 'OTF_BASE_URL')
    foreach ($n in $names + @($Env.Keys)) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
      foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $null) }
      foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
      $out = & $Shell -NoProfile -NonInteractive -Command "Get-Content -Raw '$served' | Invoke-Expression; 'iex-returned'" 2>&1 | Out-String
    } finally {
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    return $out
  }

  # Invoke-File: as `powershell -File`, which sets the exit code.
  function script:Invoke-File([string]$Tool, [hashtable]$Env = @{}) {
    Set-Content -Path $Log -Value '' -NoNewline
    $served = Get-Served $Tool
    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
      & $Shell -NoProfile -NonInteractive -File $served 2>&1 | Out-Null
      return $LASTEXITCODE
    } finally {
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
  }

  function script:Get-Requests { return Get-Content $Log | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } }
}

AfterAll {
  if ($Server) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Describe 'install.ps1' {
  It 'installs, reports ok and does not close the shell under iex' {
    $dir = Join-Path $Work 'managed'
    $out = Invoke-Case 'goodtool' @{ OTF_INSTALL_DIR = $dir; OTF_NO_MODIFY_PATH = '1' }
    $out | Should -Match 'Installed goodtool 1.2.3'
    $out | Should -Match 'iex-returned'
    Test-Path (Join-Path $dir 'goodtool.exe') | Should -BeTrue
    & (Join-Path $dir 'goodtool.exe') version | Should -Match 'fakebin version'
    $r = Get-Requests
    ($r | Where-Object { $_.path -eq '/goodtool/latest' }) | Should -Not -BeNullOrEmpty
    ($r | Where-Object { $_.path -like '/dl/goodtool/1.2.3/goodtool-1.2.3-windows-*.zip' }) | Should -Not -BeNullOrEmpty
    ($r | Where-Object { $_.path -eq '/r/goodtool' -and $_.query.s -eq 'ok' }) | Should -Not -BeNullOrEmpty
    $r[0].ua | Should -Match '^otfabric-install/9\.9\.9 \(ps1; windows-(amd64|arm64); windows [0-9.]+; (powershell|pwsh) [0-9.]+; managed; [^;)]+\)$'
    $r[0].install | Should -Match '^[0-9a-f]{16}$'
  }

  It 'replaces an existing binary' {
    $dir = Join-Path $Work 'managed'
    Invoke-Case 'goodtool' @{ OTF_INSTALL_DIR = $dir; OTF_NO_MODIFY_PATH = '1'; OTF_VERSION = '1.0.0' } | Should -Match 'Installed goodtool 1.0.0'
    (Get-ChildItem -Force $dir | Where-Object { $_.Name -like '.*' }) | Should -BeNullOrEmpty
  }

  It 'adds the directory to the user PATH once' {
    $dir = Join-Path $Work 'pathdir'
    $before = [Environment]::GetEnvironmentVariable('Path', 'User')
    try {
      Invoke-Case 'goodtool' @{ OTF_INSTALL_DIR = $dir } | Should -Match 'Added .* to your user PATH'
      Invoke-Case 'goodtool' @{ OTF_INSTALL_DIR = $dir } | Out-Null
      $parts = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';') | Where-Object { $_ -ieq $dir }
      @($parts).Count | Should -Be 1
    } finally {
      [Environment]::SetEnvironmentVariable('Path', $before, 'User')
    }
  }

  It 'unmanaged leaves PATH alone' {
    $before = [Environment]::GetEnvironmentVariable('Path', 'User')
    $dir = Join-Path $Work 'unmanaged'
    Invoke-Case 'goodtool' @{ OTF_UNMANAGED_INSTALL = $dir } | Should -Match 'Installed'
    [Environment]::GetEnvironmentVariable('Path', 'User') | Should -Be $before
    (Get-Requests)[0].ua | Should -Match '; unmanaged; '
  }

  It 'refuses a checksum mismatch and reports the stage' {
    $dir = Join-Path $Work 'bad'
    Invoke-Case 'badsum' @{ OTF_UNMANAGED_INSTALL = $dir } | Should -Match 'checksum mismatch'
    Test-Path (Join-Path $dir 'badsum.exe') | Should -BeFalse
    (Get-Requests | Where-Object { $_.path -eq '/r/badsum' }).query.stage | Should -Be 'checksum'
  }

  It 'reports a missing checksums file as download' {
    Invoke-Case 'nosums' @{ OTF_UNMANAGED_INSTALL = (Join-Path $Work 'x') } | Should -Match 'no published checksums'
    (Get-Requests | Where-Object { $_.path -eq '/r/nosums' }).query.stage | Should -Be 'download'
  }

  It 'reports a missing member as extract' {
    Invoke-Case 'nomember' @{ OTF_UNMANAGED_INSTALL = (Join-Path $Work 'x') } | Should -Match 'does not contain'
    (Get-Requests | Where-Object { $_.path -eq '/r/nomember' }).query.stage | Should -Be 'extract'
  }

  It 'keeps the previous binary when the new one does not run' {
    $dir = Join-Path $Work 'keep'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path (Join-Path $dir 'broken.exe') -Value 'previous'
    Invoke-Case 'broken' @{ OTF_UNMANAGED_INSTALL = $dir } | Should -Match 'does not run'
    Get-Content (Join-Path $dir 'broken.exe') | Should -Be 'previous'
    (Get-Requests | Where-Object { $_.path -eq '/r/broken' }).query.stage | Should -Be 'smoke'
  }

  It 'exits 0 / 1 / 2 when run as a file' {
    Invoke-File 'goodtool' @{ OTF_UNMANAGED_INSTALL = (Join-Path $Work 'file') } | Should -Be 0
    Invoke-File 'badsum' @{ OTF_UNMANAGED_INSTALL = (Join-Path $Work 'file') } | Should -Be 1
    Invoke-File 'goodtool' @{ OTF_VERSION = 'nope' } | Should -Be 2
  }

  It 'rejects invalid input without downloading' {
    Invoke-Case 'goodtool' @{ OTF_VERSION = '1.2;calc' } | Should -Match 'invalid OTF_VERSION'
    Invoke-Case 'goodtool' @{ OTF_INSTALL_DIR = 'C:\a'; OTF_UNMANAGED_INSTALL = 'C:\b' } | Should -Match 'not both'
    Invoke-Case 'goodtool' @{ OTF_TARGET = 'linux-amd64' } | Should -Match 'invalid OTF_TARGET'
    Invoke-Case 'goodtool' @{ OTF_BASE_URL = 'http://example.com' } | Should -Match 'must be https'
    (Get-Requests) | Should -BeNullOrEmpty
  }

  It 'direct mode rejects an unknown tool' {
    $out = & $Shell -NoProfile -NonInteractive -File (Join-Path $Root 'install.ps1') 'no-such-tool' 2>&1 | Out-String
    $LASTEXITCODE | Should -Be 2
    $out | Should -Match 'unknown tool'
  }
}
