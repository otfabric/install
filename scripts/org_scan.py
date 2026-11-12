#!/usr/bin/env python3
"""Find released binaries in the otfabric organisation that tools.json misses.

Lists every public repository's workflows that call the shared
go-binary-release workflow, reads their `binary-name:` inputs, and fails when
a binary is neither registered under "tools" nor listed under "deferred". A
repository with a release workflow of its own (several tools from one
repository, as otfabric/iec60870ctl) declares what it releases with a comment
line `# binary-names: tool1 tool2 ...` in that workflow. A binary may be
released by more than one repository (one that moved, while the old repository
still exists); it is fine when one of them is the registered one.
Needs the GitHub CLI (`gh`) with any token.
"""

import base64
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORG = "otfabric"


def gh(*args):
    out = subprocess.run(["gh", "api", *args], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def main():
    data = json.loads((ROOT / "tools.json").read_text())
    known = set(data["tools"]) | set(data.get("deferred", {}))
    registered_repo = {n: e["repo"] for n, e in data["tools"].items()}

    # One name per line: --paginate with --jq prints one result per page.
    repos = subprocess.run(
        ["gh", "api", "--paginate", f"orgs/{ORG}/repos?type=public&per_page=100",
         "--jq", ".[] | select(.archived | not) | .name"],
        check=True, capture_output=True, text=True,
    ).stdout.split()
    found = {}
    for repo in sorted(repos):
        if repo == ".github":
            continue  # defines the reusable workflow and its binary-name input
        try:
            files = gh(f"repos/{ORG}/{repo}/contents/.github/workflows")
        except subprocess.CalledProcessError:
            continue
        for f in files:
            if not f["name"].endswith((".yml", ".yaml")):
                continue
            content = gh(f"repos/{ORG}/{repo}/contents/{f['path']}")
            text = base64.b64decode(content["content"]).decode("utf-8", "replace")
            names = []
            if "go-binary-release.yml" in text:
                names += re.findall(r"^\s*binary-name:\s*['\"]?([A-Za-z0-9_-]+)", text, re.M)
            for line in re.findall(r"^#\s*binary-names:\s*(.+)$", text, re.M):
                names += re.findall(r"[A-Za-z0-9_-]+", line)
            for name in names:
                found.setdefault(name, set()).add(f"{ORG}/{repo}")

    missing = sorted(n for n in found if n not in known)
    moved = sorted(n for n in found if n in registered_repo and registered_repo[n] not in found[n])
    for n in sorted(found):
        print(f"{n:24} {', '.join(sorted(found[n]))}{'  (MISSING)' if n in missing else ''}")
    problems = []
    if missing:
        problems.append("not in tools.json (register or defer): " + ", ".join(missing))
    if moved:
        problems.append("registered under another repository: " + ", ".join(f"{n} -> {', '.join(sorted(found[n]))}" for n in moved))
    gone = sorted(n for n in registered_repo if n not in found)
    if gone:
        problems.append("registered but no longer released by any repository: " + ", ".join(gone))
    if problems:
        sys.exit("\n".join(problems))


if __name__ == "__main__":
    main()
