#!/bin/sh
# OT Fabric installer for Linux and macOS.
#
#   curl -fsSL https://get.otfabric.io/<tool> | sh
#
# Environment (all optional):
#   OTF_VERSION            latest (default), or X.Y.Z / vX.Y.Z
#   OTF_INSTALL_DIR        install directory; PATH may be updated (managed)
#   OTF_UNMANAGED_INSTALL  install directory; PATH and profiles untouched
#   OTF_NO_MODIFY_PATH=1   managed install without profile changes
#   OTF_TARGET             override detection: linux-amd64, linux-arm64,
#                          linux-armv7, darwin-amd64, darwin-arm64
#   OTF_TOOL               tool name, when this script is not served for one
#
# Exit codes: 0 installed, 1 installation failed, 2 invalid input.
# Source and documentation: https://github.com/otfabric/install

set -u

# Filled in by get.otfabric.io when it serves this script. Left as they are,
# the script talks to GitHub directly (the fallback when the service is down).
OTF_SERVED_TOOL='@@TOOL@@'
OTF_SERVED_BASE='@@BASE_URL@@'
OTF_INSTALLER_VERSION='@@INSTALLER_VERSION@@'

# Tool -> GitHub repository, for the direct-to-GitHub fallback.
# Generated from tools.json (make registry); tests keep the two equal.
# >>> registry >>>
otf_repo_for() {
  case "$1" in
    bacnetctl) echo otfabric/bacnetctl ;;
    canbusctl) echo otfabric/canbusctl ;;
    canopenctl) echo otfabric/canopenctl ;;
    dnp3ctl) echo otfabric/dnp3ctl ;;
    ethernetipctl) echo otfabric/ethernetipctl ;;
    iec101ctl) echo otfabric/iec60870ctl ;;
    iec102ctl) echo otfabric/iec60870ctl ;;
    iec103ctl) echo otfabric/iec60870ctl ;;
    iec104ctl) echo otfabric/iec60870ctl ;;
    iec61850ctl) echo otfabric/iec61850ctl ;;
    ieee20305ctl) echo otfabric/ieee20305ctl ;;
    knxctl) echo otfabric/knxctl ;;
    mbcapctl) echo otfabric/go-modbus-capture ;;
    mbtracectl) echo otfabric/go-modbus-trace ;;
    modbus-cli) echo otfabric/go-modbus ;;
    modbusctl) echo otfabric/modbusctl ;;
    nsdctl) echo otfabric/go-iec61850-model ;;
    ocppctl) echo otfabric/ocppctl ;;
    opcuactl) echo otfabric/opcuactl ;;
    openadrctl) echo otfabric/openadrctl ;;
    otprobe) echo otfabric/go-otfp ;;
    profinetctl) echo otfabric/profinetctl ;;
    s7commctl) echo otfabric/s7commctl ;;
    sclgen) echo otfabric/go-iec61850 ;;
    sclparse) echo otfabric/go-iec61850 ;;
    sparkplugbctl) echo otfabric/sparkplugbctl ;;
    sunspecctl) echo otfabric/sunspecctl ;;
    *) return 1 ;;
  esac
}
# <<< registry <<<

PATH_MARKER='# added by the OT Fabric installer'

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Placeholder check without spelling the placeholder, so that filling it in
# does not also rewrite the check.
unfilled() {
  case "$1" in "@@"*"@@") return 0 ;; *) return 1 ;; esac
}

# fail <stage> <message>: report the failure to the service and stop.
fail() {
  stage=$1
  shift
  printf 'error: %s\n' "$*" >&2
  report fail "$stage"
  exit 1
}

usage_error() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

has() { command -v "$1" >/dev/null 2>&1; }

clean_field() {
  # Keep User-Agent fields to a safe character set.
  printf '%s' "$1" | tr -c 'A-Za-z0-9._ +-' ' ' | tr -s ' ' | sed 's/^ //; s/ $//' | cut -c1-40
}

# ---------------------------------------------------------------- download

# fetch <url> <output file>
fetch() {
  case "$DOWNLOADER" in
    curl)
      curl --fail --silent --show-error --location --proto "$CURL_PROTO" --proto-redir "$CURL_PROTO" \
        --retry 3 --connect-timeout 15 \
        --user-agent "$UA" --header "X-OTF-Install: $INSTALL_ID" \
        --header "X-OTF-Requested: $REQUESTED" \
        --output "$2" "$1" ;;
    wget)
      wget --quiet ${WGET_HTTPS_ONLY:+--https-only} --tries=3 --timeout=30 \
        --user-agent="$UA" --header="X-OTF-Install: $INSTALL_ID" \
        --header="X-OTF-Requested: $REQUESTED" \
        --output-document="$2" "$1" ;;
    busybox-wget)
      # BusyBox wget: short options only, no retries, no protocol pinning.
      wget -q -T 30 -U "$UA" --header "X-OTF-Install: $INSTALL_ID" \
        --header "X-OTF-Requested: $REQUESTED" -O "$2" "$1" ;;
  esac
}

# fetch_text <url>: body on stdout.
fetch_text() {
  fetch "$1" - 2>/dev/null || return 1
}

# report ok|fail [stage]: one silent request with the outcome. Never fails.
report() {
  [ "$MODE_DIRECT" = 1 ] && return 0
  [ -n "${BASE:-}" ] || return 0
  url="$BASE/r/$TOOL?v=${VERSION:-}&t=${TARGET:-}&s=$1&stage=${2:-}"
  case "${DOWNLOADER:-}" in
    curl)
      curl --silent --max-time 2 --proto "$CURL_PROTO" --user-agent "$UA" \
        --header "X-OTF-Install: $INSTALL_ID" --header "X-OTF-Requested: $REQUESTED" \
        --output /dev/null "$url" >/dev/null 2>&1 ;;
    wget)
      wget --quiet --tries=1 --timeout=2 --user-agent="$UA" \
        --header="X-OTF-Install: $INSTALL_ID" --header="X-OTF-Requested: $REQUESTED" \
        --output-document=/dev/null "$url" >/dev/null 2>&1 ;;
    busybox-wget)
      wget -q -T 2 -U "$UA" --header "X-OTF-Install: $INSTALL_ID" \
        --header "X-OTF-Requested: $REQUESTED" -O /dev/null "$url" >/dev/null 2>&1 ;;
  esac
  return 0
}

# ---------------------------------------------------------------- detection

# 32 or 64: the word size of the running userland, which can differ from the
# kernel's (a 64-bit kernel with a 32-bit Raspberry Pi OS, for example).
userland_bits() {
  if [ "$(uname -s)" = Linux ] && [ -r /bin/sh ]; then
    # ELF header byte 5 (EI_CLASS): 1 = 32-bit, 2 = 64-bit.
    class=$(od -An -t u1 -j 4 -N 1 /bin/sh 2>/dev/null | tr -d ' ')
    case "$class" in
      1) echo 32; return ;;
      2) echo 64; return ;;
    esac
  fi
  getconf LONG_BIT 2>/dev/null || echo 64
}

detect_target() {
  os=$(uname -s 2>/dev/null)
  arch=$(uname -m 2>/dev/null)
  case "$os" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT)
      usage_error "on Windows, use PowerShell: irm https://get.otfabric.io/$TOOL.ps1 | iex" ;;
    *) usage_error "unsupported operating system: $os" ;;
  esac

  bits=$(userland_bits)
  case "$arch" in
    x86_64 | amd64)
      [ "$bits" = 32 ] && usage_error "32-bit x86 userland is not supported"
      arch=amd64 ;;
    aarch64 | arm64)
      # A 64-bit kernel with a 32-bit userland (common on Raspberry Pi OS)
      # needs the 32-bit binary.
      if [ "$os" = linux ] && [ "$bits" = 32 ]; then arch=armv7; else arch=arm64; fi ;;
    armv7* | armv8l) arch=armv7 ;;
    armv6* | armv5*) usage_error "ARMv6 and older are not supported (need ARMv7 or newer)" ;;
    i386 | i486 | i586 | i686) usage_error "32-bit x86 is not supported" ;;
    *) usage_error "unsupported architecture: $arch" ;;
  esac

  # An x86_64 shell under Rosetta on Apple silicon: prefer the native binary.
  if [ "$os" = darwin ] && [ "$arch" = amd64 ]; then
    if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 ]; then arch=arm64; fi
  fi
  printf '%s-%s' "$os" "$arch"
}

os_detail() {
  case "$TARGET" in
    linux-*)
      if [ -r /etc/os-release ]; then
        # Read, not sourced: only two fields, quotes removed.
        id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n1)
        ver=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n1)
        clean_field "${id:-linux} $ver"
      else
        printf 'linux'
      fi ;;
    darwin-*) clean_field "macos $(sw_vers -productVersion 2>/dev/null)" ;;
  esac
}

shell_name() {
  if [ -n "${BASH_VERSION:-}" ]; then printf 'bash'; return; fi
  if [ -n "${ZSH_VERSION:-}" ]; then printf 'zsh'; return; fi
  exe=$(readlink "/proc/$$/exe" 2>/dev/null || true)
  case "$exe" in
    *busybox*) printf 'busybox' ;;
    "") printf 'sh' ;;
    *) clean_field "${exe##*/}" ;;
  esac
}

ci_name() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then printf 'github-actions'
  elif [ -n "${GITLAB_CI:-}" ]; then printf 'gitlab-ci'
  elif [ -n "${JENKINS_URL:-}" ]; then printf 'jenkins'
  elif [ -n "${TF_BUILD:-}" ]; then printf 'azure-pipelines'
  elif [ -n "${BITBUCKET_BUILD_NUMBER:-}" ]; then printf 'bitbucket'
  elif [ -n "${CIRCLECI:-}" ]; then printf 'circleci'
  elif [ -n "${BUILDKITE:-}" ]; then printf 'buildkite'
  elif [ -n "${CI:-}" ]; then printf 'ci'
  else printf '-'
  fi
}

new_install_id() {
  id=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  [ -n "$id" ] || id=$(printf '%08x%08x' "$(date +%s)" "$$")
  printf '%s' "$id"
}

# ---------------------------------------------------------------- checksums

sha256_of() {
  if has sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif has shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif has openssl; then openssl dgst -sha256 -r "$1" | awk '{print $1}'
  else return 1
  fi
}

# ---------------------------------------------------------------- PATH

path_contains() {
  case ":${PATH}:" in *":$1:"*) return 0 ;; *) return 1 ;; esac
}

# add_path_line <file> <line>: append once, creating the file if needed.
add_path_line() {
  if [ -f "$1" ] && grep -F -q -- "$2" "$1" 2>/dev/null; then
    return 1
  fi
  mkdir -p "$(dirname "$1")" 2>/dev/null
  printf '\n%s\n%s\n' "$PATH_MARKER" "$2" >>"$1" 2>/dev/null || return 1
  return 0
}

configure_path() {
  dir=$1
  posix_line="case \":\${PATH}:\" in *\":$dir:\"*) ;; *) export PATH=\"$dir:\$PATH\" ;; esac"
  changed=""
  if add_path_line "$HOME/.profile" "$posix_line"; then changed="$changed ~/.profile"; fi
  for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$rc" ] && add_path_line "$rc" "$posix_line"; then changed="$changed ~/${rc##*/}"; fi
  done
  zrc="${ZDOTDIR:-$HOME}/.zshrc"
  if [ -f "$zrc" ] || [ "$(basename "${SHELL:-}")" = zsh ]; then
    if add_path_line "$zrc" "$posix_line"; then changed="$changed $zrc"; fi
  fi
  if [ -d "$HOME/.config/fish" ]; then
    fish_line="contains -- \"$dir\" \$PATH; or set -gx PATH \"$dir\" \$PATH"
    if add_path_line "$HOME/.config/fish/conf.d/otfabric.fish" "$fish_line"; then
      changed="$changed ~/.config/fish/conf.d/otfabric.fish"
    fi
  fi
  if [ -n "$changed" ]; then
    say "Added $dir to PATH in:$changed"
    say "Open a new terminal, or run:  export PATH=\"$dir:\$PATH\""
  fi
}

# ---------------------------------------------------------------- main

main() {
  # Tool: served name, then the first argument, then OTF_TOOL.
  TOOL=$OTF_SERVED_TOOL
  if unfilled "$TOOL"; then TOOL=${1:-${OTF_TOOL:-}}; fi
  [ -n "$TOOL" ] || usage_error "no tool given; usage: sh install.sh <tool>  (see https://get.otfabric.io/)"
  case "$TOOL" in
    *[!a-z0-9-]* | -*) usage_error "invalid tool name: $TOOL" ;;
  esac

  if unfilled "$OTF_INSTALLER_VERSION"; then OTF_INSTALLER_VERSION=dev; fi

  # Service or direct-to-GitHub. OTF_BASE_URL is for testing against a local server.
  BASE=${OTF_BASE_URL:-$OTF_SERVED_BASE}
  MODE_DIRECT=0
  if unfilled "$BASE"; then BASE=""; MODE_DIRECT=1; fi
  BASE=${BASE%/}

  CURL_PROTO="=https"
  WGET_HTTPS_ONLY=1
  case "$BASE" in
    "" | https://*) ;;
    http://127.0.0.1:* | http://localhost:*) CURL_PROTO="=http,https"; WGET_HTTPS_ONLY="" ;;
    *) usage_error "OTF_BASE_URL must be https" ;;
  esac

  if has curl; then
    DOWNLOADER=curl
  elif has wget; then
    DOWNLOADER=wget
    if wget --help 2>&1 | grep -qi busybox; then DOWNLOADER=busybox-wget; fi
  else
    DOWNLOADER=""
    usage_error "curl or wget is required"
  fi
  for cmd in uname tar mkdir mv chmod rm awk sed; do
    has "$cmd" || usage_error "required command not found: $cmd"
  done

  REPO=""
  if [ "$MODE_DIRECT" = 1 ]; then
    REPO=$(otf_repo_for "$TOOL") || usage_error "unknown tool: $TOOL (see https://github.com/otfabric/install#tools)"
  fi

  # Install directory and mode.
  if [ -n "${OTF_UNMANAGED_INSTALL:-}" ] && [ -n "${OTF_INSTALL_DIR:-}" ]; then
    usage_error "set OTF_INSTALL_DIR or OTF_UNMANAGED_INSTALL, not both"
  fi
  if [ -n "${OTF_UNMANAGED_INSTALL:-}" ]; then
    DEST=$OTF_UNMANAGED_INSTALL
    MODE=unmanaged
  else
    DEST=${OTF_INSTALL_DIR:-${XDG_BIN_HOME:-${HOME:?HOME is not set}/.local/bin}}
    MODE=managed
  fi
  case "$DEST" in
    /*) ;;
    *) DEST="$(pwd)/$DEST" ;;
  esac

  # Version as requested, validated before it reaches a URL.
  REQUESTED=${OTF_VERSION:-latest}
  REQUESTED=${REQUESTED#v}
  if [ "$REQUESTED" != latest ]; then
    printf '%s' "$REQUESTED" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' ||
      usage_error "invalid OTF_VERSION: ${OTF_VERSION:-} (expected X.Y.Z)"
  fi

  if [ -n "${OTF_TARGET:-}" ]; then
    case "$OTF_TARGET" in
      linux-amd64 | linux-arm64 | linux-armv7 | darwin-amd64 | darwin-arm64) TARGET=$OTF_TARGET ;;
      *) usage_error "invalid OTF_TARGET: $OTF_TARGET" ;;
    esac
  else
    TARGET=$(detect_target) || exit 2
  fi

  INSTALL_ID=$(new_install_id)
  CI_NAME=$(ci_name)
  UA="otfabric-install/$OTF_INSTALLER_VERSION (sh; $TARGET; $(os_detail); $(shell_name); $MODE; $CI_NAME)"
  VERSION=""

  # Resolve once; everything after uses this exact version.
  if [ "$REQUESTED" = latest ]; then
    if [ "$MODE_DIRECT" = 1 ]; then
      VERSION=$(fetch_text "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
    else
      VERSION=$(fetch_text "$BASE/$TOOL/latest" 2>/dev/null | tr -d '\r\n ')
    fi
    printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' ||
      fail resolve "could not determine the latest version of $TOOL; retry, or set OTF_VERSION"
  else
    VERSION=$REQUESTED
  fi

  ARCHIVE="$TOOL-$VERSION-$TARGET.tar.gz"
  SUMS="$TOOL-$VERSION-checksums.txt"
  MEMBER="$TOOL-$VERSION-$TARGET"
  if [ "$MODE_DIRECT" = 1 ]; then
    URL_BASE="https://github.com/$REPO/releases/download/v$VERSION"
  else
    URL_BASE="$BASE/dl/$TOOL/$VERSION"
  fi

  say "Installing $TOOL $VERSION ($TARGET) into $DEST"

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t otfabric) || fail download "cannot create a temporary directory"
  trap 'rm -rf "$TMP"' EXIT
  trap 'rm -rf "$TMP"; exit 130' INT TERM

  fetch "$URL_BASE/$SUMS" "$TMP/$SUMS" ||
    fail download "$TOOL $VERSION has no published checksums; the version may not exist or is still being published"
  fetch "$URL_BASE/$ARCHIVE" "$TMP/$ARCHIVE" ||
    fail download "could not download $ARCHIVE"

  expected=$(awk -v f="$ARCHIVE" '$2 == f || $2 == "*" f {print $1}' "$TMP/$SUMS" | head -n1 | tr 'A-F' 'a-f')
  printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$' ||
    fail checksum "no checksum for $ARCHIVE in $SUMS"
  actual=$(sha256_of "$TMP/$ARCHIVE") || fail checksum "sha256sum, shasum or openssl is required"
  [ "$actual" = "$expected" ] ||
    fail checksum "checksum mismatch for $ARCHIVE (expected $expected, got $actual)"

  mkdir -p "$TMP/x"
  tar -xzf "$TMP/$ARCHIVE" -C "$TMP/x" "$MEMBER" 2>/dev/null ||
    fail extract "$ARCHIVE does not contain $MEMBER"
  if [ ! -f "$TMP/x/$MEMBER" ] || [ -L "$TMP/x/$MEMBER" ]; then
    fail extract "$MEMBER in $ARCHIVE is not a regular file"
  fi
  chmod 755 "$TMP/x/$MEMBER"

  # Smoke test before replacing anything.
  # Every OT Fabric CLI has a `version` subcommand (none has a --version flag).
  # stdin is closed: under `curl | sh` it holds the rest of this script.
  if ! "$TMP/x/$MEMBER" version </dev/null >/dev/null 2>&1; then
    fail smoke "$TOOL $VERSION does not run on this system ($TARGET)"
  fi

  mkdir -p "$DEST" 2>/dev/null || fail install "cannot create $DEST"
  [ -w "$DEST" ] || fail install "$DEST is not writable; choose another OTF_INSTALL_DIR or run with the required rights"
  staged="$DEST/.$TOOL.new.$$"
  cp "$TMP/x/$MEMBER" "$staged" 2>/dev/null || { rm -f "$staged"; fail install "cannot write to $DEST"; }
  chmod 755 "$staged"
  mv -f "$staged" "$DEST/$TOOL" || { rm -f "$staged"; fail install "cannot replace $DEST/$TOOL"; }

  report ok

  say "Installed $TOOL $VERSION to $DEST/$TOOL"
  if [ "$MODE" = managed ] && [ "${OTF_NO_MODIFY_PATH:-0}" != 1 ] && ! path_contains "$DEST"; then
    configure_path "$DEST"
  elif ! path_contains "$DEST"; then
    say "$DEST is not on your PATH; add it, or run $DEST/$TOOL"
  fi
  found=$(command -v "$TOOL" 2>/dev/null || true)
  if [ -n "$found" ] && [ "$found" != "$DEST/$TOOL" ]; then
    warn "another $TOOL comes first on your PATH: $found"
  fi
  say "Run '$TOOL --help' to get started."
}

main "$@"
