#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG (EDIT THIS)
# =========================
NVIM_CONFIG_REPO="git@github.com:YOURUSER/YOUR_NVIM_REPO.git"
NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# =========================
# HELPERS
# =========================
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
is_wsl() { is_linux && grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; }

require_repo_config() {
  if [[ "$NVIM_CONFIG_REPO" == *"YOURUSER"* ]] || [[ "$NVIM_CONFIG_REPO" == *"YOUR_NVIM_REPO"* ]]; then
    err "You must set NVIM_CONFIG_REPO at the top of this script."
    err "Edit bootstrap.sh and set NVIM_CONFIG_REPO to your repo URL, then re-run."
    exit 1
  fi
}

# =========================
# OS PREP
# =========================
install_prereqs_ubuntu() {
  info "Installing Ubuntu prerequisites (apt)..."
  sudo apt update
  sudo apt install -y \
    build-essential \
    curl \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    zip \
    pkg-config
}

install_xcode_cli_tools_macos() {
  if xcode-select -p >/dev/null 2>&1; then
    info "Xcode Command Line Tools already installed."
  else
    info "Installing Xcode Command Line Tools..."
    xcode-select --install || true
    warn "If a GUI prompt appeared, complete it, then re-run this script if needed."
  fi
}

# =========================
# HOMEBREW
# =========================
install_homebrew() {
  if have brew; then
    info "Homebrew already installed."
    return
  fi

  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if is_macos; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" || true
  fi

  if ! have brew; then
    err "Homebrew install completed but 'brew' not found on PATH."
    err "Open a new shell, or add brew shellenv to your profile, then re-run."
    exit 1
  fi
}

ensure_brew_shellenv_persisted() {
  info "Persisting brew shellenv in your shell profile (idempotent)..."
  local line=""
  if is_macos; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      line='eval "$(/opt/homebrew/bin/brew shellenv)"'
    else
      line='eval "$(/usr/local/bin/brew shellenv)"'
    fi
  else
    line='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
  fi

  for f in "$HOME/.zprofile" "$HOME/.profile"; do
    touch "$f"
    if ! grep -Fq "$line" "$f"; then
      printf "\n# Homebrew\n%s\n" "$line" >>"$f"
      info "Added brew shellenv to $f"
    fi
  done
}

# =========================
# PACKAGES
# =========================
brew_install_tools() {
  info "Installing tools via Homebrew..."
  brew update

  brew install \
    neovim \
    git \
    tmux \
    starship \
    ripgrep \
    fd \
    fzf \
    bat \
    jq \
    tree \
    htop \
    direnv \
    git-delta \
    lazygit \
    eza \
    node

  if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc || true
  fi
}

# =========================
# ZSH + ZINIT + STARSHIP
# =========================
setup_zsh_default_shell() {
  if ! have zsh; then
    info "Installing zsh..."
    if is_macos; then
      brew install zsh
    else
      sudo apt install -y zsh || brew install zsh
    fi
  fi

  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    info "Setting zsh as default shell (may prompt for password)..."
    chsh -s "$(command -v zsh)" || warn "Could not change default shell (this can be restricted)."
  fi
}

install_zinit() {
  local zinit_dir="${ZINIT_HOME:-$HOME/.local/share/zinit/zinit.git}"
  if [[ -d "$zinit_dir/.git" ]]; then
    info "zinit already installed."
    return
  fi
  info "Installing zinit..."
  mkdir -p "$(dirname "$zinit_dir")"
  git clone https://github.com/zdharma-continuum/zinit.git "$zinit_dir"
}

ensure_zshrc_config() {
  info "Configuring ~/.zshrc (idempotent)..."
  local zshrc="$HOME/.zshrc"
  touch "$zshrc"

  # Brew shellenv in zshrc as well (non-login shells)
  if is_macos; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      grep -Fq 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$zshrc" ||
        printf '\n# Homebrew\neval "$(/opt/homebrew/bin/brew shellenv)"\n' >>"$zshrc"
    else
      grep -Fq 'eval "$(/usr/local/bin/brew shellenv)"' "$zshrc" ||
        printf '\n# Homebrew\neval "$(/usr/local/bin/brew shellenv)"\n' >>"$zshrc"
    fi
  else
    grep -Fq 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' "$zshrc" ||
      printf '\n# Homebrew\neval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n' >>"$zshrc"
  fi

  # zinit + starship + direnv
  if ! grep -Fq "zinit.git/zinit.zsh" "$zshrc"; then
    cat >>"$zshrc" <<'EOF'

# -------------------------
# zinit (plugin manager)
# -------------------------
ZINIT_HOME="${ZINIT_HOME:-$HOME/.local/share/zinit/zinit.git}"
if [[ -f "$ZINIT_HOME/zinit.zsh" ]]; then
  source "$ZINIT_HOME/zinit.zsh"
  zinit light zsh-users/zsh-autosuggestions
  zinit light zsh-users/zsh-syntax-highlighting
  zinit light Aloxaf/fzf-tab
fi

# -------------------------
# Starship prompt
# -------------------------
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# -------------------------
# direnv (per-project env)
# -------------------------
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
EOF
    info "Added zinit/starship/direnv config to ~/.zshrc"
  else
    info "~/.zshrc already contains zinit config; leaving as-is."
  fi

  # Ensure aliases file is sourced
  if ! grep -Fq ".config/zsh/aliases.zsh" "$zshrc"; then
    cat >>"$zshrc" <<'EOF'

# -------------------------
# Custom aliases
# -------------------------
if [[ -f "$HOME/.config/zsh/aliases.zsh" ]]; then
  source "$HOME/.config/zsh/aliases.zsh"
fi
EOF
    info "Added aliases sourcing to ~/.zshrc"
  fi
}

# =========================
# ALIASES
# =========================
ensure_aliases_file() {
  info "Creating/updating aliases file..."
  local dir="$HOME/.config/zsh"
  local file="$dir/aliases.zsh"
  mkdir -p "$dir"
  touch "$file"

  # Write a marked block so re-runs don't duplicate
  local begin="# >>> bootstrap: git aliases >>>"
  local end="# <<< bootstrap: git aliases <<<"

  if grep -Fq "$begin" "$file"; then
    info "Aliases block already present in $file; leaving as-is."
    return
  fi

  cat >>"$file" <<'EOF'

# >>> bootstrap: git aliases >>>
alias gm='git merge'
alias gs='git stash'
alias gsc='git stash clear'
alias gsm='git stash -m'
alias gsa='git stash apply'
alias gsl='git stash list'

alias sgc='skip=1 git commit -m'
alias gc='git commit -m'
alias gcam='git commit --amend -m'
alias sgcam='skip=1 git commit --amend -m'
alias gcan='git commit --amend --no-edit'
alias sgcan='skip=1 git commit --amend --no-edit'

alias ga='git add'
alias gaa='git add .'
alias gst='git status'
alias gl='git pull'
alias gp='git push'
alias gpf='git push --force'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gcoc='check=1 git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'
alias gd='git diff'
alias gf='git fetch'
alias grs='git reset'
alias grh='git reset --hard'
alias grst='git restore'
alias grsta='git restore .'
alias grb='git rebase -i'
alias glat='git fetch && git pull'

# eza aliases (only if installed)
if command -v eza >/dev/null 2>&1; then
  # Safe: keep ls as-is if you prefer; change to `alias ls='eza'` if you want full replacement.
  alias l='eza -lah --git'
  alias ll='eza -lah --git'
  alias la='eza -a'
  alias lt='eza --tree --level=2'
fi
# <<< bootstrap: git aliases <<<
EOF

  info "Wrote aliases block to $file"
}

# =========================
# NEOVIM CONFIG
# =========================
clone_nvim_config() {
  require_repo_config

  info "Setting up Neovim config..."
  mkdir -p "$(dirname "$NVIM_CONFIG_DIR")"

  if [[ -d "$NVIM_CONFIG_DIR/.git" ]]; then
    info "Neovim config already exists at $NVIM_CONFIG_DIR"
    info "Pulling latest..."
    git -C "$NVIM_CONFIG_DIR" pull --ff-only || warn "Could not fast-forward pull; resolve manually."
    return
  fi

  if [[ -e "$NVIM_CONFIG_DIR" ]]; then
    warn "$NVIM_CONFIG_DIR exists but is not a git repo."
    warn "Move it out of the way if you want this script to clone your config."
    return
  fi

  git clone "$NVIM_CONFIG_REPO" "$NVIM_CONFIG_DIR"
  info "Cloned Neovim config to $NVIM_CONFIG_DIR"
}

# =========================
# MAIN
# =========================
main() {
  if is_macos; then
    info "Detected macOS."
    install_xcode_cli_tools_macos
  elif is_linux; then
    info "Detected Linux."
    if have apt; then
      install_prereqs_ubuntu
    else
      warn "No apt detected. This script assumes Ubuntu/WSL for Linux."
    fi
  else
    err "Unsupported OS: $(uname -s)"
    exit 1
  fi

  install_homebrew
  ensure_brew_shellenv_persisted
  brew_install_tools

  setup_zsh_default_shell
  install_zinit
  ensure_zshrc_config
  ensure_aliases_file

  clone_nvim_config

  # Set git editor once per machine (idempotent)
  if have git && have nvim; then
    git config --global core.editor "nvim" || true
  fi

  if is_wsl; then
    warn "WSL detected: keep your repos inside /home (NOT /mnt/c) for best performance."
    warn "Consider Windows Defender exclusions for \\\\wsl$\\ to avoid slow file IO."
  fi

  info "Done."
  info "Open a NEW terminal window (so zsh + brew env load), then run: nvim"
  info "Test aliases: gst, gaa, glog, ll, lt"
}

main "$@"
