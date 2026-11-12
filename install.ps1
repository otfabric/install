# OT Fabric installer for Windows (PowerShell 5.1 and 7).
#
#   irm https://get.otfabric.io/<tool>.ps1 | iex
#
# Environment (all optional):
#   OTF_VERSION            latest (default), or X.Y.Z / vX.Y.Z
#   OTF_INSTALL_DIR        install directory; user PATH may be updated (managed)
#   OTF_UNMANAGED_INSTALL  install directory; PATH untouched
#   OTF_NO_MODIFY_PATH=1   managed install without PATH changes
#   OTF_TARGET             override detection: windows-amd64, windows-arm64
#   OTF_TOOL               tool name, when this script is not served for one
#
# Run as a file (powershell -File install.ps1 <tool>), it exits with
# 0 installed, 1 installation failed, 2 invalid input. Under `| iex` it never
# exits, so it cannot close the calling shell.
# Source and documentation: https://github.com/otfabric/install

& {
  param([string]$ToolArg)

  Set-StrictMode -Version 2.0
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'

  # Filled in by get.otfabric.io when it serves this script. Left as they are,
  # the script talks to GitHub directly (the fallback when the service is down).
  $ServedTool = '@@TOOL@@'
  $ServedBase = '@@BASE_URL@@'
  $InstallerVersion = '@@INSTALLER_VERSION@@'

  # Tool -> GitHub repository, for the direct-to-GitHub fallback.
  # Generated from tools.json (make registry); tests keep the two equal.
  # >>> registry >>>
  $Registry = @{
    'bacnetctl' = 'otfabric/bacnetctl'
    'canbusctl' = 'otfabric/canbusctl'
    'canopenctl' = 'otfabric/canopenctl'
    'dnp3ctl' = 'otfabric/dnp3ctl'
    'ethernetipctl' = 'otfabric/ethernetipctl'
    'iec101ctl' = 'otfabric/iec60870ctl'
    'iec102ctl' = 'otfabric/iec60870ctl'
    'iec103ctl' = 'otfabric/iec60870ctl'
    'iec104ctl' = 'otfabric/iec60870ctl'
    'iec61850ctl' = 'otfabric/iec61850ctl'
    'ieee20305ctl' = 'otfabric/ieee20305ctl'
    'knxctl' = 'otfabric/knxctl'
    'mbcapctl' = 'otfabric/go-modbus-capture'
    'mbtracectl' = 'otfabric/go-modbus-trace'
    'mmstracectl' = 'otfabric/go-mms-trace'
    'modbus-cli' = 'otfabric/go-modbus'
    'modbusctl' = 'otfabric/modbusctl'
    'nsdctl' = 'otfabric/go-iec61850-model'
    'ocppctl' = 'otfabric/ocppctl'
    'opcuactl' = 'otfabric/opcuactl'
    'openadrctl' = 'otfabric/openadrctl'
    'otprobe' = 'otfabric/go-otfp'
    'profinetctl' = 'otfabric/profinetctl'
    's7commctl' = 'otfabric/s7commctl'
    'sclgen' = 'otfabric/go-iec61850'
    'sclparse' = 'otfabric/go-iec61850'
    'sparkplugbctl' = 'otfabric/sparkplugbctl'
    'sunspecctl' = 'otfabric/sunspecctl'
  }
  # <<< registry <<<

  $VersionPattern = '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'

  # Placeholder check without spelling the placeholder.
  function Test-Unfilled([string]$Value) { return $Value.StartsWith('@@') -and $Value.EndsWith('@@') }

  $state = @{ ToolArg = $ToolArg; Base = ''; Direct = $true; Tool = ''; Version = ''; Target = ''; Ua = ''; Id = ''; Requested = 'latest' }

  # Our own errors carry an exit code and a stage in Exception.Data.
  function New-OtfError([string]$Message, [int]$Code, [string]$Stage) {
    $e = New-Object System.Exception $Message
    $e.Data['otfCode'] = $Code
    $e.Data['otfStage'] = $Stage
    return $e
  }
  function Test-OtfError($Record) { return $Record.Exception.Data.Contains('otfCode') }
  function Stop-Usage([string]$Message) { throw (New-OtfError $Message 2 '') }
  function Stop-Stage([string]$Stage, [string]$Message) { throw (New-OtfError $Message 1 $Stage) }

  function Get-RequestHeader {
    return @{ 'X-OTF-Install' = $state.Id; 'X-OTF-Requested' = $state.Requested }
  }

  function Invoke-Fetch([string]$Url, [string]$OutFile) {
    $params = @{ Uri = $Url; UserAgent = $state.Ua; Headers = (Get-RequestHeader); UseBasicParsing = $true; TimeoutSec = 60 }
    if ($OutFile) { $params.OutFile = $OutFile }
    $last = $null
    for ($i = 0; $i -lt 3; $i++) {
      try {
        $r = Invoke-WebRequest @params
        if ($OutFile) { return $true }
        if ($r.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($r.Content) }
        return [string]$r.Content
      } catch {
        $last = $_
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
        if ($status -ge 400 -and $status -lt 500) { break }
        Start-Sleep -Seconds (2 * ($i + 1))
      }
    }
    throw $last
  }

  function Send-Report([string]$Status, [string]$Stage) {
    if ($state.Direct -or -not $state.Base -or -not $state.Tool) { return }
    $q = 'v={0}&t={1}&s={2}&stage={3}' -f [uri]::EscapeDataString($state.Version), $state.Target, $Status, $Stage
    try {
      Invoke-WebRequest -Uri ('{0}/r/{1}?{2}' -f $state.Base, $state.Tool, $q) -UserAgent $state.Ua `
        -Headers (Get-RequestHeader) -UseBasicParsing -TimeoutSec 2 | Out-Null
    } catch {
      $null = $_  # best effort: the outcome report never affects the install
    }
  }

  function Get-Target {
    $isWin = $true
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { $isWin = $IsWindows }
    if (-not $isWin) {
      Stop-Usage ('on Linux and macOS, use: curl -fsSL https://get.otfabric.io/{0} | sh' -f $state.Tool)
    }
    $arch = $null
    try {
      $arch = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    } catch { $arch = $null }
    if (-not $arch) {
      # Older .NET Framework: the native architecture even under emulation.
      $arch = $env:PROCESSOR_ARCHITEW6432
      if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    }
    switch -Regex ($arch) {
      '^(X64|AMD64)$' { return 'windows-amd64' }
      '^(Arm64|ARM64)$' { return 'windows-arm64' }
      default { Stop-Usage "unsupported Windows architecture: $arch (need x64 or ARM64)" }
    }
  }

  function Get-CiName {
    if ($env:GITHUB_ACTIONS) { return 'github-actions' }
    if ($env:GITLAB_CI) { return 'gitlab-ci' }
    if ($env:JENKINS_URL) { return 'jenkins' }
    if ($env:TF_BUILD) { return 'azure-pipelines' }
    if ($env:BITBUCKET_BUILD_NUMBER) { return 'bitbucket' }
    if ($env:CIRCLECI) { return 'circleci' }
    if ($env:BUILDKITE) { return 'buildkite' }
    if ($env:CI) { return 'ci' }
    return '-'
  }

  function Add-UserPath([string]$Dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { $current = '' }
    $parts = $current.Split(';') | Where-Object { $_ -ne '' }
    if ($parts | Where-Object { $_.TrimEnd('\') -ieq $Dir.TrimEnd('\') }) { return $false }
    $new = (@($parts) + $Dir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    return $true
  }

  function Test-OnPath([string]$Dir) {
    foreach ($p in ($env:Path -split ';')) { if ($p -and $p.TrimEnd('\') -ieq $Dir.TrimEnd('\')) { return $true } }
    return $false
  }

  function Install-Tool {
    # Tool: served name, then the argument, then OTF_TOOL.
    $tool = $ServedTool
    if (Test-Unfilled $tool) { $tool = $state.ToolArg }
    if (-not $tool) { $tool = $env:OTF_TOOL }
    if (-not $tool) { Stop-Usage 'no tool given; set $env:OTF_TOOL (see https://get.otfabric.io/)' }
    if ($tool -cnotmatch '^[a-z0-9][a-z0-9-]*$') { Stop-Usage "invalid tool name: $tool" }
    $state.Tool = $tool

    $iv = $InstallerVersion
    if (Test-Unfilled $iv) { $iv = 'dev' }

    $base = $env:OTF_BASE_URL
    if (-not $base) { $base = $ServedBase }
    if (Test-Unfilled $base) { $base = '' }
    $base = $base.TrimEnd('/')
    if ($base -and $base -notmatch '^https://' -and $base -notmatch '^http://(127\.0\.0\.1|localhost):[0-9]+$') {
      Stop-Usage 'OTF_BASE_URL must be https'
    }
    $state.Base = $base
    $state.Direct = -not $base

    $repo = ''
    if ($state.Direct) {
      if (-not $Registry.ContainsKey($tool)) { Stop-Usage "unknown tool: $tool (see https://github.com/otfabric/install#tools)" }
      $repo = $Registry[$tool]
    }

    if ($env:OTF_UNMANAGED_INSTALL -and $env:OTF_INSTALL_DIR) { Stop-Usage 'set OTF_INSTALL_DIR or OTF_UNMANAGED_INSTALL, not both' }
    if ($env:OTF_UNMANAGED_INSTALL) {
      $dest = $env:OTF_UNMANAGED_INSTALL; $mode = 'unmanaged'
    } else {
      $dest = $env:OTF_INSTALL_DIR
      if (-not $dest) { $dest = Join-Path $env:LOCALAPPDATA 'OTFabric\bin' }
      $mode = 'managed'
    }
    $dest = [IO.Path]::GetFullPath($dest)

    $requested = $env:OTF_VERSION
    if (-not $requested) { $requested = 'latest' }
    $requested = $requested -replace '^v', ''
    if ($requested -ne 'latest' -and $requested -notmatch $VersionPattern) {
      Stop-Usage "invalid OTF_VERSION: $($env:OTF_VERSION) (expected X.Y.Z)"
    }
    $state.Requested = $requested

    if ($env:OTF_TARGET) {
      if ($env:OTF_TARGET -notin @('windows-amd64', 'windows-arm64')) { Stop-Usage "invalid OTF_TARGET: $($env:OTF_TARGET)" }
      $target = $env:OTF_TARGET
    } else {
      $target = Get-Target
    }
    $state.Target = $target

    $state.Id = -join ((1..8) | ForEach-Object { '{0:x2}' -f (Get-Random -Minimum 0 -Maximum 256) })
    $osDetail = 'windows {0}' -f [Environment]::OSVersion.Version.ToString()
    $runtime = 'powershell {0}.{1}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
    if ($PSVersionTable.PSEdition -eq 'Core') { $runtime = 'pwsh {0}.{1}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor }
    $state.Ua = 'otfabric-install/{0} (ps1; {1}; {2}; {3}; {4}; {5})' -f $iv, $target, $osDetail, $runtime, $mode, (Get-CiName)

    # Resolve once; everything after uses this exact version.
    if ($requested -eq 'latest') {
      $version = ''
      try {
        if ($state.Direct) {
          $json = Invoke-Fetch "https://api.github.com/repos/$repo/releases/latest" $null | ConvertFrom-Json
          $version = ([string]$json.tag_name) -replace '^v', ''
        } else {
          $version = (Invoke-Fetch "$base/$tool/latest" $null).Trim()
        }
      } catch { $version = '' }
      if ($version -notmatch $VersionPattern) {
        Stop-Stage 'resolve' "could not determine the latest version of $tool; retry, or set OTF_VERSION"
      }
    } else {
      $version = $requested
    }
    $state.Version = $version

    $archive = "$tool-$version-$target.zip"
    $sums = "$tool-$version-checksums.txt"
    $member = "$tool-$version-$target.exe"
    if ($state.Direct) { $urlBase = "https://github.com/$repo/releases/download/v$version" } else { $urlBase = "$base/dl/$tool/$version" }

    Write-Host "Installing $tool $version ($target) into $dest"

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('otfabric-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
      try { Invoke-Fetch "$urlBase/$sums" (Join-Path $tmp $sums) | Out-Null }
      catch { Stop-Stage 'download' "$tool $version has no published checksums; the version may not exist or is still being published" }
      try { Invoke-Fetch "$urlBase/$archive" (Join-Path $tmp $archive) | Out-Null }
      catch { Stop-Stage 'download' "could not download $archive" }

      $expected = $null
      foreach ($line in (Get-Content -LiteralPath (Join-Path $tmp $sums))) {
        $f = $line -split '\s+', 2
        if ($f.Count -eq 2 -and ($f[1] -ceq $archive -or $f[1] -ceq "*$archive")) { $expected = $f[0].ToLowerInvariant(); break }
      }
      if ($expected -notmatch '^[0-9a-f]{64}$') { Stop-Stage 'checksum' "no checksum for $archive in $sums" }
      $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $tmp $archive)).Hash.ToLowerInvariant()
      if ($actual -ne $expected) { Stop-Stage 'checksum' "checksum mismatch for $archive (expected $expected, got $actual)" }

      # Extract only the expected member.
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      $exe = Join-Path $tmp "$tool.exe"
      $zip = $null
      try {
        $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $tmp $archive))
        $entry = $zip.Entries | Where-Object { $_.FullName -ceq $member } | Select-Object -First 1
        if (-not $entry) { Stop-Stage 'extract' "$archive does not contain $member" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $exe, $true)
      } catch {
        if (Test-OtfError $_) { throw }
        Stop-Stage 'extract' "cannot extract $archive`: $($_.Exception.Message)"
      } finally { if ($zip) { $zip.Dispose() } }

      # Smoke test before replacing anything. Every OT Fabric CLI has `version`.
      # Windows PowerShell 5.1 turns native stderr into a terminating error under
      # ErrorActionPreference=Stop, so relax it for this one call.
      $rc = 1
      $previousPreference = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      try { & $exe version *> $null; $rc = $LASTEXITCODE } catch { $rc = 1 } finally { $ErrorActionPreference = $previousPreference }
      if ($rc -ne 0) { Stop-Stage 'smoke' "$tool $version does not run on this system ($target)" }

      try {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $final = Join-Path $dest "$tool.exe"
        $old = Join-Path $dest ".$tool.old.exe"
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
        # A running .exe cannot be overwritten but can be renamed.
        if (Test-Path -LiteralPath $final) { Move-Item -LiteralPath $final -Destination $old -Force }
        try { Move-Item -LiteralPath $exe -Destination $final -Force }
        catch {
          if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination $final -Force }
          throw
        }
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
      } catch {
        if (Test-OtfError $_) { throw }
        Stop-Stage 'install' "cannot install into $dest`: $($_.Exception.Message)"
      }
    } finally {
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Send-Report 'ok' ''
    Write-Host "Installed $tool $version to $final"

    if ($mode -eq 'managed' -and $env:OTF_NO_MODIFY_PATH -ne '1' -and -not (Test-OnPath $dest)) {
      if (Add-UserPath $dest) { Write-Host "Added $dest to your user PATH. Open a new terminal to use it." }
      $env:Path = "$dest;$env:Path"
    } elseif (-not (Test-OnPath $dest)) {
      Write-Host "$dest is not on your PATH; add it, or run $final"
    }
    Write-Host "Run '$tool --help' to get started."
  }

  $script:exitCode = 0
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {
    $null = $_  # PowerShell 7 has no ServicePointManager setting to change
  }
  try {
    Install-Tool
  } catch {
    $e = $_.Exception
    Write-Host "error: $($e.Message)" -ForegroundColor Red
    if (Test-OtfError $_) {
      $script:exitCode = [int]$e.Data['otfCode']
      if ($script:exitCode -eq 1) { Send-Report 'fail' ([string]$e.Data['otfStage']) }
    } else {
      $script:exitCode = 1
      Send-Report 'fail' 'install'
    }
  }
  if ($script:exitCode -ne 0 -and $PSCommandPath) { exit $script:exitCode }
} @args
