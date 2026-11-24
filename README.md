# dotfiles

Personal configuration for Arch/Omarchy (Hyprland), Ubuntu/WSL and macOS.

## Contents

| File | Purpose |
| --- | --- |
| `bootstrap.sh` | Installs packages (pacman/apt/brew), sets up zsh, tmux, kitty, and clones the Neovim config |
| `healthcheck.sh` | Verifies the tools the setup expects and prints install hints |
| `hyprland.conf`, `hyprpaper.conf` | Hyprland compositor and wallpaper |
| `waybar/` | Waybar config and styles |
| `dunstrc` | Dunst notifications |
| `kitty.conf` | Kitty terminal |
| `htoprc` | htop |
| `cyberdream.conf` | Cyberdream color theme |

## Usage

```sh
./bootstrap.sh     # set up a machine
./healthcheck.sh   # check required/optional tools
```

`bootstrap.sh` overwrites `~/.zshrc`, `~/.tmux.conf` and kitty config (backups are saved as `*.bootstrap.bak`).
It also sets global git defaults, including `git config --global push.autoSetupRemote true`, and the generated `~/.zshrc` runs `eval "$(/opt/homebrew/bin/brew shellenv)"` on macOS (falling back to `/usr/local/bin/brew` on Intel).

Behaviour can be tuned with environment variables, e.g.:

```sh
INSTALL_NODE=0 SET_DEFAULT_SHELL_ZSH=0 OVERWRITE_TMUX=0 ./bootstrap.sh
```

Other toggles: `OVERWRITE_ZSHRC`, `OVERWRITE_KITTY`, `OVERWRITE_WEZTERM_WINDOWS`.
