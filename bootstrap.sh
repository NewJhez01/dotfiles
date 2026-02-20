
#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Owen Bootstrap (Arch/Omarchy + Ubuntu/WSL + macOS)
# - Uses: pacman on Arch, apt on Ubuntu, brew on macOS
# - Intentionally overwrites: ~/.zshrc, ~/.tmux.conf (with backups)
# - Clones/updates Neovim config
# ==========================================

# =========================
# CONFIG (EDIT THIS)
# =========================
NVIM_CONFIG_REPO="git@github.com:NewJhez01/nvim.git"
NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
INSTALL_NODE="${INSTALL_NODE:-1}"          # 1=install node, 0=skip
SET_DEFAULT_SHELL_ZSH="${SET_DEFAULT_SHELL_ZSH:-1}"  # 1=chsh to zsh, 0=skip
OVERWRITE_ZSHRC="${OVERWRITE_ZSHRC:-1}"    # 1=overwrite ~/.zshrc (backup first)
OVERWRITE_TMUX="${OVERWRITE_TMUX:-1}"      # 1=overwrite ~/.tmux.conf (backup first)

# =========================
# HELPERS
# =========================
info() { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
is_wsl()   { is_linux && grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; }

backup_once() {
  local path="$1"
  if [[ -e "$path" && ! -e "${path}.bootstrap.bak" ]]; then
    cp -a "$path" "${path}.bootstrap.bak"
    info "Backed up $path -> ${path}.bootstrap.bak"
  fi
}

require_repo_config() {
  if [[ "$NVIM_CONFIG_REPO" == *"YOURUSER"* ]] || [[ "$NVIM_CONFIG_REPO" == *"YOUR_NVIM_REPO"* ]]; then
    err "You must set NVIM_CONFIG_REPO at the top of this script."
    exit 1
  fi
}

detect_pm() {
  if is_macos; then echo "brew"; return; fi
  if have pacman; then echo "pacman"; return; fi
  if have apt; then echo "apt"; return; fi
  err "No supported package manager found. Need pacman (Arch), apt (Ubuntu), or brew (macOS)."
  exit 1
}

# =========================
# PACKAGE INSTALLS
# =========================
install_homebrew() {
  if have brew; then
    info "Homebrew already installed."
    return
  fi

  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! have brew; then
    err "Homebrew installed but 'brew' not found on PATH."
    err "Open a new shell, or add brew shellenv to your profile."
    exit 1
  fi
}

install_tools_brew() {
  info "Installing tools via brew..."
  brew update
  local pkgs=(
    neovim git tmux starship ripgrep fd fzf bat jq tree htop direnv git-delta lazygit eza zoxide
  )
  if [[ "$INSTALL_NODE" == "1" ]]; then
    pkgs+=(node)
  fi
  pkgs+=(zsh)
  brew install "${pkgs[@]}"

  if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc || true
  fi
}

install_tools_pacman() {
  info "Installing tools via pacman (Arch/Omarchy)..."
  sudo pacman -Syu --needed --noconfirm

  local pkgs=(
    neovim git tmux starship ripgrep fd fzf bat jq tree htop direnv git-delta lazygit eza zoxide
    unzip zip pkgconf base-devel
    zsh
  )
  if [[ "$INSTALL_NODE" == "1" ]]; then
    pkgs+=(nodejs npm)
  fi

  # Some Arch repos may not have every package depending on mirrors/enablement.
  # pacman will error if a package is missing; we install in one go for speed.
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

install_tools_apt() {
  info "Installing tools via apt (Ubuntu/WSL)..."
  sudo apt update
  sudo apt install -y \
    build-essential curl git ca-certificates gnupg lsb-release unzip zip pkg-config \
    tmux ripgrep jq tree htop direnv zsh

  # Ubuntu naming differences
  sudo apt install -y neovim fzf bat fd-find || true

  # Nice-to-haves may require extra repos on Ubuntu; skip silently if missing.
  sudo apt install -y zoxide || true
}

install_nvim_dev_tools() {
  local pm="$1"
  info "Installing Neovim formatter/linter toolchain..."

  case "$pm" in
    brew)
      brew install \
        stylua \
        luacheck \
        php-code-sniffer \
        php-cs-fixer \
        go \
        rust || true
      ;;
    pacman)
      local pac_pkgs=(
        stylua
        luacheck
        lua-check
        php
        php-codesniffer
        php-cs-fixer
        go
        rustup
      )
      for pkg in "${pac_pkgs[@]}"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
          sudo pacman -S --needed --noconfirm "$pkg"
        else
          warn "Skipping unavailable pacman package: $pkg"
        fi
      done
      if have rustup; then
        rustup default stable >/dev/null 2>&1 || true
        rustup component add rustfmt || true
      fi
      ;;
    apt)
      sudo apt install -y \
        php php-cli composer \
        golang rustc cargo \
        stylua luacheck php-codesniffer php-cs-fixer rustfmt || true
      sudo apt install -y lua-check || true
      ;;
  esac

  if have npm; then
    if [[ "$(npm config get prefix 2>/dev/null || true)" == "/usr" ]]; then
      sudo npm install -g @fsouza/prettierd prettier eslint_d || warn "npm global install failed (sudo)."
    else
      npm install -g @fsouza/prettierd prettier eslint_d || sudo npm install -g @fsouza/prettierd prettier eslint_d || warn "npm global install failed."
    fi
  else
    warn "npm not found; skipping @fsouza/prettierd/prettier/eslint_d install."
  fi

  if have go; then
    go install golang.org/x/tools/cmd/goimports@latest || warn "go install failed: goimports"
    go install mvdan.cc/gofumpt@latest || warn "go install failed: gofumpt"
  else
    warn "go not found; skipping goimports/gofumpt install."
  fi

  if have composer; then
    composer global require --dev laravel/pint || true
  else
    warn "composer not found; skipping laravel/pint install."
  fi
}

# =========================
# ZSH CONFIG (INTENTIONAL OVERWRITE)
# =========================
write_zshrc() {
  local zshrc="$HOME/.zshrc"

  if [[ "$OVERWRITE_ZSHRC" == "1" ]]; then
    backup_once "$zshrc"
    info "Writing ~/.zshrc (overwriting)..."
    cat >"$zshrc" <<'EOF'
# ==========================================
# Owen ~/.zshrc (bootstrap-managed)
# ==========================================

# Faster key response for vi-mode
KEYTIMEOUT=1

# Basic sanity
export EDITOR="nvim"
export VISUAL="nvim"

# Ensure user-installed tooling is on PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.config/composer/vendor/bin:$PATH"
export PATH="$HOME/.composer/vendor/bin:$PATH"

# Completion
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"

zmodload zsh/complist

# Vim keybindings
bindkey -v
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
bindkey -M vicmd '^?' backward-delete-char
bindkey -M vicmd '^H' backward-delete-char

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# direnv
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# fzf keybindings/completions (works for brew + pacman + apt if fzf installed)
if command -v fzf >/dev/null 2>&1; then
  # Common locations; ignore if missing
  [[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
  [[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
  [[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
fi

# Custom aliases (created by bootstrap)
if [[ -f "$HOME/.config/zsh/aliases.zsh" ]]; then
  source "$HOME/.config/zsh/aliases.zsh"
fi
EOF
  else
    info "Skipping ~/.zshrc overwrite (OVERWRITE_ZSHRC=0)."
  fi
}

set_default_shell_zsh() {
  if [[ "$SET_DEFAULT_SHELL_ZSH" != "1" ]]; then
    info "Skipping default shell change (SET_DEFAULT_SHELL_ZSH=0)."
    return
  fi

  if ! have zsh; then
    warn "zsh not found; skipping chsh."
    return
  fi

  # On WSL/corporate environments, chsh may be blocked; treat as best-effort.
  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    info "Setting zsh as default shell (may prompt for password)..."
    chsh -s "$(command -v zsh)" || warn "Could not change default shell (may be restricted)."
  else
    info "zsh already set as default shell."
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
  alias ls='eza'
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
# GIT DEFAULTS
# =========================
configure_git_defaults() {
  if ! have git; then
    warn "git not found; skipping git defaults."
    return
  fi

  git config --global core.editor "nvim" || true
  git config --global pull.rebase false || true
  git config --global init.defaultBranch main || true
  info "Configured basic global git defaults."
}

ensure_tmux_conf() {
  local file="$HOME/.tmux.conf"

  if [[ "$OVERWRITE_TMUX" != "1" ]]; then
    info "Skipping tmux overwrite (OVERWRITE_TMUX=0)."
    return
  fi

  backup_once "$file"
  info "Writing tmux config (overwriting ~/.tmux.conf)..."

  cat >"$file" <<'EOF'
# -------------------------
# Tmux config
# -------------------------

# Prefix
unbind C-b
set -g prefix C-Space
bind C-Space send-prefix
bind C-@ send-prefix

# Indexing
set -g base-index 1
setw -g pane-base-index 1

# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Copy mode = scrolling (Vim)
setw -g mode-keys vi
set -g history-limit 100000
set -g mouse on

# Enter copy mode with prefix + [
bind [ copy-mode -e

# -------------------------
# Copy to system clipboard (macOS / Linux / WSL)
# -------------------------
# Choose the best available clipboard command:
# - WSL: clip.exe (Windows clipboard)
# - macOS: pbcopy
# - Wayland: wl-copy
# - X11: xclip / xsel
set -g @clipboard_copy_cmd 'cat >/dev/null'

# Prefer Windows clipboard when inside WSL (if available)
if-shell 'command -v clip.exe >/dev/null 2>&1 && grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null' \
  'set -g @clipboard_copy_cmd "clip.exe"'

# macOS
if-shell 'command -v pbcopy >/dev/null 2>&1' \
  'set -g @clipboard_copy_cmd "pbcopy"'

# Wayland
if-shell 'command -v wl-copy >/dev/null 2>&1' \
  'set -g @clipboard_copy_cmd "wl-copy"'

# X11
if-shell 'command -v xclip >/dev/null 2>&1' \
  'set -g @clipboard_copy_cmd "xclip -in -selection clipboard"'
if-shell 'command -v xsel >/dev/null 2>&1' \
  'set -g @clipboard_copy_cmd "xsel -ib"'

# Copy selection (Enter or y) -> system clipboard, then exit copy-mode
bind -T copy-mode-vi Enter send -X copy-pipe-and-cancel "#{@clipboard_copy_cmd}"
bind -T copy-mode-vi y     send -X copy-pipe-and-cancel "#{@clipboard_copy_cmd}"

# Quick reload
bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"
EOF

  info "Wrote $file"
}

# =========================
# MAIN
# =========================
main() {
  local pm
  pm="$(detect_pm)"
  info "Detected package manager: $pm"

  case "$pm" in
    brew)
      install_homebrew
      install_tools_brew
      ;;
    pacman)
      install_tools_pacman
      ;;
    apt)
      install_tools_apt
      ;;
  esac

  install_nvim_dev_tools "$pm"

  ensure_aliases_file
  write_zshrc
  set_default_shell_zsh
  ensure_tmux_conf
  clone_nvim_config
  configure_git_defaults

  if is_wsl; then
    warn "WSL detected: keep repos in /home (NOT /mnt/c) for best performance."
    warn "Consider Windows Defender exclusions for \\\\wsl$\\ to avoid slow IO."
  fi

  info "Done."
  info "Open a NEW terminal window (so zsh loads), then run: nvim"
  info "Test zoxide: z <foldername>"
  info "Test tmux copy-mode scroll: Ctrl-Space [ then k/j, /search, q"
  info "Test tmux copy -> clipboard: Ctrl-Space [ select text, then Enter (or y), then paste in OS app"
}

main "$@"
