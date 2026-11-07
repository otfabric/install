# AGENTS.md — install

## What this is

The public one-line installers for the OT Fabric command-line tools:
`install.sh` (POSIX sh, Linux and macOS) and `install.ps1` (Windows PowerShell
5.1 and PowerShell 7), the tool registry `tools.json`, and their tests. They
are served by get.otfabric.io, whose implementation is not in this repository.
Profile: **infrastructure**.

## Organisation standards

This repository follows **otfabric/engineering policy 1.4**, profile
**infrastructure** (`.otfabric/policy.yaml`, mode `enforce`). Where this file
and the organisation standards disagree, this file wins here — say so in your
report.

## Where the truth lives

| Question | Source |
|---|---|
| Which tools exist and where they are released | `tools.json` (the script registry blocks and the README table are generated from it) |
| Installer options, exit codes, requirements | README.md |
| Release asset naming | `otfabric/.github` `.github/workflows/go-binary-release.yml` |
| What is sent to get.otfabric.io | SECURITY.md, "Data sent" |
| Release history | RELEASE.md (`## vX.Y.Z` … `---`) |

## Hard rules

1. Checksum verification is never optional; there is no switch to skip it.
2. `install.sh` stays POSIX sh with no dependency beyond those in README.md "Requirements".
3. Every `OTF_*` value is validated before it reaches a URL or a path.
4. The scripts never elevate privileges.
5. The `@@…@@` placeholders stay; get.otfabric.io depends on them.
6. Never skip or delete tests to make CI pass.

## Commands

| When you change… | Run |
|---|---|
| anything | `make check` |
| `tools.json` | `make registry`, then `make check` |
| `install.ps1` | CI (`windows` job); Pester needs Windows |
| the tool list against the organisation | `make org-scan` (needs `gh`) |

## Definition of Done

`make check` green, CI green on every platform, RELEASE.md section for
user-visible changes.

## Git and releases

The maintainer works on `main` in this repository. Do not tag unless the
maintainer asks in the session.
