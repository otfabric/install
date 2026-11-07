# OT Fabric installers

One-line installers for the OT Fabric protocol command-line tools.

```sh
curl -fsSL https://get.otfabric.io/modbusctl | sh
```

```powershell
irm https://get.otfabric.io/modbusctl.ps1 | iex
```

Replace `modbusctl` with any tool from the [list below](#tools). Run the same command again to upgrade.

The installer:

1. detects the platform (Linux amd64/arm64/armv7, macOS amd64/arm64, Windows amd64/arm64);
2. resolves the version (latest stable release, or `OTF_VERSION`) once and uses exactly that release;
3. downloads the archive and the release's SHA-256 checksums file, and refuses to install on a missing, malformed or mismatching checksum;
4. extracts only the expected binary, runs `<tool> version` as a smoke test, and only then replaces an installed copy;
5. installs per user without `sudo` (`~/.local/bin`, or `%LOCALAPPDATA%\OTFabric\bin`) and adds that directory to `PATH` unless told not to.

## Options

All options are environment variables, the same for every tool.

| Variable | Default | Effect |
|---|---|---|
| `OTF_VERSION` | `latest` | Install a specific version, `3.5.1` or `v3.5.1`. For tools that ship inside a library repository (kind `embedded` below), this is the library's version. |
| `OTF_INSTALL_DIR` | `~/.local/bin` (`$XDG_BIN_HOME` if set); Windows `%LOCALAPPDATA%\OTFabric\bin` | Install directory. `PATH` may be updated. |
| `OTF_UNMANAGED_INSTALL` | unset | Install directory for CI, containers and device images: never touches `PATH` or shell profiles. Cannot be combined with `OTF_INSTALL_DIR`. |
| `OTF_NO_MODIFY_PATH` | `0` | `1` leaves `PATH` and shell profiles alone. |
| `OTF_TARGET` | detected | Force a target, e.g. `linux-armv7`. |

```sh
# A specific version
curl -fsSL https://get.otfabric.io/modbusctl | env OTF_VERSION=3.5.1 sh

# CI, Dockerfile or device image: no profile changes
curl -fsSL https://get.otfabric.io/modbusctl | env OTF_UNMANAGED_INSTALL=/usr/local/bin sh
```

```powershell
$env:OTF_VERSION = '3.5.1'; $env:OTF_INSTALL_DIR = 'C:\Tools'
irm https://get.otfabric.io/modbusctl.ps1 | iex

# From cmd.exe
powershell -NoProfile -Command "irm https://get.otfabric.io/modbusctl.ps1 | iex"
```

Exit codes (shell, and PowerShell run as a file): `0` installed, `1` installation failed, `2` invalid input. Under `irm | iex` PowerShell never exits, so it cannot close your terminal.

## Requirements

- Linux and macOS: POSIX `sh` (dash, bash, zsh, BusyBox ash), `curl` or `wget` (BusyBox wget works), `tar`, and `sha256sum`, `shasum` or `openssl`.
- Windows: Windows PowerShell 5.1 or PowerShell 7. Nothing else.

32-bit x86 and ARMv6 are not supported. On a 64-bit ARM kernel with a 32-bit userland (common on Raspberry Pi OS), the 32-bit ARMv7 build is chosen.

## Without get.otfabric.io

The scripts also work straight from this repository and then download from GitHub Releases directly:

```sh
curl -fsSL https://raw.githubusercontent.com/otfabric/install/main/install.sh | sh -s -- modbusctl
```

```powershell
$env:OTF_TOOL = 'modbusctl'; irm https://raw.githubusercontent.com/otfabric/install/main/install.ps1 | iex
```

## Privacy

Requests to `get.otfabric.io` are logged to understand where and how the tools are used: the tool, version and platform, the installer's User-Agent (shown in `install.sh` / `install.ps1`: installer version, platform, OS version, shell, install mode, CI system), whether the install succeeded, and the approximate location derived from the IP address. Full IP addresses are not stored. The direct-from-GitHub route above sends nothing to OT Fabric.

## Security

The checksums file comes from the same GitHub release as the archive: it proves the download is intact, not who published it. Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## Tools

<!-- tools:start -->
| Tool | Kind | Protocol | Repository | Summary |
|---|---|---|---|---|
| `bacnetctl` | cli | BACnet | [otfabric/bacnetctl](https://github.com/otfabric/bacnetctl) | BACnet/IP discovery, property read/write, COV, alarms, BBMD and a simulated device. |
| `canbusctl` | cli | CAN | [otfabric/canbusctl](https://github.com/otfabric/canbusctl) | CAN FD/XL, SocketCAN, ISO-TP and DBC: monitor, decode, capture, replay and simulate. |
| `canopenctl` | cli | CANopen | [otfabric/canopenctl](https://github.com/otfabric/canopenctl) | CANopen (CiA 301/402) discovery, SDO/PDO, NMT, EMCY, EDS and device simulation. |
| `dnp3ctl` | cli | DNP3 | [otfabric/dnp3ctl](https://github.com/otfabric/dnp3ctl) | DNP3 (IEEE 1815) polling, control, discovery, file transfer and a simulated outstation. |
| `ethernetipctl` | cli | EtherNet/IP | [otfabric/ethernetipctl](https://github.com/otfabric/ethernetipctl) | EtherNet/IP (CIP) discovery, attributes, cyclic I/O, Logix tags, EDS and adapter simulation. |
| `iec104ctl` | cli | IEC 60870-5-104 | [otfabric/iec104ctl](https://github.com/otfabric/iec104ctl) | IEC 104 SCADA and RTU testing, monitoring, commands and diagnostics. |
| `iec61850ctl` | cli | IEC 61850 | [otfabric/iec61850ctl](https://github.com/otfabric/iec61850ctl) | IEC 61850 MMS, GOOSE and Sampled Values: discover IEDs, browse, control, reports and SCL. |
| `ieee20305ctl` | cli | IEEE 2030.5 | [otfabric/ieee20305ctl](https://github.com/otfabric/ieee20305ctl) | IEEE 2030.5 (SEP 2.0) DER testing: discovery, registration, certificates and validation. |
| `knxctl` | cli | KNX | [otfabric/knxctl](https://github.com/otfabric/knxctl) | KNXnet/IP discovery, tunnelling, routing, group monitoring, DPT coding and simulation. |
| `mbcapctl` | embedded | Modbus | [otfabric/go-modbus-capture](https://github.com/otfabric/go-modbus-capture) | Inspect, convert and validate Modbus capture files (.mbcap). |
| `mbtracectl` | embedded | Modbus | [otfabric/go-modbus-trace](https://github.com/otfabric/go-modbus-trace) | Analyse Modbus/TCP traffic in pcap/pcapng traces and export MBCAP. |
| `modbus-cli` | embedded | Modbus | [otfabric/go-modbus](https://github.com/otfabric/go-modbus) | Minimal Modbus TCP/RTU client for quick probing and troubleshooting. |
| `modbusctl` | cli | Modbus | [otfabric/modbusctl](https://github.com/otfabric/modbusctl) | Modbus TCP discovery, register scanning, fingerprinting, SunSpec, recording, replay and simulation. |
| `nsdctl` | embedded | IEC 61850 | [otfabric/go-iec61850-model](https://github.com/otfabric/go-iec61850-model) | Inspect and validate IEC 61850 namespace definitions (NSD, IEC 61850-7-7). |
| `ocppctl` | cli | OCPP | [otfabric/ocppctl](https://github.com/otfabric/ocppctl) | OCPP 1.6J/2.0.1/2.1: test CSMS connections, simulate chargers and serve a test CSMS. |
| `opcuactl` | cli | OPC UA | [otfabric/opcuactl](https://github.com/otfabric/opcuactl) | OPC UA discovery, browse, read/write, subscriptions, events, history and diagnostics. |
| `openadrctl` | cli | OpenADR | [otfabric/openadrctl](https://github.com/otfabric/openadrctl) | OpenADR 3.x VEN and business-logic clients, a test VTN, events and reports. |
| `otprobe` | embedded | multi-protocol | [otfabric/go-otfp](https://github.com/otfabric/go-otfp) | Identify which industrial protocol an endpoint speaks. |
| `profinetctl` | cli | PROFINET | [otfabric/profinetctl](https://github.com/otfabric/profinetctl) | PROFINET IO discovery, DCP configuration, LLDP topology, GSDML, I&M and RT I/O monitoring. |
| `s7commctl` | cli | S7comm | [otfabric/s7commctl](https://github.com/otfabric/s7commctl) | Siemens S7comm PLC discovery, identification, memory read/write, blocks and diagnostics. |
| `sclgen` | embedded | IEC 61850 | [otfabric/go-iec61850](https://github.com/otfabric/go-iec61850) | Generate Go types from IEC 61850 SCL XSD schema bundles. |
| `sclparse` | embedded | IEC 61850 | [otfabric/go-iec61850](https://github.com/otfabric/go-iec61850) | Detect, summarise and validate IEC 61850 SCL configuration files. |
| `sparkplugbctl` | cli | Sparkplug B | [otfabric/sparkplugbctl](https://github.com/otfabric/sparkplugbctl) | Sparkplug B 3.0 MQTT monitoring, publishing, Protobuf coding and edge/host simulation. |
| `sunspecctl` | cli | SunSpec | [otfabric/sunspecctl](https://github.com/otfabric/sunspecctl) | SunSpec Modbus for inverters, meters and batteries: discover, read, poll and simulate. |
<!-- tools:end -->

Adding a tool: see [CONTRIBUTING.md](CONTRIBUTING.md).
