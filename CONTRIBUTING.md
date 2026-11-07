# Contributing

## Adding a tool

A tool can be added when its repository publishes releases with the
`otfabric/.github` `go-binary-release` workflow: assets named
`<tool>-<version>-<os>-<arch>.tar.gz` (`.zip` for Windows) for all seven
targets, a `<tool>-<version>-checksums.txt`, each archive holding
`<tool>-<version>-<os>-<arch>[.exe]`, and a `version` subcommand.

1. Add it to `tools.json` (`repo`, `kind`: `cli` or `embedded`, `protocol`, `summary`), and remove it from `deferred` if it was there.
2. `make registry` regenerates the registry blocks in both scripts and the README table.
3. `make check`.
4. After merging, tag a release (below); get.otfabric.io serves it once the engineering deploy pin is moved to the new tag.

The weekly `org-scan` CI job fails when a repository releases a binary that is
neither registered nor deferred.

## Changing the scripts

- `install.sh` is POSIX `sh`: no bashisms, nothing beyond `curl`/`wget`, `tar`,
  `awk`, `sed`, `grep`, `od` and a SHA-256 tool. `make lint` runs shellcheck.
- `install.ps1` runs on Windows PowerShell 5.1 and PowerShell 7, under
  `irm | iex`: never `exit` outside the final file-mode check, no classes.
- Keep the `@@TOOL@@`, `@@BASE_URL@@` and `@@INSTALLER_VERSION@@` placeholders:
  get.otfabric.io fills them in.
- A behaviour change needs a case in `tests/run.sh` and, for Windows,
  `tests/install.Tests.ps1`.

## Releasing

1. Add a `## vX.Y.Z` section to RELEASE.md, ending with `---`.
2. Tag `main`: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. The engineering repository's daily check opens a PR that moves the deploy
   pin to the new tag; deploying it puts the new scripts on get.otfabric.io.
