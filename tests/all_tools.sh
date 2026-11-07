#!/bin/sh
# Install every tool in the registry through the live service, each into its
# own directory, and run it. Writes "<tool> <ok|fail> <version or reason>"
# lines to $1 and exits 1 if any tool failed.
#
#   sh tests/all_tools.sh results.txt
#
# BASE (default https://get.otfabric.io) selects the service.
set -u

out=${1:?usage: all_tools.sh RESULTS_FILE}
base=${BASE:-https://get.otfabric.io}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: >"$out"

if ! curl -fsSL "$base/tools.json" -o "$work/tools.json"; then
  echo "cannot fetch $base/tools.json" >&2
  exit 1
fi
tools=$(python3 -I -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1])))))' "$work/tools.json")

failed=0
for tool in $tools; do
  dir="$work/$tool"
  echo "::group::$tool"
  if curl -fsSL "$base/$tool" | env OTF_UNMANAGED_INSTALL="$dir" sh &&
    ver=$("$dir/$tool" version </dev/null 2>&1 | head -n 1); then
    echo "$tool ok $ver" >>"$out"
  else
    echo "$tool fail see log" >>"$out"
    failed=1
  fi
  echo "::endgroup::"
done

cat "$out"
exit "$failed"
