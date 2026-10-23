# Dotfiles

Personal dotfiles and a rebuild script for my Arch Linux laptop
(Hyprland, zsh, Intel + NVIDIA, GRUB/UEFI). `install.sh` takes a fresh
`archinstall` to a working setup: packages, system config, services,
dotfile links, and a few extras.

This is built for one machine. It is not a general-purpose installer, and
values like the hostname and timezone are set in the script.

## Prerequisites

- A fresh Arch install with a normal user in the `wheel` group (sudo works)
- A working network connection
- `git` (`sudo pacman -S --needed git`)

## Install

```bash
git clone https://github.com/ColeSuk/Dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Run it as your normal user, not as root. It asks for your sudo password up
front and prompts for a few values on the first run (see below).

## Local config

Values specific to my network are not stored in this repo. They live in
`local/config.sh`, which is gitignored. If that file is missing, the script
asks for the values once and saves them. `local/config.example.sh` shows the
expected variables:

- `LAN_CIDR`: the local network range, used to render firewall config
- `NAS_HOST`: the NAS host or IP
- `NAS_SHARE`: the share name only (for example `nas`, not `//host/nas`)

The NAS username and password are asked for once and written to a
root-only credentials file under `/etc/samba/credentials/`. They are never
stored in the repo.

## What it does

In order: preflight checks, local config, native and AUR packages, system
config under `/etc`, timezone/locale/hostname, services, user account
(docker group, zsh), dotfile symlinks, repo clones, NAS mount, extras
(uv tools, Caddy root certificate), and a checklist of manual steps.

The script is designed to be safe to re-run: each step checks whether it is
already done. Existing files that a symlink would replace are renamed to
`<name>.bak.<timestamp>` first.

## Running one step

Any function can be run on its own:

```bash
./install.sh setup_nas
./install.sh link_dotfiles
```

## Layout

- `packages/`: native and AUR package lists
- `system/`: files deployed to `/etc` (paths mirror the real ones);
  `*.template` files are rendered from `local/config.sh`
- `system/ca/`: public root certificate for my internal Caddy CA
- `hypr/`, `kitty/`, `nvim/`, `rofi/`, `tmux/`, `waybar/`, `.zshrc`, ...:
  the dotfiles themselves, symlinked into `$HOME`
- `local/`: machine-specific values (gitignored)

## After the script

It prints a checklist of manual steps at the end (SSH keys, Wi-Fi, Tailscale,
NAS check, and so on).
