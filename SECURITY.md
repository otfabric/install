# Security policy

## Reporting a vulnerability

Report privately to security@otfabric.io, or through GitHub Security Advisories
on this repository (<https://github.com/otfabric/install/security/advisories/new>).
Do not open a public issue. Expect an acknowledgement within 5 working days.

## Supported versions

| Version | Supported |
|---|---|
| The version served by get.otfabric.io (latest tag) | ✓ |
| Older tags | ✗ |

## Threat model

The scripts run with the user's rights, from a pipe (`curl | sh`, `irm | iex`).
They download a release archive of an OT Fabric tool and install one binary.

| Input | Trust | Handling |
|---|---|---|
| The script itself | Trusted as far as the TLS connection to get.otfabric.io or raw.githubusercontent.com | Served over HTTPS only; `curl` is pinned to HTTPS for the request and every redirect (`--proto =https --proto-redir =https`), `wget` uses `--https-only` where available |
| `OTF_*` environment variables | User input | Tool names are checked against `[a-z0-9-]`, versions against a strict `X.Y.Z` pattern and targets against a fixed list before they reach a URL or a path; `OTF_BASE_URL` (testing only) must be HTTPS or `http://127.0.0.1` / `http://localhost` |
| Version returned by get.otfabric.io or the GitHub API | Untrusted | Must match the same strict version pattern |
| Checksums file | Integrity only | The archive's SHA-256 must match its line exactly; a missing, malformed or mismatching entry stops the install before extraction |
| Archive | Untrusted until verified | Only the expected member (`<tool>-<version>-<target>[.exe]`) is extracted; it must be a regular file, not a link |
| Downloaded binary | Verified archive member | Run once (`version`, stdin closed) before it replaces an installed copy |

What the checksum does **not** prove: the checksums file comes from the same
GitHub release as the archive, so it proves the download is intact, not who
published it. Anyone able to replace release assets could replace both.
Build provenance attestations are planned (`gh attestation verify`).

## Secure defaults

- Per-user install directory; never runs `sudo` or asks for elevation.
- No option to skip checksum verification.
- PATH changes are a single marked line per shell profile, appended once, and
  are skipped entirely with `OTF_UNMANAGED_INSTALL` or `OTF_NO_MODIFY_PATH=1`.

## Data sent

When served by get.otfabric.io, the script sends a User-Agent
(`otfabric-install/<version> (<sh|ps1>; <target>; <os and version>; <shell>; <managed|unmanaged>; <ci system>)`),
a random per-run install id, the requested version, and one final request with
the outcome (`ok`, or `fail` and the failed stage). Run from this repository,
it talks only to GitHub.
