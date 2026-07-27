#!/usr/bin/env bash
#
# One-command installer for this Neovim configuration.
#
# Supports macOS (Homebrew), Debian/Ubuntu (apt) and Fedora/RHEL (dnf).
# Safe to re-run: every step checks before acting.
#
# Remote (clones the config for you):
#   curl -fsSL https://raw.githubusercontent.com/numycode/nvim-config/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --check
#
# Local (from a clone):
#   ./install.sh              install everything
#   ./install.sh --check      report what is missing, change nothing
#   ./install.sh --dry-run    print the commands instead of running them
#   ./install.sh --help       full option list

set -euo pipefail

readonly NVIM_MIN_MAJOR=0
# 0.12, not 0.11: nvim-treesitter's main branch calls vim.list.unique(), which
# does not exist before 0.12, and parser installation fails without it. No
# distro packages 0.12 yet, so this normally means the upstream tarball.
readonly NVIM_MIN_MINOR=12
readonly NERD_FONT="JetBrainsMono"

# Overridable so a fork or branch can be installed:
#   NVIM_CONFIG_REPO=https://github.com/you/fork.git curl ... | bash
readonly REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/numycode/nvim-config.git}"
readonly REPO_BRANCH="${NVIM_CONFIG_BRANCH:-main}"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# When piped from curl there is no script file on disk, so BASH_SOURCE points at
# something like /dev/fd/63. In that case REPO_DIR is empty and we clone.
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  REPO_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
else
  REPO_DIR=""
fi
BOOTSTRAP=false

DRY_RUN=false
CHECK_ONLY=false
ASSUME_YES=false
SKIP_FONT=false
SKIP_OPTIONAL=false
SKIP_SYNC=false

OS=""          # macos | linux
DISTRO=""      # debian | fedora | macos
PKG=""         # brew | apt | dnf
ARCH=""        # x86_64 | arm64
SUDO=""

MISSING=()
INSTALLED=()
SKIPPED=()
WARNINGS=()

# ---------------------------------------------------------------- output ----

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""; C_BOLD=""
fi

info()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; WARNINGS+=("$*"); }
err()   { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step()  { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
die()   { err "$*"; exit 1; }

# Run a command, honouring --dry-run.
run() {
  if $DRY_RUN; then
    printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  $ASSUME_YES && return 0
  $DRY_RUN && return 0
  # Piped from curl, stdin is the script itself, so prompt on the terminal.
  # With no terminal at all (CI), decline rather than hang.
  if [[ ! -r /dev/tty ]]; then
    warn "no terminal available to confirm: $1 (pass --yes to accept)"
    return 1
  fi
  local reply
  printf '  %s?%s %s [y/N] ' "$C_YELLOW" "$C_RESET" "$1"
  read -r reply </dev/tty || return 1
  [[ "$reply" =~ ^[Yy]$ ]]
}

# True when the directory holds this Neovim configuration.
is_config_repo() {
  [[ -f "$1/init.lua" && -d "$1/lua/config" && -d "$1/lua/plugins" ]]
}

usage() {
  cat <<'EOF'
Installer for this Neovim configuration.

Usage: ./install.sh [options]

Options:
  --check           Report what is missing and exit without changing anything.
  --dry-run         Print the commands that would run, but do not run them.
  -y, --yes         Do not prompt for confirmation.
  --skip-font       Do not install the Nerd Font.
  --skip-optional   Do not install optional tools (delta).
  --no-sync         Do not run the headless Neovim plugin/LSP sync at the end.
  -h, --help        Show this help.

Supported platforms:
  macOS             via Homebrew
  Debian / Ubuntu   via apt-get
  Fedora / RHEL     via dnf

Tools installed from upstream rather than the system package manager, because
distro versions are frequently too old or absent:
  neovim   when the packaged version is older than 0.12 (no distro packages it yet)
  lazygit  when not packaged (absent from Debian bookworm)
  gh       when not packaged (absent from Debian bookworm)
  uv       always, via the official Astral installer
EOF
}

# ------------------------------------------------------------- detection ----

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)         CHECK_ONLY=true ;;
      --dry-run)       DRY_RUN=true ;;
      -y|--yes)        ASSUME_YES=true ;;
      --skip-font)     SKIP_FONT=true ;;
      --skip-optional) SKIP_OPTIONAL=true ;;
      --no-sync)       SKIP_SYNC=true ;;
      -h|--help)       usage; exit 0 ;;
      *)               err "Unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
  done
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) OS="macos"; DISTRO="macos"; PKG="brew" ;;
    Linux)  OS="linux" ;;
    *)      die "Unsupported operating system: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)  ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)             die "Unsupported architecture: $(uname -m)" ;;
  esac

  if [[ "$OS" == "linux" ]]; then
    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release; unsupported Linux distribution."
    # shellcheck disable=SC1091
    . /etc/os-release
    local ids="${ID:-} ${ID_LIKE:-}"
    case " $ids " in
      *" debian "*|*" ubuntu "*) DISTRO="debian"; PKG="apt" ;;
      *" fedora "*|*" rhel "*)   DISTRO="fedora"; PKG="dnf" ;;
      *) die "Unsupported Linux distribution: ${PRETTY_NAME:-${ID:-unknown}}. Supported: Debian/Ubuntu, Fedora/RHEL." ;;
    esac
  fi

  if [[ "$OS" == "linux" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      SUDO=""
    elif have sudo; then
      SUDO="sudo"
    else
      die "Need root or sudo to install system packages, and sudo was not found."
    fi
  fi
}

# ------------------------------------------------------- package managers ----

APT_UPDATED=false

pkg_install() {
  # Install system packages by name; no-op when the list is empty.
  [[ $# -gt 0 ]] || return 0
  case "$PKG" in
    brew) run brew install "$@" ;;
    apt)
      if ! $APT_UPDATED; then
        run $SUDO apt-get update -qq
        APT_UPDATED=true
      fi
      run $SUDO apt-get install -y "$@"
      ;;
    dnf) run $SUDO dnf install -y "$@" ;;
  esac
}

# True when the package manager knows about a package.
pkg_available() {
  case "$PKG" in
    brew) brew info --formula "$1" >/dev/null 2>&1 ;;
    apt)  apt-cache show "$1" >/dev/null 2>&1 ;;
    dnf)  dnf info "$1" >/dev/null 2>&1 ;;
  esac
}

ensure_homebrew() {
  have brew && return 0
  warn "Homebrew is not installed."
  confirm "Install Homebrew now?" || die "Homebrew is required on macOS. See https://brew.sh"
  run /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # The installer does not touch the current shell's PATH.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  have brew || die "Homebrew installation did not put brew on PATH."
}

# ------------------------------------------------------------- utilities ----

readonly LOCAL_BIN="$HOME/.local/bin"

LOCAL_BIN_WARNED=false

ensure_local_bin() {
  [[ -d "$LOCAL_BIN" ]] || run mkdir -p "$LOCAL_BIN"
  case ":$PATH:" in
    *":$LOCAL_BIN:"*) return 0 ;;
  esac

  # Put it on PATH for the rest of this run, otherwise anything installed here
  # (uv, and lazygit where it is not packaged) is invisible to the steps below
  # and to the final verification.
  export PATH="$LOCAL_BIN:$PATH"

  $LOCAL_BIN_WARNED && return 0
  LOCAL_BIN_WARNED=true
  warn "$LOCAL_BIN was not on your PATH. Added it for this run; to keep it, add
      export PATH=\"\$HOME/.local/bin:\$PATH\"
      to your shell profile (~/.bashrc, ~/.zshrc)."
}

# Download to a path, preferring curl.
fetch() {
  local url="$1" dest="$2"
  if have curl; then
    run curl -fsSL "$url" -o "$dest"
  elif have wget; then
    run wget -qO "$dest" "$url"
  else
    die "Neither curl nor wget is available to download $url"
  fi
}

# nvim_version_ok <version-string>  e.g. "0.11.2"
nvim_version_ok() {
  local v="${1#v}" major minor
  major="${v%%.*}"
  v="${v#*.}"
  minor="${v%%.*}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( major > NVIM_MIN_MAJOR )) && return 0
  (( major == NVIM_MIN_MAJOR && minor >= NVIM_MIN_MINOR )) && return 0
  return 1
}

current_nvim_version() {
  have nvim || return 1
  nvim --version 2>/dev/null | head -1 | sed -E 's/^NVIM v?//'
}

github_latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
    sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -1
}

# ------------------------------------------------------- install: neovim ----

install_neovim_from_tarball() {
  local tag asset url tmp
  tag="$(github_latest_tag neovim/neovim)"
  [[ -n "$tag" ]] || die "Could not determine the latest Neovim release."

  asset="nvim-linux-${ARCH}.tar.gz"
  url="https://github.com/neovim/neovim/releases/download/${tag}/${asset}"

  info "Installing Neovim ${tag} from ${asset} into /opt/nvim"
  tmp="$(mktemp -d)"
  fetch "$url" "$tmp/nvim.tar.gz"
  run $SUDO rm -rf /opt/nvim
  run $SUDO mkdir -p /opt/nvim
  run $SUDO tar -xzf "$tmp/nvim.tar.gz" -C /opt/nvim --strip-components=1
  run $SUDO ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -rf "$tmp"
  INSTALLED+=("neovim ${tag} (upstream tarball)")
}

ensure_neovim() {
  local version
  if version="$(current_nvim_version)" && nvim_version_ok "$version"; then
    ok "neovim $version"
    return 0
  fi

  if [[ -n "${version:-}" ]]; then
    warn "neovim $version is older than the required 0.${NVIM_MIN_MINOR}"
  else
    MISSING+=("neovim")
  fi
  if $CHECK_ONLY; then
    [[ -n "${version:-}" ]] || warn "neovim is not installed"
    return 0
  fi

  case "$DISTRO" in
    macos)
      pkg_install neovim
      INSTALLED+=("neovim")
      ;;
    debian|fedora)
      # Try the distro package first, but only keep it if it is new enough.
      if pkg_available neovim; then
        pkg_install neovim || true
      fi
      if version="$(current_nvim_version)" && nvim_version_ok "$version"; then
        ok "neovim $version (from $PKG)"
        INSTALLED+=("neovim $version")
      else
        [[ -n "${version:-}" ]] &&
          warn "packaged neovim ${version} is too old; using the upstream tarball instead"
        install_neovim_from_tarball
      fi
      ;;
  esac
}

# --------------------------------------------------------- install: base ----

ensure_base_packages() {
  local -a want=()
  # Entries are "binary:package". The binary is what we probe for; the package
  # is what we install. They differ often enough (rg/ripgrep, cc/gcc,
  # fdfind/fd-find) that conflating them silently reinstalls present tools.
  local -a spec=()

  case "$DISTRO" in
    macos)
      # git, curl, tar, gzip and unzip ship with macOS; the compiler comes from
      # the Command Line Tools.
      spec=(
        rg:ripgrep
        fd:fd
        node:node
        npm:node
        python3:python
      )
      if ! xcode-select -p >/dev/null 2>&1; then
        warn "Xcode Command Line Tools are missing (needed to compile treesitter parsers)."
        $CHECK_ONLY || run xcode-select --install || true
      else
        ok "Xcode Command Line Tools"
      fi
      ;;
    debian)
      spec=(
        git:git
        curl:curl
        unzip:unzip
        tar:tar
        gzip:gzip
        cc:build-essential
        make:build-essential
        rg:ripgrep
        node:nodejs
        npm:npm
        python3:python3
      )
      # Mason installs basedpyright and ruff from PyPI into a venv. Debian
      # splits both out of python3, and without them those two silently fail to
      # install, leaving Python with no language server.
      have pip3 || spec+=(pip3:python3-pip)
      python3 -c 'import venv' >/dev/null 2>&1 || spec+=(__venv:python3-venv)
      # Debian names the fd binary `fdfind`; either satisfies the requirement.
      have fdfind || have fd || spec+=(fd:fd-find)
      $SKIP_FONT || spec+=(fc-cache:fontconfig)
      ;;
    fedora)
      spec=(
        git:git
        curl:curl
        unzip:unzip
        tar:tar
        gzip:gzip
        cc:gcc
        make:make
        rg:ripgrep
        fd:fd-find
        node:nodejs
        npm:npm
        python3:python3
      )
      # See the Debian note above: Mason needs pip to install basedpyright/ruff.
      have pip3 || spec+=(pip3:python3-pip)
      $SKIP_FONT || spec+=(fc-cache:fontconfig)
      ;;
  esac

  local entry binary package
  for entry in "${spec[@]}"; do
    binary="${entry%%:*}"
    package="${entry##*:}"
    # A leading __ marks an entry already resolved above, not a real command.
    if [[ "$binary" == __* ]]; then
      want+=("$package")
    else
      have "$binary" || want+=("$package")
    fi
  done

  # De-duplicate (build-essential can be added twice).
  local -a uniq=()
  local p
  for p in "${want[@]:-}"; do
    [[ -z "$p" ]] && continue
    [[ " ${uniq[*]:-} " == *" $p "* ]] || uniq+=("$p")
  done

  if [[ ${#uniq[@]} -eq 0 ]]; then
    ok "base packages already present"
    return 0
  fi

  MISSING+=("${uniq[@]}")
  if $CHECK_ONLY; then
    warn "would install: ${uniq[*]}"
    return 0
  fi

  info "Installing: ${uniq[*]}"
  pkg_install "${uniq[@]}"
  INSTALLED+=("${uniq[@]}")
}

# On Debian the fd binary is installed as `fdfind`; snacks.nvim looks for `fd`.
ensure_fd_symlink() {
  [[ "$DISTRO" == "debian" ]] || return 0
  have fd && { ok "fd"; return 0; }
  have fdfind || return 0

  $CHECK_ONLY && { warn "fd is installed as fdfind; a symlink is needed"; return 0; }

  ensure_local_bin
  run ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
  ok "linked fdfind -> $LOCAL_BIN/fd"
  INSTALLED+=("fd (symlink to fdfind)")
}

# ------------------------------------------------------ install: lazygit ----

install_lazygit_from_release() {
  local tag version os_name asset url tmp
  tag="$(github_latest_tag jesseduffield/lazygit)"
  [[ -n "$tag" ]] || die "Could not determine the latest lazygit release."
  version="${tag#v}"

  case "$OS" in
    macos) os_name="Darwin" ;;
    linux) os_name="Linux" ;;
  esac

  asset="lazygit_${version}_${os_name}_${ARCH}.tar.gz"
  url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/${asset}"

  info "Installing lazygit ${tag} from ${asset}"
  ensure_local_bin
  tmp="$(mktemp -d)"
  fetch "$url" "$tmp/lazygit.tar.gz"
  run tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
  run install -m 0755 "$tmp/lazygit" "$LOCAL_BIN/lazygit"
  rm -rf "$tmp"
  INSTALLED+=("lazygit ${tag} (upstream release)")
}

ensure_lazygit() {
  have lazygit && { ok "lazygit"; return 0; }
  MISSING+=("lazygit")
  $CHECK_ONLY && { warn "lazygit is not installed"; return 0; }

  # Absent from Debian bookworm, so fall back to the upstream release.
  if pkg_available lazygit; then
    pkg_install lazygit && { INSTALLED+=("lazygit"); return 0; }
  fi
  install_lazygit_from_release
}

# ----------------------------------------------------------- install: uv ----

install_gh_from_release() {
  local tag version os_name arch_name asset url tmp
  tag="$(github_latest_tag cli/cli)"
  [[ -n "$tag" ]] || die "Could not determine the latest gh release."
  version="${tag#v}"

  # gh names its assets differently from lazygit: "macOS" not "Darwin", Go's
  # "amd64" not "x86_64", and a .zip rather than a .tar.gz on macOS. All four
  # combinations were HEAD-checked against the release URL before being written
  # here -- the naming is not guessable from the lazygit function above.
  case "$OS" in
    macos) os_name="macOS" ;;
    linux) os_name="linux" ;;
  esac

  case "$ARCH" in
    x86_64) arch_name="amd64" ;;
    arm64)  arch_name="arm64" ;;
  esac

  ensure_local_bin
  tmp="$(mktemp -d)"

  # The archive unpacks to gh_<version>_<os>_<arch>/bin/gh.
  if [[ "$OS" == "macos" ]]; then
    asset="gh_${version}_${os_name}_${arch_name}.zip"
    url="https://github.com/cli/cli/releases/download/${tag}/${asset}"
    info "Installing gh ${tag} from ${asset}"
    fetch "$url" "$tmp/gh.zip"
    run unzip -q "$tmp/gh.zip" -d "$tmp"
  else
    asset="gh_${version}_${os_name}_${arch_name}.tar.gz"
    url="https://github.com/cli/cli/releases/download/${tag}/${asset}"
    info "Installing gh ${tag} from ${asset}"
    fetch "$url" "$tmp/gh.tar.gz"
    run tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
  fi

  run install -m 0755 "$tmp/gh_${version}_${os_name}_${arch_name}/bin/gh" "$LOCAL_BIN/gh"
  rm -rf "$tmp"
  INSTALLED+=("gh ${tag} (upstream release)")
}

# Required, not optional: octo.nvim drives the whole <leader>go namespace through
# this binary. Debian bookworm does not package it, so the upstream release is
# the fallback -- same shape as lazygit above.
ensure_gh() {
  have gh && { ok "gh"; check_gh_auth; return 0; }
  MISSING+=("gh")
  $CHECK_ONLY && { warn "gh is not installed"; return 0; }

  if pkg_available gh; then
    pkg_install gh && { INSTALLED+=("gh"); check_gh_auth; return 0; }
  fi
  install_gh_from_release
  check_gh_auth
}

# Installed but signed out is the state that looks like a broken config: every
# <leader>go key fails at the point of use with a gh error. Say so here instead.
check_gh_auth() {
  $CHECK_ONLY && return 0
  gh auth status >/dev/null 2>&1 && return 0
  warn "gh is not authenticated; run 'gh auth login' to enable <leader>go"
}

ensure_uv() {
  have uv && { ok "uv"; return 0; }
  MISSING+=("uv")
  $CHECK_ONLY && { warn "uv is not installed"; return 0; }

  if [[ "$PKG" == "brew" ]]; then
    pkg_install uv
  else
    info "Installing uv via the official installer"
    if $DRY_RUN; then
      printf '  %s$ curl -LsSf https://astral.sh/uv/install.sh | sh%s\n' "$C_DIM" "$C_RESET"
    else
      # The installer drops uv into ~/.local/bin, which this shell may not have
      # on PATH yet.
      curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
      ensure_local_bin
      have uv || warn "uv installed but not found on PATH; check $LOCAL_BIN"
    fi
  fi
  INSTALLED+=("uv")
}

# ---------------------------------------------------- install: hackatime ----

install_hackatime_cli_from_release() {
  local tag os_name arch_name asset url tmp
  tag="$(github_latest_tag wakatime/wakatime-cli)"
  [[ -n "$tag" ]] || die "Could not determine the latest wakatime-cli release."

  # This project names its assets after Go's GOOS/GOARCH, which is neither what
  # detect_platform records nor what lazygit publishes.
  case "$OS" in
    macos) os_name="darwin" ;;
    linux) os_name="linux" ;;
  esac
  case "$ARCH" in
    x86_64) arch_name="amd64" ;;
    arm64)  arch_name="arm64" ;;
  esac

  asset="wakatime-cli-${os_name}-${arch_name}.zip"
  url="https://github.com/wakatime/wakatime-cli/releases/download/${tag}/${asset}"

  info "Installing wakatime-cli ${tag} from ${asset}"
  ensure_local_bin
  tmp="$(mktemp -d)"
  fetch "$url" "$tmp/wakatime-cli.zip"
  run unzip -oq "$tmp/wakatime-cli.zip" -d "$tmp"
  # The binary inside carries the same platform suffix as the archive.
  run install -m 0755 "$tmp/wakatime-cli-${os_name}-${arch_name}" "$LOCAL_BIN/wakatime-cli"
  rm -rf "$tmp"
  INSTALLED+=("wakatime-cli ${tag} (upstream release)")
}

# Installing this ourselves keeps the plugin off its own download path, which
# wants a python3 provider -- and options.lua disables every provider host.
# Finding wakatime-cli on PATH also turns the plugin's autoupdate off, so the
# version is ours to bump by re-running this script.
ensure_hackatime_cli() {
  have wakatime-cli && { ok "wakatime-cli"; return 0; }
  MISSING+=("wakatime-cli")
  $CHECK_ONLY && { warn "wakatime-cli is not installed"; return 0; }

  install_hackatime_cli_from_release
}

# ~/.wakatime.cfg holds the API key and the server URL. It is hand-maintained, so
# an existing file is never read, merged, backed up or rewritten -- we only ever
# create one that is not there, and only when the key is in the environment.
# Otherwise the user runs :WakaTimeApiKey, which writes it from inside Neovim.
ensure_hackatime_config() {
  local cfg="$HOME/.wakatime.cfg"

  if [[ -f "$cfg" ]]; then
    ok "hackatime config (existing, left alone)"
    return 0
  fi

  local key="${HACKATIME_API_KEY:-${WAKATIME_API_KEY:-}}"
  if [[ -z "$key" ]]; then
    SKIPPED+=("hackatime config (no HACKATIME_API_KEY in the environment)")
    warn "No ~/.wakatime.cfg and no HACKATIME_API_KEY set. Run :WakaTimeApiKey inside Neovim,
      or re-run with HACKATIME_API_KEY=... to have it written for you."
    return 0
  fi

  MISSING+=("hackatime config")
  $CHECK_ONLY && return 0

  local url="${HACKATIME_API_URL:-https://hackatime.hackclub.com/api/hackatime/v1}"
  info "Writing $cfg"
  if $DRY_RUN; then
    printf '  %s$ write %s (api_url=%s, api_key from environment)%s\n' "$C_DIM" "$cfg" "$url" "$C_RESET"
    return 0
  fi

  # Created empty at 0600 first: the key must never exist in a world-readable file,
  # not even for the instant between creating it and chmod'ing it.
  (umask 077 && : >"$cfg") || { warn "Could not create $cfg"; return 0; }
  printf '[settings]\napi_url = %s\napi_key = %s\n' "$url" "$key" >>"$cfg"
  INSTALLED+=("hackatime config ($cfg)")
}

# --------------------------------------------------------- install: font ----

# Detect the font itself rather than the package that may have delivered it:
# fonts are just as often installed by hand.
nerd_font_present() {
  if [[ "$OS" == "macos" ]]; then
    local dir match
    for dir in "$HOME/Library/Fonts" /Library/Fonts; do
      [[ -d "$dir" ]] || continue
      match="$(find "$dir" -maxdepth 1 -iname "${NERD_FONT}NerdFont*" -print -quit 2>/dev/null)"
      [[ -n "$match" ]] && return 0
    done
    brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 && return 0
    return 1
  fi

  have fc-list && fc-list 2>/dev/null | grep -qi "${NERD_FONT}.*Nerd" && return 0
  return 1
}

ensure_nerd_font() {
  if $SKIP_FONT; then
    SKIPPED+=("Nerd Font (--skip-font)")
    ok "skipped (--skip-font)"
    return 0
  fi

  if nerd_font_present; then
    ok "${NERD_FONT} Nerd Font"
    return 0
  fi

  MISSING+=("${NERD_FONT} Nerd Font")
  if $CHECK_ONLY; then
    warn "${NERD_FONT} Nerd Font is not installed"
    return 0
  fi

  if [[ "$OS" == "macos" ]]; then
    run brew install --cask font-jetbrains-mono-nerd-font
    INSTALLED+=("${NERD_FONT} Nerd Font")
    warn "Set your terminal font to '${NERD_FONT} Nerd Font' for icons to render."
    return 0
  fi

  local font_dir="$HOME/.local/share/fonts"

  local tag url tmp
  tag="$(github_latest_tag ryanoasis/nerd-fonts)"
  [[ -n "$tag" ]] || { warn "Could not resolve the latest Nerd Fonts release; skipping font."; return 0; }
  url="https://github.com/ryanoasis/nerd-fonts/releases/download/${tag}/${NERD_FONT}.zip"

  info "Installing ${NERD_FONT} Nerd Font ${tag}"
  tmp="$(mktemp -d)"
  fetch "$url" "$tmp/font.zip"
  run mkdir -p "$font_dir"
  run unzip -oq "$tmp/font.zip" -d "$font_dir/${NERD_FONT}NerdFont"
  rm -rf "$tmp"
  have fc-cache && run fc-cache -f "$font_dir" >/dev/null 2>&1
  INSTALLED+=("${NERD_FONT} Nerd Font")
  warn "Set your terminal font to '${NERD_FONT} Nerd Font' for icons to render."
}

# ----------------------------------------------------- install: optional ----

ensure_optional() {
  if $SKIP_OPTIONAL; then
    SKIPPED+=("delta (--skip-optional)")
    return 0
  fi

  # delta: nicer lazygit diffs. Package name differs from the binary name.
  if have delta; then
    ok "delta"
  else
    $CHECK_ONLY && { MISSING+=("delta (optional)"); warn "delta is not installed (optional)"; }
    if ! $CHECK_ONLY; then
      # git-delta everywhere, so there is nothing to branch on. Verified on
      # Fedora 44, where `dnf info delta` finds nothing and git-delta is 0.19.1.
      local delta_pkg="git-delta"
      if pkg_available "$delta_pkg"; then
        pkg_install "$delta_pkg" && INSTALLED+=("delta")
      else
        warn "delta is not packaged here; see https://github.com/dandavison/delta"
      fi
    fi
  fi
}

# -------------------------------------------------------------- config ----

# Minimal git, needed before the repo can be cloned. The full package pass
# later is a no-op for anything installed here.
ensure_git_for_bootstrap() {
  have git && return 0
  info "Installing git so the configuration can be cloned"
  case "$PKG" in
    brew) run brew install git ;;
    apt)  run $SUDO apt-get update -qq && run $SUDO apt-get install -y git ;;
    dnf)  run $SUDO dnf install -y git ;;
  esac
  have git || $DRY_RUN || die "Could not install git."
}

# Put the configuration at CONFIG_DIR, cloning it when we were piped from curl.
bootstrap_repo() {
  if is_config_repo "$CONFIG_DIR"; then
    REPO_DIR="$CONFIG_DIR"
    ok "config already present at $CONFIG_DIR"
    if [[ -d "$CONFIG_DIR/.git" ]] && ! $CHECK_ONLY; then
      info "Updating to the latest $REPO_BRANCH"
      run git -C "$CONFIG_DIR" pull --ff-only origin "$REPO_BRANCH" >/dev/null 2>&1 ||
        warn "Could not fast-forward $CONFIG_DIR; leaving your local state alone."
    fi
    return 0
  fi

  if $CHECK_ONLY; then
    warn "no configuration at $CONFIG_DIR; a full run would clone $REPO_URL"
    REPO_DIR="$CONFIG_DIR"
    return 0
  fi

  ensure_git_for_bootstrap

  # Something else already lives there.
  if [[ -e "$CONFIG_DIR" ]]; then
    local backup
    backup="${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    warn "$CONFIG_DIR exists but is not this configuration."
    confirm "Move it to $backup and clone there?" ||
      die "Refusing to overwrite $CONFIG_DIR. Move it aside, or re-run with --yes."
    run mv "$CONFIG_DIR" "$backup"
    INSTALLED+=("backed up previous config to $backup")
  fi

  info "Cloning $REPO_URL into $CONFIG_DIR"
  run mkdir -p "$(dirname "$CONFIG_DIR")"
  run git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$CONFIG_DIR"
  REPO_DIR="$CONFIG_DIR"
  INSTALLED+=("cloned configuration to $CONFIG_DIR")
}

# Local runs: the repo may live anywhere, so point CONFIG_DIR at it.
ensure_config_location() {
  if [[ "$REPO_DIR" == "$CONFIG_DIR" ]]; then
    ok "config in place at $CONFIG_DIR"
    return 0
  fi
  if [[ -L "$CONFIG_DIR" && "$(readlink "$CONFIG_DIR")" == "$REPO_DIR" ]]; then
    ok "config symlinked: $CONFIG_DIR -> $REPO_DIR"
    return 0
  fi

  $CHECK_ONLY && { warn "config lives at $REPO_DIR, not $CONFIG_DIR"; return 0; }

  if [[ -e "$CONFIG_DIR" ]]; then
    local backup
    backup="${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    warn "$CONFIG_DIR already exists and is not this repository."
    confirm "Move it to $backup and link this repo there?" || {
      warn "Left $CONFIG_DIR alone. Neovim will not use this configuration."
      return 0
    }
    run mv "$CONFIG_DIR" "$backup"
    INSTALLED+=("backed up previous config to $backup")
  fi

  run mkdir -p "$(dirname "$CONFIG_DIR")"
  run ln -s "$REPO_DIR" "$CONFIG_DIR"
  ok "linked $CONFIG_DIR -> $REPO_DIR"
  INSTALLED+=("config symlink")
}

ensure_treesitter_cli() {
  if have tree-sitter; then
    ok "tree-sitter CLI (system)"
    return 0
  fi
  if [[ -x "$REPO_DIR/node_modules/tree-sitter-cli/tree-sitter" ]]; then
    ok "tree-sitter CLI (node_modules)"
    return 0
  fi

  MISSING+=("tree-sitter CLI")
  $CHECK_ONLY && return 0

  have npm || { warn "npm is unavailable; treesitter parsers cannot be compiled."; return 0; }
  info "Installing the tree-sitter CLI via npm"
  run npm --prefix "$REPO_DIR" install --no-audit --no-fund
  INSTALLED+=("tree-sitter CLI")
}

sync_neovim() {
  if $SKIP_SYNC || $CHECK_ONLY; then
    SKIPPED+=("Neovim plugin sync")
    ok "skipped (--no-sync)"
    return 0
  fi

  # `restore` installs the exact commits pinned in lazy-lock.json, which is
  # committed precisely so a fresh machine reproduces a known-good plugin set.
  # `sync` would update everything and rewrite the lockfile instead.
  local lazy_cmd="+Lazy! restore"
  [[ -f "$REPO_DIR/lazy-lock.json" ]] || lazy_cmd="+Lazy! install"

  info "Installing plugins and language servers (a few minutes on first run)"
  if $DRY_RUN; then
    printf '  %s$ nvim --headless "%s" +qa%s\n' "$C_DIM" "$lazy_cmd" "$C_RESET"
    printf '  %s$ nvim --headless   # wait for Mason installs%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  nvim --headless "$lazy_cmd" +qa 2>&1 | grep -viE '^\s*$' || true
  ok "plugins installed"

  # Stop treesitter.lua kicking off its own asynchronous install in this same
  # instance; the call below drives it synchronously instead.
  export NVIM_PARSERS_MANAGED=1

  # `installed` counts only the parsers config.parsers asks for -- never a bare
  # get_installed() total, which also counts dependencies (`xml` pulls in `dtd`)
  # and so once read 26/26 on Fedora while `vimdoc` was missing.
  info "Installing treesitter parsers"
  local parser_out
  parser_out="$(nvim --headless -c 'lua
    local ok, res = pcall(function()
      return { require("config.parsers").ensure({ timeout_ms = 900000 }) }
    end)
    if not ok then
      print("parsers: FAILED " .. tostring(res))
    else
      local installed, wanted, err, missing = res[1], res[2], res[3], res[4] or {}
      local detail = ""
      if #missing > 0 then
        detail = " (missing: " .. table.concat(missing, ", ") .. ")"
      end
      if err then
        detail = detail .. " (" .. err .. ")"
      end
      print(("parsers: %d/%d installed%s"):format(installed, wanted, detail))
    end
  ' +qa 2>&1 | grep -E '^parsers:' || true)"

  if [[ -n "$parser_out" ]]; then
    printf '%s\n' "$parser_out"
  fi
  if [[ "$parser_out" == *FAILED* || "$parser_out" == *"missing:"* ]]; then
    WARNINGS+=("${parser_out#parsers: }")
  fi

  # The LSP stack is lazy-loaded on BufReadPre so the dashboard stays fast,
  # which means a headless run with no file never loads it and Mason installs
  # nothing. Load it explicitly here, otherwise the first real edit silently
  # spends minutes downloading language servers.
  info "Installing language servers and formatters via Mason"
  nvim --headless -c 'lua
    require("lazy").load({ plugins = { "mason-lspconfig.nvim", "mason-tool-installer.nvim" } })

    local ok, reg = pcall(require, "mason-registry")
    if not ok then vim.cmd("qa!") return end

    -- The registry index is downloaded lazily. Until it lands
    -- get_all_packages() is empty, nothing can install, and a naive wait exits
    -- immediately having done nothing.
    local refreshed = false
    reg.refresh(function() refreshed = true end)
    vim.wait(300000, function() return refreshed end, 250)

    -- Install exactly what the config declares, rather than trusting
    -- ensure_installed to have fired before the registry was ready.
    local want = {}
    local ok_ml, ml = pcall(require, "mason-lspconfig")
    if ok_ml and ml.get_mappings then
      local to_package = ml.get_mappings().lspconfig_to_package
      for server in pairs(require("config.servers")) do
        if to_package[server] then want[to_package[server]] = true end
      end
    end
    for _, tool in ipairs(require("config.tools")) do want[tool] = true end

    for name in pairs(want) do
      local found, pkg = pcall(reg.get_package, name)
      if found and not pkg:is_installed() then pcall(function() pkg:install() end) end
    end

    -- Wait until nothing has been installing for a short settle period, so we
    -- do not exit during the gap between two queued downloads. This can take
    -- several minutes, so report progress rather than looking hung.
    local settle_ms, timeout_ms = 20000, 1200000
    local idle_since, last_report = nil, 0

    vim.wait(timeout_ms, function()
      local busy = {}
      for _, p in ipairs(reg.get_all_packages()) do
        if p:is_installing() then busy[#busy + 1] = p.name end
      end

      local now = vim.uv.now()
      if now - last_report >= 15000 then
        last_report = now
        local done = #reg.get_installed_packages()
        if #busy > 0 then
          table.sort(busy)
          print(("  ... %d installed, building: %s"):format(done, table.concat(busy, ", ")))
        else
          print(("  ... %d installed"):format(done))
        end
      end

      if #busy > 0 then
        idle_since = nil
        return false
      end
      idle_since = idle_since or now
      return (now - idle_since) >= settle_ms
    end, 1000)

    local names = {}
    for _, p in ipairs(reg.get_installed_packages()) do names[#names + 1] = p.name end
    table.sort(names)
    print("mason installed " .. #names .. ": " .. table.concat(names, ", "))
  ' +qa 2>&1 | grep -E "^  \.\.\.|^mason installed" || true

  ok "language servers installed"
}

# -------------------------------------------------------------- verify ----

verify() {
  step "Verification"
  local failed=0

  local -a required=(nvim git curl rg node npm python3 uv lazygit gh wakatime-cli)
  local cmd
  for cmd in "${required[@]}"; do
    if have "$cmd"; then
      ok "$cmd"
    else
      err "$cmd is missing"
      failed=1
    fi
  done

  if have fd || have fdfind; then ok "fd"; else err "fd is missing"; failed=1; fi

  local version
  if version="$(current_nvim_version)"; then
    if nvim_version_ok "$version"; then
      ok "neovim $version meets the 0.${NVIM_MIN_MINOR}+ requirement"
    else
      err "neovim $version is older than 0.${NVIM_MIN_MINOR}"
      failed=1
    fi
  fi

  if $DRY_RUN || ! have nvim; then
    :
  elif $SKIP_SYNC; then
    warn "config load not checked (--no-sync); run 'nvim' and ':checkhealth' yourself"
  else
    local out
    out="$(nvim --headless -c 'qa' 2>&1 | grep -viE '^\s*$' || true)"
    if [[ -z "$out" ]]; then
      ok "config loads without errors"
    else
      err "config reported errors on startup:"
      printf '%s\n' "$out" | head -20
      failed=1
    fi
  fi

  return $failed
}

summary() {
  step "Summary"
  printf '  platform: %s (%s, %s)\n' "$DISTRO" "$PKG" "$ARCH"

  if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    printf '\n  %sinstalled:%s\n' "$C_GREEN" "$C_RESET"
    printf '    - %s\n' "${INSTALLED[@]}"
  fi
  if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    printf '\n  %sskipped:%s\n' "$C_DIM" "$C_RESET"
    printf '    - %s\n' "${SKIPPED[@]}"
  fi
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n  %swarnings:%s\n' "$C_YELLOW" "$C_RESET"
    printf '    - %s\n' "${WARNINGS[@]}"
  fi

  if $CHECK_ONLY; then
    if [[ ${#MISSING[@]} -gt 0 ]]; then
      printf '\n  %smissing:%s\n' "$C_RED" "$C_RESET"
      printf '    - %s\n' "${MISSING[@]}"
      printf '\n  Run %s./install.sh%s to install them.\n' "$C_BOLD" "$C_RESET"
    else
      printf '\n  %sEverything is already installed.%s\n' "$C_GREEN" "$C_RESET"
    fi
  fi
}

# ---------------------------------------------------------------- main ----

main() {
  parse_args "$@"
  detect_platform

  # No script on disk, or one sitting outside a checkout: fetch the config.
  if [[ -z "$REPO_DIR" ]] || ! is_config_repo "$REPO_DIR"; then
    BOOTSTRAP=true
  fi

  step "Neovim config installer"
  printf '  source:   %s\n' "$($BOOTSTRAP && echo "$REPO_URL ($REPO_BRANCH)" || echo "$REPO_DIR")"
  printf '  target:   %s\n' "$CONFIG_DIR"
  printf '  platform: %s / %s / %s\n' "$OS" "$DISTRO" "$ARCH"
  $DRY_RUN   && printf '  %smode:     dry run, nothing will be changed%s\n' "$C_DIM" "$C_RESET"
  $CHECK_ONLY && printf '  %smode:     check only, nothing will be changed%s\n' "$C_DIM" "$C_RESET"

  [[ "$OS" == "macos" ]] && ! $CHECK_ONLY && ensure_homebrew

  if $BOOTSTRAP; then
    step "Configuration"
    bootstrap_repo
  fi

  step "System packages"
  ensure_base_packages
  ensure_fd_symlink

  step "Neovim"
  ensure_neovim

  step "Tools"
  ensure_lazygit
  ensure_gh
  ensure_uv
  ensure_hackatime_cli
  ensure_hackatime_config
  ensure_optional

  step "Fonts"
  ensure_nerd_font

  step "Configuration"
  $BOOTSTRAP || ensure_config_location
  ensure_treesitter_cli

  if ! $CHECK_ONLY; then
    step "Neovim sync"
    sync_neovim
  fi

  local rc=0
  $CHECK_ONLY || verify || rc=$?
  summary

  if [[ $rc -ne 0 ]]; then
    printf '\n%sSome checks failed. See the errors above.%s\n' "$C_RED" "$C_RESET"
    exit 1
  fi

  if ! $CHECK_ONLY && ! $DRY_RUN; then
    printf '\n%sDone.%s Start Neovim with: %snvim%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '  Press %s<Space>%s to see the keymap menu, and run %s:checkhealth%s to confirm.\n' \
      "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
  fi
}

# Guarded so the functions above can be sourced by tests.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  main "$@"
fi
