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
OVERWRITE_KITTY="${OVERWRITE_KITTY:-1}"    # 1=overwrite kitty.conf (backup first)
OVERWRITE_WEZTERM_WINDOWS="${OVERWRITE_WEZTERM_WINDOWS:-1}"  # 1=overwrite Windows .wezterm.lua from WSL

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
windows_home_dir() {
  local win_profile

  have cmd.exe || return 1
  have wslpath || return 1

  win_profile="$(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')"
  [[ -n "$win_profile" ]] || return 1

  wslpath "$win_profile"
}

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
    neovim git tmux kitty starship ripgrep fd fzf bat jq tree htop direnv git-delta lazygit eza zoxide
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

install_jetbrains_mono_nerd_font() {
  local pm="$1"

  info "Installing JetBrainsMono Nerd Font..."

  case "$pm" in
    brew)
      brew tap homebrew/cask-fonts
      brew install --cask font-jetbrains-mono-nerd-font
      ;;
    pacman)
      if pacman -Si ttf-jetbrains-mono-nerd >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd
      else
        warn "Skipping JetBrainsMono Nerd Font; pacman package not available."
      fi
      ;;
    apt)
      local font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMonoNerdFont"
      local tmp_zip="/tmp/JetBrainsMono.zip"

      mkdir -p "$font_dir"
      curl -fL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$tmp_zip"
      unzip -o "$tmp_zip" -d "$font_dir" >/dev/null
      rm -f "$tmp_zip"

      if have fc-cache; then
        fc-cache -f "$font_dir" >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

install_tools_pacman() {
  info "Installing tools via pacman (Arch/Omarchy)..."
  sudo pacman -Syu --needed --noconfirm

  local pkgs=(
    neovim git tmux kitty starship ripgrep fd fzf bat jq tree htop direnv git-delta lazygit eza zoxide
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
    tmux kitty ripgrep jq tree htop direnv zsh

  # Ubuntu naming differences
  sudo apt install -y neovim fzf bat fd-find || true

  # Nice-to-haves may require extra repos on Ubuntu; skip silently if missing.
  sudo apt install -y zoxide || true
}

install_nvim_dev_tools() {
  local pm="$1"
  info "Installing language runtimes for Neovim tooling..."

  case "$pm" in
    brew)
      brew install \
        php \
        go \
        rust || true
      ;;
    pacman)
      local pac_pkgs=(
        php
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
        golang rustc cargo rustfmt || true
      ;;
  esac
}

ensure_fzf_tab_plugin() {
  local plugin_dir="$HOME/.config/zsh/plugins/fzf-tab"
  info "Installing/updating fzf-tab plugin..."

  mkdir -p "$(dirname "$plugin_dir")"
  if [[ -d "$plugin_dir/.git" ]]; then
    git -C "$plugin_dir" pull --ff-only || warn "Could not update fzf-tab; keeping existing version."
    return
  fi

  if [[ -e "$plugin_dir" ]]; then
    warn "$plugin_dir exists but is not a git repo; skipping fzf-tab clone."
    return
  fi

  git clone --depth 1 https://github.com/Aloxaf/fzf-tab "$plugin_dir" \
    || warn "Could not clone fzf-tab; Tab will use default zsh completion."
}

ensure_zsh_autosuggestions_plugin() {
  local plugin_dir="$HOME/.config/zsh/plugins/zsh-autosuggestions"
  info "Installing/updating zsh-autosuggestions plugin..."

  mkdir -p "$(dirname "$plugin_dir")"
  if [[ -d "$plugin_dir/.git" ]]; then
    git -C "$plugin_dir" pull --ff-only || warn "Could not update zsh-autosuggestions; keeping existing version."
    return
  fi

  if [[ -e "$plugin_dir" ]]; then
    warn "$plugin_dir exists but is not a git repo; skipping zsh-autosuggestions clone."
    return
  fi

  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$plugin_dir" \
    || warn "Could not clone zsh-autosuggestions."
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

# zsh-autosuggestions (ghost text inline suggestions)
if [[ -f "$HOME/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOME/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  bindkey -M viins '^[[C' autosuggest-accept
fi

# fzf-tab (fzf UI for normal completion, e.g. cd <Tab>)
if [[ -f "$HOME/.config/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh" ]]; then
  source "$HOME/.config/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh"
  zstyle ':fzf-tab:*' use-fzf-default-opts yes
fi

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
  local tmux_shell="/bin/sh"

  if [[ "$OVERWRITE_TMUX" != "1" ]]; then
    info "Skipping tmux overwrite (OVERWRITE_TMUX=0)."
    return
  fi

  if have zsh; then
    tmux_shell="$(command -v zsh)"
  elif [[ -n "${SHELL:-}" ]] && [[ -x "${SHELL}" ]]; then
    tmux_shell="${SHELL}"
  fi

  backup_once "$file"
  info "Writing tmux config (overwriting ~/.tmux.conf)..."

  cat >"$file" <<EOF
# -------------------------
# Tmux config
# -------------------------

# Use the real shell path instead of inheriting a stale SHELL env from the
# terminal session that started the tmux server.
set -g default-shell ${tmux_shell}
set -g default-command ${tmux_shell}

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

ensure_kitty_conf() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
  local file="$dir/kitty.conf"
  local opacity="0.88"
  local kitty_shell=""

  if [[ "$OVERWRITE_KITTY" != "1" ]]; then
    info "Skipping kitty config overwrite (OVERWRITE_KITTY=0)."
    return
  fi

  if is_wsl; then
    # WSLg is not a full compositor environment, so keep this opaque.
    opacity="1.0"
  fi

  if have zsh; then
    kitty_shell="$(command -v zsh)"
  fi

  mkdir -p "$dir"
  backup_once "$file"
  info "Writing kitty config (overwriting $file)..."

  cat >"$file" <<EOF
# ==========================================
# Owen kitty.conf (bootstrap-managed)
# ==========================================

font_size 13.0

cursor_shape beam
cursor_blink_interval 0

scrollback_lines 10000

tab_bar_edge top
tab_bar_style powerline
tab_powerline_style slanted

# Match the transparent compositor-style look where the platform supports it.
background_opacity ${opacity}
dynamic_background_opacity yes

background #111417
foreground #e6e6e6
selection_background #3a4a5a
selection_foreground #ffffff

font_family JetBrainsMono Nerd Font

window_padding_width 10

shell_integration enabled
${kitty_shell:+shell ${kitty_shell}}

macos_option_as_alt yes
macos_thicken_font 0.15
EOF

  info "Wrote $file"
}

explain_kitty_linux_transparency() {
  if ! is_linux || is_wsl; then
    return
  fi

  info "Kitty note: restart kitty itself after bootstrap; 'exec zsh' only reloads the shell."

  case "${XDG_SESSION_TYPE:-unknown}" in
    x11)
      if pgrep -x picom >/dev/null 2>&1; then
        info "Kitty transparency check: X11 compositor detected (picom)."
      else
        warn "Kitty transparency check: X11 session with no running picom detected; opacity may stay opaque without a compositor."
      fi
      ;;
    wayland)
      info "Kitty transparency check: Wayland session detected; opacity depends on compositor/Desktop Environment support."
      ;;
    *)
      warn "Kitty transparency check: unknown session type; if opacity does not apply, verify your compositor/Desktop Environment supports transparent terminal windows."
      ;;
  esac
}

ensure_wezterm_windows_conf() {
  local win_home file

  if ! is_wsl; then
    return
  fi

  if [[ "$OVERWRITE_WEZTERM_WINDOWS" != "1" ]]; then
    info "Skipping Windows wezterm config overwrite (OVERWRITE_WEZTERM_WINDOWS=0)."
    return
  fi

  if ! win_home="$(windows_home_dir)"; then
    warn "Could not resolve Windows home directory from WSL; skipping wezterm config."
    return
  fi

  file="$win_home/.wezterm.lua"
  mkdir -p "$win_home"
  backup_once "$file"
  info "Writing Windows wezterm config (overwriting $file)..."

  cat >"$file" <<'EOF'
local wezterm = require 'wezterm'

local config = {}

config.default_prog = { 'wsl.exe', '--cd', '~' }
config.font = wezterm.font('JetBrainsMono Nerd Font')
config.font_size = 13.0

config.window_background_opacity = 0.88
config.win32_system_backdrop = 'Acrylic'
config.window_padding = {
  left = 10,
  right = 10,
  top = 10,
  bottom = 10,
}

config.colors = {
  background = '#111417',
  foreground = '#e6e6e6',
  selection_bg = '#3a4a5a',
  selection_fg = '#ffffff',
  cursor_bg = '#e6e6e6',
  cursor_fg = '#111417',
}

config.cursor_blink_rate = 0
config.default_cursor_style = 'BlinkingBar'
config.scrollback_lines = 10000
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

return config
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

  install_jetbrains_mono_nerd_font "$pm"
  install_nvim_dev_tools "$pm"
  ensure_fzf_tab_plugin
  ensure_zsh_autosuggestions_plugin

  ensure_aliases_file
  write_zshrc
  set_default_shell_zsh
  ensure_tmux_conf
  ensure_kitty_conf
  explain_kitty_linux_transparency
  ensure_wezterm_windows_conf
  clone_nvim_config
  configure_git_defaults

  if is_wsl; then
    warn "WSL detected: keep repos in /home (NOT /mnt/c) for best performance."
    warn "Consider Windows Defender exclusions for \\\\wsl$\\ to avoid slow IO."
  fi

  info "Done."
  info "Open a NEW terminal window (so zsh loads), then run: nvim"
  info "Test kitty: launch a NEW kitty window and confirm opacity/background look matches your platform"
  info "Test wezterm on Windows: launch 'wezterm' and confirm Acrylic/transparency and WSL startup"
  info "Test fzf-tab: type 'cd ' then press Tab"
  info "Test zoxide: z <foldername>"
  info "Test tmux copy-mode scroll: Ctrl-Space [ then k/j, /search, q"
  info "Test tmux copy -> clipboard: Ctrl-Space [ select text, then Enter (or y), then paste in OS app"
}

main "$@"
