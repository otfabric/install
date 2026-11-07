# Release notes

## v0.1.0

- First release: `install.sh` (POSIX sh) and `install.ps1` (PowerShell 5.1 and 7) for 24 OT Fabric tools.
- Mandatory SHA-256 verification against the release checksums file; only the expected archive member is extracted; `<tool> version` smoke test before an existing binary is replaced.
- `OTF_VERSION`, `OTF_INSTALL_DIR`, `OTF_UNMANAGED_INSTALL`, `OTF_NO_MODIFY_PATH`, `OTF_TARGET`; exit codes 0/1/2.
- Served by get.otfabric.io; falls back to GitHub Releases when run from this repository.

---
