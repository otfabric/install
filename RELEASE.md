# Release notes

## v0.1.2

**Date:** 2026-11-12
**Previous release:** v0.1.1

- New tool: `mmstracectl` (IEC 61850 capture analysis), from otfabric/go-mms-trace.

---

## v0.1.1

**Date:** 2026-11-12
**Previous release:** v0.1.0

- New tools: `iec101ctl`, `iec102ctl` and `iec103ctl` (IEC 60870-5-101, -102 and -103), from otfabric/iec60870ctl.
- `iec104ctl` is now installed from otfabric/iec60870ctl, where it moved (v0.9.0 and later); otfabric/iec104ctl is no longer used.
- `org-scan`: reads `# binary-names:` from repositories with their own release workflow, and accepts a binary released by more than one repository when one of them is the registered one.

---

## v0.1.0

- First release: `install.sh` (POSIX sh) and `install.ps1` (PowerShell 5.1 and 7) for 24 OT Fabric tools.
- Mandatory SHA-256 verification against the release checksums file; only the expected archive member is extracted; `<tool> version` smoke test before an existing binary is replaced.
- `OTF_VERSION`, `OTF_INSTALL_DIR`, `OTF_UNMANAGED_INSTALL`, `OTF_NO_MODIFY_PATH`, `OTF_TARGET`; exit codes 0/1/2.
- Served by get.otfabric.io; falls back to GitHub Releases when run from this repository.

---
