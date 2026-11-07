#!/usr/bin/env python3
"""Keep install.sh, install.ps1 and the README tools table equal to tools.json.

  scripts/registry.py          rewrite both blocks
  scripts/registry.py --check  exit 1 when a block is out of date
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPO = re.compile(r"^otfabric/[A-Za-z0-9._-]+$")


def load():
    data = json.loads((ROOT / "tools.json").read_text())
    tools = data["tools"]
    for name, entry in tools.items():
        if not NAME.match(name):
            sys.exit(f"tools.json: invalid tool name {name!r}")
        if not REPO.match(entry.get("repo", "")):
            sys.exit(f"tools.json: {name}: invalid repo {entry.get('repo')!r}")
        if entry.get("kind") not in ("cli", "embedded"):
            sys.exit(f"tools.json: {name}: kind must be cli or embedded")
        if not entry.get("summary"):
            sys.exit(f"tools.json: {name}: summary is required")
    overlap = set(tools) & set(data.get("deferred", {}))
    if overlap:
        sys.exit(f"tools.json: both registered and deferred: {sorted(overlap)}")
    return dict(sorted(tools.items()))


def sh_block(tools):
    lines = ["otf_repo_for() {", '  case "$1" in']
    lines += [f"    {n}) echo {e['repo']} ;;" for n, e in tools.items()]
    lines += ["    *) return 1 ;;", "  esac", "}"]
    return "\n".join(lines)


def ps1_block(tools):
    lines = ["  $Registry = @{"]
    lines += [f"    '{n}' = '{e['repo']}'" for n, e in tools.items()]
    lines += ["  }"]
    return "\n".join(lines)


def readme_block(tools):
    lines = ["| Tool | Kind | Protocol | Repository | Summary |", "|---|---|---|---|---|"]
    for n, e in tools.items():
        lines.append(
            f"| `{n}` | {e['kind']} | {e.get('protocol', '')} | "
            f"[{e['repo']}](https://github.com/{e['repo']}) | {e['summary']} |"
        )
    return "\n".join(lines)


def replace_readme(path, block):
    text = path.read_text()
    pattern = re.compile(r"(<!-- tools:start -->\n)(.*?)(<!-- tools:end -->)", re.S)
    if not pattern.search(text):
        sys.exit("README.md: tools markers not found")
    return text, pattern.sub(lambda m: m.group(1) + block + "\n" + m.group(3), text)


def replace(path, block, indent):
    text = path.read_text()
    pattern = re.compile(
        rf"(^{indent}# >>> registry >>>\n)(.*?)(^{indent}# <<< registry <<<$)",
        re.S | re.M,
    )
    if not pattern.search(text):
        sys.exit(f"{path.name}: registry markers not found")
    return text, pattern.sub(lambda m: m.group(1) + block + "\n" + m.group(3), text)


def main():
    check = "--check" in sys.argv[1:]
    tools = load()
    stale = []
    for name, block, indent in (
        ("install.sh", sh_block(tools), ""),
        ("install.ps1", ps1_block(tools), "  "),
    ):
        path = ROOT / name
        old, new = replace(path, block, indent)
        if old != new:
            if check:
                stale.append(name)
            else:
                path.write_text(new)
                print(f"updated {name}")
    path = ROOT / "README.md"
    old, new = replace_readme(path, readme_block(tools))
    if old != new:
        if check:
            stale.append("README.md")
        else:
            path.write_text(new)
            print("updated README.md")
    if stale:
        sys.exit(f"registry out of date in {', '.join(stale)}; run `make registry`")


if __name__ == "__main__":
    main()
