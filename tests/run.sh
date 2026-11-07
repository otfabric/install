#!/bin/sh
# End-to-end tests for install.sh against tests/fake_server.py.
#
#   tests/run.sh [shell]     e.g. tests/run.sh dash; default: sh
#
# Each case serves install.sh the way get.otfabric.io does (placeholders
# filled in) and pipes it into the shell under test, like `curl | sh`.
# Needs python3 and curl or wget.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SH_UNDER_TEST=${1:-sh}
WORK=$(mktemp -d)
PASS=0
FAILED=0

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

python3 -I "$ROOT/tests/fake_server.py" "$WORK" &
SERVER_PID=$!
i=0
while [ ! -f "$WORK/port" ]; do
  i=$((i + 1))
  [ "$i" -gt 100 ] && { echo "fake server did not start" >&2; exit 1; }
  sleep 0.1
done
BASE="http://127.0.0.1:$(cat "$WORK/port")"
cd "$WORK" || exit 1

# served <tool>: install.sh as get.otfabric.io serves it for <tool>.
served() {
  sed -e "s|@@TOOL@@|$1|" -e "s|@@BASE_URL@@|$BASE|" -e "s|@@INSTALLER_VERSION@@|9.9.9|" "$ROOT/install.sh"
}

# run_case <tool> [VAR=value ...]: fresh HOME, pipes the served script into
# the shell. Sets RC, OUT and CASE_HOME.
run_case() {
  tool=$1
  shift
  CASE_HOME=$(mktemp -d "$WORK/home.XXXXXX")
  : >"$WORK/requests.jsonl"
  OUT=$(served "$tool" | env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin" \
    HOME="$CASE_HOME" SHELL=/bin/sh "$@" "$SH_UNDER_TEST" 2>&1)
  RC=$?
}

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
not_ok() {
  FAILED=$((FAILED + 1))
  printf 'FAIL %s\n' "$1"
  printf '%s\n' "$OUT" | sed 's/^/     | /'
}
check() { # check <name> <condition...>
  name=$1
  shift
  if "$@"; then ok "$name"; else not_ok "$name"; fi
}
requests() { cat "$WORK/requests.jsonl"; }
has_request() { grep -q -- "$1" "$WORK/requests.jsonl"; }
count_in() { grep -c -F -- "$2" "$1" 2>/dev/null || true; }

# --- happy path, managed --------------------------------------------------
run_case goodtool
check "managed install exits 0" test "$RC" = 0
check "binary installed in ~/.local/bin" test -x "$CASE_HOME/.local/bin/goodtool"
check "installed binary runs" sh -c "'$CASE_HOME/.local/bin/goodtool' version | grep -q 'goodtool version: 1.2.3'"
check "PATH added to ~/.profile" grep -q '.local/bin' "$CASE_HOME/.profile"
check "latest resolved through the service" has_request '"path": "/goodtool/latest"'
check "checksums fetched through /dl/" has_request '"path": "/dl/goodtool/1.2.3/goodtool-1.2.3-'
check "outcome reported ok" has_request '"s": "ok"'
check "requested header is latest" has_request '"requested": "latest"'
check "install id sent" sh -c "grep -Eq '\"install\": \"[0-9a-f]{16}\"' '$WORK/requests.jsonl'"
check "User-Agent format" sh -c "grep -Eq '\"ua\": \"otfabric-install/9.9.9 \\(sh; (linux|darwin)-(amd64|arm64|armv7); [^;]*; [^;]+; managed; [^;)]+\\)\"' '$WORK/requests.jsonl'"
if [ -n "${EXPECT_TARGET:-}" ]; then
  check "detected target is $EXPECT_TARGET" has_request "goodtool-1.2.3-$EXPECT_TARGET.tar.gz"
fi
check "no temporary files left in install dir" sh -c "! ls -A '$CASE_HOME/.local/bin' | grep -q '^\\.'"

# Same HOME again: PATH line is not duplicated.
home=$CASE_HOME
: >"$WORK/requests.jsonl"
OUT=$(served goodtool | env -i PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" HOME="$home" SHELL=/bin/sh "$SH_UNDER_TEST" 2>&1)
RC=$?
check "reinstall exits 0" test "$RC" = 0
check "PATH line added once" test "$(count_in "$home/.profile" 'added by the OT Fabric installer')" = 1

# zsh users get ~/.zshrc too.
run_case goodtool SHELL=/bin/zsh
check "zsh: PATH added to ~/.zshrc" grep -q '.local/bin' "$CASE_HOME/.zshrc"

# Directory already on PATH: no profile edits.
run_case goodtool OTF_INSTALL_DIR=/tmp/otf-onpath-$$ PATH="/tmp/otf-onpath-$$:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
check "dir already on PATH: no ~/.profile" test ! -e "$CASE_HOME/.profile"
rm -rf "/tmp/otf-onpath-$$"

# A 64-bit ARM kernel (uname says aarch64) with a 32-bit userland needs armv7.
if [ "$(uname -s)" = Linux ]; then
  mkdir -p "$WORK/fakebin"
  cat >"$WORK/fakebin/uname" <<'EOS'
#!/bin/sh
case "$1" in -m) echo aarch64 ;; *) echo Linux ;; esac
EOS
  chmod 755 "$WORK/fakebin/uname"
  case $(od -An -t u1 -j 4 -N 1 /bin/sh | tr -d ' ') in 1) want=linux-armv7 ;; *) want=linux-arm64 ;; esac
  run_case goodtool PATH="$WORK/fakebin:/usr/bin:/bin:/usr/local/bin"
  check "aarch64 kernel picks $want for this userland" has_request "goodtool-1.2.3-$want.tar.gz"
fi

# --- pinned version, other modes ------------------------------------------
run_case goodtool OTF_VERSION=v1.0.0
check "pinned version exits 0" test "$RC" = 0
check "pinned version installed" sh -c "'$CASE_HOME/.local/bin/goodtool' version | grep -q '1.0.0'"
check "pinned version skips /latest" sh -c "! grep -q '/latest' '$WORK/requests.jsonl'"
check "requested header is the pin" has_request '"requested": "1.0.0"'

run_case goodtool OTF_UNMANAGED_INSTALL="$WORK/unmanaged"
check "unmanaged exits 0" test "$RC" = 0
check "unmanaged installs into the given dir" test -x "$WORK/unmanaged/goodtool"
check "unmanaged leaves profiles alone" test ! -e "$CASE_HOME/.profile"
check "unmanaged in User-Agent" has_request 'unmanaged;'

run_case goodtool OTF_NO_MODIFY_PATH=1
check "OTF_NO_MODIFY_PATH exits 0" test "$RC" = 0
check "OTF_NO_MODIFY_PATH leaves profiles alone" test ! -e "$CASE_HOME/.profile"

run_case goodtool OTF_INSTALL_DIR=relative/bin
check "relative OTF_INSTALL_DIR exits 0" test "$RC" = 0

run_case goodtool OTF_TARGET=linux-armv7 GITHUB_ACTIONS=true
check "OTF_TARGET is used" has_request 'goodtool-1.2.3-linux-armv7.tar.gz'
check "CI detected in User-Agent" has_request 'github-actions)'

# --- invalid input: exit 2, nothing downloaded -----------------------------
run_case goodtool OTF_VERSION='1.2;rm -rf /'
check "invalid version exits 2" test "$RC" = 2
check "invalid version downloads nothing" test ! -s "$WORK/requests.jsonl"

run_case goodtool OTF_INSTALL_DIR=/tmp/a OTF_UNMANAGED_INSTALL=/tmp/b
check "both install dirs exits 2" test "$RC" = 2

run_case goodtool OTF_TARGET=linux-mips
check "invalid target exits 2" test "$RC" = 2

run_case 'Bad;Tool'
check "invalid tool name exits 2" test "$RC" = 2

run_case goodtool OTF_BASE_URL=http://example.com
check "plain http base refused" test "$RC" = 2

# --- failures: exit 1, reported with the stage, nothing installed ---------
run_case badsum
check "checksum mismatch exits 1" test "$RC" = 1
check "checksum mismatch installs nothing" test ! -e "$CASE_HOME/.local/bin/badsum"
check "checksum mismatch reported" has_request '"stage": "checksum"'

run_case nosums
check "missing checksums exits 1" test "$RC" = 1
check "missing checksums reported as download" has_request '"stage": "download"'
check "missing checksums: archive not fetched" sh -c "! grep -q 'nosums-1.2.3-.*tar.gz' '$WORK/requests.jsonl'"

run_case nomember
check "missing member exits 1" test "$RC" = 1
check "missing member reported as extract" has_request '"stage": "extract"'

run_case linkmember
check "symlink member exits 1" test "$RC" = 1
check "symlink member reported as extract" has_request '"stage": "extract"'

run_case nolatest
check "unresolvable latest exits 1" test "$RC" = 1
check "unresolvable latest reported as resolve" has_request '"stage": "resolve"'

run_case broken OTF_UNMANAGED_INSTALL="$WORK/keep"
mkdir -p "$WORK/keep"
printf 'previous\n' >"$WORK/keep/broken"
OUT=$(served broken | env -i PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" HOME="$CASE_HOME" \
  OTF_UNMANAGED_INSTALL="$WORK/keep" "$SH_UNDER_TEST" 2>&1)
RC=$?
check "binary that does not run exits 1" test "$RC" = 1
check "previous binary kept on smoke failure" grep -q previous "$WORK/keep/broken"

mkdir -p "$WORK/ro"
chmod 555 "$WORK/ro"
if [ ! -w "$WORK/ro" ]; then
  run_case goodtool OTF_UNMANAGED_INSTALL="$WORK/ro"
  check "read-only install dir exits 1" test "$RC" = 1
  check "read-only install dir reported as install" has_request '"stage": "install"'
fi
chmod 755 "$WORK/ro"

# --- direct-to-GitHub fallback (no network needed for these) --------------
OUT=$(env -i PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" HOME="$WORK" "$SH_UNDER_TEST" "$ROOT/install.sh" no-such-tool 2>&1)
RC=$?
check "direct mode: unknown tool exits 2" test "$RC" = 2
OUT=$(env -i PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" HOME="$WORK" "$SH_UNDER_TEST" "$ROOT/install.sh" 2>&1)
RC=$?
check "direct mode: no tool exits 2" test "$RC" = 2

printf '\n%s passed, %s failed (%s)\n' "$PASS" "$FAILED" "$SH_UNDER_TEST"
[ "$FAILED" = 0 ]
