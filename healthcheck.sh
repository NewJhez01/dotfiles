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

check_one_required() {
  local label="$1"
  shift
  local found=""
  local cmd
  for cmd in "$@"; do
    if have "$cmd"; then
      found="$cmd"
      break
    fi
  done

  if [[ -n "$found" ]]; then
    ok "$label -> $found ($(command -v "$found"))"
  else
    miss_req "$label (any of: $*)"
  fi
}

print_hints() {
  local pm="$1"
  printf "\nInstall hints (%s):\n" "$pm"
  case "$pm" in
    brew)
      cat <<'EOF'
  brew install stylua luacheck php-code-sniffer php-cs-fixer go rust
  npm install -g @fsouza/prettierd prettier eslint_d
  go install golang.org/x/tools/cmd/goimports@latest
  go install mvdan.cc/gofumpt@latest
  composer global require --dev laravel/pint
EOF
      ;;
    pacman)
      cat <<'EOF'
  sudo pacman -S --needed stylua luacheck php php-codesniffer php-cs-fixer go rustup
  rustup default stable && rustup component add rustfmt
  npm install -g @fsouza/prettierd prettier eslint_d
  go install golang.org/x/tools/cmd/goimports@latest
  go install mvdan.cc/gofumpt@latest
  composer global require --dev laravel/pint
EOF
      ;;
    apt)
      cat <<'EOF'
  sudo apt install -y php php-cli composer golang rustc cargo stylua luacheck php-codesniffer php-cs-fixer rustfmt
  npm install -g @fsouza/prettierd prettier eslint_d
  go install golang.org/x/tools/cmd/goimports@latest
  go install mvdan.cc/gofumpt@latest
  composer global require --dev laravel/pint
EOF
      ;;
    *)
      cat <<'EOF'
  Install required commands manually, then re-run this script.
EOF
      ;;
  esac
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
  check_required_cmd rg
  check_required_cmd fd
  check_required_cmd fzf
  check_required_cmd node
  check_required_cmd npm

  printf "\nLanguage runtimes:\n"
  check_required_cmd php
  check_required_cmd go

  printf "\nNeovim formatters/linters:\n"
  check_required_cmd stylua
  check_required_cmd luacheck
  check_required_cmd phpcs
  check_one_required "php formatter" pint php-cs-fixer
  check_one_required "js formatter" prettierd prettier
  check_required_cmd eslint_d
  check_required_cmd goimports
  check_required_cmd gofumpt
  check_optional_cmd rustfmt

  printf "\nDAP (PHP):\n"
  if [[ -f "$HOME/.local/share/nvim/vscode-php-debug/out/phpDebug.js" ]]; then
    ok "php debug adapter script -> $HOME/.local/share/nvim/vscode-php-debug/out/phpDebug.js"
  else
    miss_opt "php debug adapter script (~/.local/share/nvim/vscode-php-debug/out/phpDebug.js)"
  fi

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
