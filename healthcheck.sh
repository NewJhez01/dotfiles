#!/usr/bin/env bash
set -euo pipefail

# Neovim + dotfiles tooling healthcheck
# - Verifies commands expected by this setup
# - Prints install hints by package manager
# - Exits non-zero when required tools are missing

have() { command -v "$1" >/dev/null 2>&1; }
pm_detect() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "brew"
    return
  fi
  if have pacman; then
    echo "pacman"
    return
  fi
  if have apt; then
    echo "apt"
    return
  fi
  echo "unknown"
}

missing_required=0
missing_optional=0

ok() { printf "  [ok]   %s\n" "$1"; }
miss_req() { printf "  [miss] %s (required)\n" "$1"; missing_required=$((missing_required + 1)); }
miss_opt() { printf "  [miss] %s (optional)\n" "$1"; missing_optional=$((missing_optional + 1)); }

check_required_cmd() {
  local cmd="$1"
  if have "$cmd"; then
    ok "$cmd -> $(command -v "$cmd")"
  else
    miss_req "$cmd"
  fi
}

check_optional_cmd() {
  local cmd="$1"
  if have "$cmd"; then
    ok "$cmd -> $(command -v "$cmd")"
  else
    miss_opt "$cmd"
  fi
}

print_hints() {
  local pm="$1"
  printf "\nInstall hints (%s):\n" "$pm"
  case "$pm" in
    brew)
      cat <<'EOB'
  brew install neovim git tmux kitty ripgrep fd fzf node php go rust
  # Neovim formatter/linter tools are managed by Mason (and project-local binaries).
EOB
      ;;
    pacman)
      cat <<'EOP'
  sudo pacman -S --needed neovim git tmux kitty ripgrep fd fzf nodejs npm php go rustup
  rustup default stable && rustup component add rustfmt
  # Neovim formatter/linter tools are managed by Mason (and project-local binaries).
EOP
      ;;
    apt)
      cat <<'EOA'
  sudo apt install -y neovim git tmux kitty ripgrep fd-find fzf nodejs npm php php-cli composer golang rustc cargo rustfmt
  # Neovim formatter/linter tools are managed by Mason (and project-local binaries).
EOA
      ;;
    *)
      cat <<'EOU'
  Install required commands manually, then re-run this script.
EOU
      ;;
  esac
}

check_kitty_runtime() {
  local kitty_conf="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"

  printf "\nKitty runtime:\n"
  if [[ -f "$kitty_conf" ]]; then
    ok "kitty config -> $kitty_conf"
    if grep -Eq '^background_opacity[[:space:]]+0\.[0-9]+' "$kitty_conf"; then
      ok "kitty background_opacity configured"
    else
      miss_opt "kitty background_opacity not configured in $kitty_conf"
    fi
  else
    miss_opt "kitty config ($kitty_conf)"
  fi

  local login_shell=""
  login_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"
  if [[ -n "$login_shell" ]]; then
    ok "login shell -> $login_shell"
    if [[ -n "${SHELL:-}" && "${SHELL}" != "$login_shell" ]]; then
      miss_opt "SHELL env mismatch (${SHELL}); GUI apps may start the wrong shell until the session is restarted"
    fi
  fi

  if [[ "$(uname -s)" == "Linux" ]]; then
    case "${XDG_SESSION_TYPE:-unknown}" in
      x11)
        ok "session type -> x11"
        if pgrep -x picom >/dev/null 2>&1; then
          ok "x11 compositor -> picom running"
        else
          miss_opt "x11 compositor (picom not running; kitty may appear opaque)"
        fi
        ;;
      wayland)
        ok "session type -> wayland"
        ok "wayland compositor -> managed by desktop environment/window manager"
        ;;
      *)
        miss_opt "session type (XDG_SESSION_TYPE unset; kitty transparency support unclear)"
        ;;
    esac
  fi
}

main() {
  local pm
  pm="$(pm_detect)"

  printf "Dotfiles healthcheck\n"
  printf "Detected package manager: %s\n\n" "$pm"

  printf "Core tools:\n"
  check_required_cmd nvim
  check_required_cmd git
  check_required_cmd tmux
  check_required_cmd kitty
  check_required_cmd rg
  check_required_cmd fd
  check_required_cmd fzf
  check_required_cmd node
  check_required_cmd npm

  printf "\nLanguage runtimes:\n"
  check_required_cmd php
  check_required_cmd go

  printf "\nNeovim formatters/linters (host fallback, optional):\n"
  check_optional_cmd stylua
  check_optional_cmd luacheck
  check_optional_cmd phpcs
  check_optional_cmd pint
  check_optional_cmd php-cs-fixer
  check_optional_cmd prettierd
  check_optional_cmd prettier
  check_optional_cmd eslint_d
  check_optional_cmd goimports
  check_optional_cmd gofumpt
  check_optional_cmd rustfmt

  printf "\nDAP (PHP):\n"
  if [[ -f "$HOME/.local/share/nvim/vscode-php-debug/out/phpDebug.js" ]]; then
    ok "php debug adapter script -> $HOME/.local/share/nvim/vscode-php-debug/out/phpDebug.js"
  else
    miss_opt "php debug adapter script (~/.local/share/nvim/vscode-php-debug/out/phpDebug.js)"
  fi

  check_kitty_runtime

  printf "\nSummary:\n"
  printf "  required missing: %s\n" "$missing_required"
  printf "  optional missing: %s\n" "$missing_optional"

  if [[ "$missing_required" -gt 0 ]]; then
    print_hints "$pm"
    exit 1
  fi

  printf "\nAll required checks passed.\n"
}

main "$@"
