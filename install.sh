#!/usr/bin/env bash

set -euo pipefail
# -e: stop the script when a command fails
# -u: treat using a variable that was never set as an error,
# -o pipefail: in a pipeline like a | b count a failure in any part, not only the last

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # stores the folder the script lives in.
PKG_DIR="$SCRIPT_DIR/packages"
CHANGED=()

log() { echo "==> $*"; } # echo out ==> plus everything I was called with

die() {
  echo "Error: $*" >&2 # send the message to the error stream instead of normal output
  exit 1               #  stops the script with an error code
}

install_native() {
  local list="$PKG_DIR/pkglist-native.txt"
  if [[ ! -f "$list" ]]; then
    die "The native package list file does not exist"
  fi
  log "Installing native packages"
  # shellcheck disable=SC2024
  # this warning is a false alarm since the redirect is performed by the shell not by sudo
  sudo pacman -Syu --needed - <"$list"
}

install_aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    log "yay is already installed"
    return 0
  fi
  log "Installing yay"
  local tmp
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si)
  rm -rf "$tmp"
}

install_aur() {
  local list="$PKG_DIR/pkglist-aur.txt"
  if [[ ! -f "$list" ]]; then
    die "The AUR package list file does not exist"
  fi
  local pkgs
  mapfile -t pkgs <"$list"
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log "There are no packages to install from the AUR."
    return 0
  fi
  log "Installing AUR packages"
  yay -S --needed "${pkgs[@]}"
}

install_if_changed() {
  local src="$1" dest="$2" rel="$3"
  if sudo cmp -s "$src" "$dest"; then
    log "unchanged: $dest"
    return 0
  fi
  sudo install -Dm644 "$src" "$dest"
  CHANGED+=("$rel")
  log "updated: $dest"
}

deploy_file() {
  local rel="$1"
  local src="$SCRIPT_DIR/system/$rel"
  local dest="/$rel"
  [[ -f "$src" ]] || die "The system directory does not contain: $src"
  install_if_changed "$src" "$dest" "$rel"
}

deploy_template() {
  local rel="$1"
  local tpl="$SCRIPT_DIR/system/$rel.template"
  : "${LAN_CIDR:?LAN_CIDR is not set (see local/config.sh)}"
  [[ -f "$tpl" ]] || die "The system directory does not contain: $tpl"

  local rendered
  rendered="$(mktemp)"
  sed "s|@LAN_CIDR@|$LAN_CIDR|g" "$tpl" >"$rendered"
  install_if_changed "$rendered" "/$rel" "$rel"
  rm -f "$rendered"
}

system_config() {
  log "Deploying system config"
  local files=(
    etc/modprobe.d/blacklist-nouveau.conf
    etc/modprobe.d/nvidia-pm.conf
    etc/nftables.conf
    etc/mkinitcpio.conf
    etc/iwd/main.conf
  )
  local f
  for f in "${files[@]}"; do
    deploy_file "$f"
  done
  deploy_template etc/systemd/system/docker.service.d/nftables-order.conf
  local want='GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia-drm.modeset=1 nvidia_drm.fbdev=1"'
  if ! grep -qxF "$want" /etc/default/grub; then
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|$want|" /etc/default/grub
    CHANGED+=("etc/default/grub")
    log "updated: GRUB_CMDLINE_LINUX_DEFAULT"
  fi
  local grub=0 reload=0 rebuild=0
  for f in "${CHANGED[@]}"; do
    case "$f" in
    etc/mkinitcpio.conf | etc/modprobe.d/*) rebuild=1 ;;
    etc/default/grub) grub=1 ;;
    etc/systemd/system/*) reload=1 ;;
    esac
  done
  if [[ $rebuild -eq 1 ]]; then
    log "Rebuilding initramfs"
    sudo mkinitcpio -P
  fi
  if [[ $reload -eq 1 ]]; then
    log "Reloading systemd"
    sudo systemctl daemon-reload
  fi
  if [[ $grub -eq 1 ]]; then
    log "Regenerating GRUB config"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

load_local_config() {
  local cfg="$SCRIPT_DIR/local/config.sh"
  if [[ -f "$cfg" ]]; then
    # shellcheck source=/dev/null
    source "$cfg"
  else
    log "No local/config.sh found, asking for values"
    read -rp "LAN CIDR (e.g. 192.168.1.0/24): " LAN_CIDR
    read -rp "NAS host/IP: " NAS_HOST
    read -rp "NAS share name: " NAS_SHARE
    [[ $NAS_SHARE != //* ]] || die "NAS_SHARE should be just the share name (e.g. nas), not //host/share"
    mkdir -p "$SCRIPT_DIR/local"
    {
      printf 'NAS_HOST=%q\n' "$NAS_HOST"
      printf 'NAS_SHARE=%q\n' "$NAS_SHARE"
      printf 'LAN_CIDR=%q\n' "$LAN_CIDR"
    } >"$cfg"
    chmod 600 "$cfg"
    log "Saved Nas host, Nas share and Lan CIDR to config"
  fi
}

enable_services() {
  log "Enabling services"

  # started now and at boot
  local now_services=(
    systemd-resolved
    iwd
    systemd-timesyncd
    nftables
    docker
    tailscaled
  )

  # enabled for next boot only
  local boot_services=(
    nvidia-suspend
    nvidia-hibernate
    nvidia-resume
    ly@tty2
  )

  local s
  for s in "${now_services[@]}"; do
    log "enabling $s"
    sudo systemctl enable --now "$s"
  done
  for s in "${boot_services[@]}"; do
    log "enabling $s"
    sudo systemctl enable "$s"
  done
}

setup_user() {
  log "Configuring user account"

  # docker group
  if [[ " $(id -nG "$USER") " == *" docker "* ]]; then
    log "already in docker group"
  else
    log "Adding current user to docker group"
    sudo usermod -aG docker "$USER"
  fi

  # login shell
  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ $current_shell != "$zsh_path" ]]; then
    log "Setting user shell to zsh"
    sudo chsh -s "$zsh_path" "$USER"
  else
    log "User shell is already zsh"
  fi
}

link_one() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || die "Missing in repo: $src"

  # 1. already correct?
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    log "linked: $dest"
    return 0
  fi

  # 2. something else is there: a real file or folder, or a wrong/broken link
  if [[ -e "$dest" || -L "$dest" ]]; then
    local backup
    backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup"
    log "backed up: $dest -> $backup"
  fi

  # 3. make the parent folder, then the link
  log "Creating parent folder"
  mkdir -p "$(dirname "$dest")"
  log "Create the link"
  ln -s "$src" "$dest"
  log "linked: $dest"
}

link_dotfiles() {
  log "Linking dotfiles"
  local links=(
    ".zshrc|$HOME/.zshrc"
    ".gitconfig|$HOME/.gitconfig"
    "starship.toml|$HOME/.config/starship.toml"
    "hypr|$HOME/.config/hypr"
    "kitty|$HOME/.config/kitty"
    "nvim|$HOME/.config/nvim"
    "rofi|$HOME/.config/rofi"
    "tmux|$HOME/.config/tmux"
    "waybar|$HOME/.config/waybar"
  )
  local entry rel dest
  for entry in "${links[@]}"; do
    rel="${entry%%|*}"
    dest="${entry#*|}"
    link_one "$SCRIPT_DIR/$rel" "$dest"
  done
  local active="$SCRIPT_DIR/hypr/monitors_active.lua"
  if [[ -e "$active" || -L "$active" ]]; then
    log "kept: $active"
  else
    ln -s "$SCRIPT_DIR/hypr/monitors_undocked.lua" "$active"
    log "created: $active"
  fi
}

ensure_line() {
  local line="$1" file="$2"
  if grep -qxF "$line" "$file"; then
    log "present: $line"
  else
    echo "$line" | sudo tee -a "$file" >/dev/null
    log "added: $line"
  fi
}

system_basics() {
  log "Configuring timezone, hostname, locale"

  local tz="America/Chicago"
  local new_hostname="revenant"

  # timezone
  if [[ "$(timedatectl show -p Timezone --value)" != "$tz" ]]; then
    log "Setting timezone to: $tz"
    sudo timedatectl set-timezone "$tz"
  else
    log "timezone already $tz"
  fi

  # hostname
  if [[ "$(hostnamectl hostname)" != "$new_hostname" ]]; then
    log "Setting hostname to $new_hostname"
    sudo hostnamectl set-hostname "$new_hostname"
  else
    log "Hostname is already $new_hostname"
  fi

  # locale
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
    log "Uncommenting and setting locale to en_US.UTF-8 UTF-8"
    sudo sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    sudo locale-gen
  fi
  if ! grep -qxF 'LANG=en_US.UTF-8' /etc/locale.conf 2>/dev/null; then
    log "Setting LANG to en_US.UTF-8"
    sudo localectl set-locale LANG=en_US.UTF-8
  fi

  # resolv.conf
  local stub="/run/systemd/resolve/stub-resolv.conf"
  if [[ "$(readlink /etc/resolv.conf)" != "$stub" ]]; then
    log "Linking /etc/resolv.conf to the systemd-resolved stub"
    sudo ln -sf "$stub" /etc/resolv.conf
  fi
  ensure_line "127.0.0.1 nginx.local" /etc/hosts
  ensure_line "127.0.0.1 httpd.local" /etc/hosts
}

clone_one() {
  local repo="$1" dest="$2" # repo looks like ColeSuk/bash-scripts
  if [[ -d "$dest/.git" ]]; then
    log "present: $dest"
    return 0
  fi
  log "Cloning $repo"
  mkdir -p "$(dirname "$dest")"
  git clone "https://github.com/$repo.git" "$dest"
  git -C "$dest" remote set-url origin "git@github.com:$repo.git"
}

clone_repos() {
  log "Cloning repos"
  local repos=(
    "ColeSuk/bash-scripts|$HOME/dev/scripts"
  )
  local entry repo dest
  for entry in "${repos[@]}"; do
    repo="${entry%%|*}"
    dest="${entry#*|}"
    clone_one "$repo" "$dest"
  done
}

setup_nas() {
  log "Configuring NAS mount"

  local mnt="/mnt/nas"
  local cred="/etc/samba/credentials/nas"
  : "${NAS_HOST:?NAS_HOST is not set (see local/config.sh)}"
  : "${NAS_SHARE:?NAS_SHARE is not set (see local/config.sh)}"
  [[ $NAS_SHARE != //* ]] || die "NAS_SHARE should be just the share name (e.g. nas), not //host/share"
  log "Creating mount point"
  sudo mkdir -p "$mnt"
  local nas_user nas_pass
  if ! sudo test -f "$cred"; then
    sudo install -d -m700 /etc/samba/credentials
    read -rp "NAS username: " nas_user
    read -rsp "NAS password: " nas_pass
    echo
    sudo install -m600 /dev/null "$cred"
    printf 'username=%s\npassword=%s\n' "$nas_user" "$nas_pass" | sudo tee "$cred" >/dev/null
  else
    log "present: $cred"
  fi
  local fstab="/etc/fstab"
  local line
  local reload=0
  line="//$NAS_HOST/$NAS_SHARE $mnt cifs credentials=$cred,uid=$(id -u),gid=$(id -g),iocharset=utf8,_netdev,x-systemd.automount 0 0"
  if ! grep -qxF "$line" "$fstab"; then
    reload=1
  fi
  ensure_line "$line" "$fstab"
  if [[ $reload -eq 1 ]]; then
    log "Reloading systemd"
    sudo systemctl daemon-reload
  fi
}

trust_caddy_ca() {
  local crt="$SCRIPT_DIR/system/ca/caddy-local-root.crt"
  [[ -f "$crt" ]] || die "The system directory does not contain: $crt"
  local trusted
  trusted="$(trust list)"
  if grep -q "Caddy Local Authority" <<<"$trusted"; then
    log "present: Caddy CA is already trusted"
  else
    log "Adding Caddy cert"
    sudo trust anchor "$crt"
  fi
}

extras() {
  log "Installing extras"

  local uv_tools=(ruff mypy)
  local t
  local installed
  installed="$(uv tool list)"

  for t in "${uv_tools[@]}"; do
    if grep -q "^$t " <<<"$installed"; then
      log "present: $t"
    else
      log "Installing $t"
      uv tool install "$t"
    fi
  done
  trust_caddy_ca
}

post_install_checklist() {
  cat <<'EOF'
Manual steps remaining:
  1.) SSH keys (restore or generate), then add them to GitHub
  2.) Switching the dotfiles repo's own remote to SSH once keys exist: git -C ~/.dotfiles remote set-url origin git@github.com:ColeSuk/Dotfiles.git
  3.) Wi-Fi through impala
  4.) sudo tailscale up
  5.) Check the NAS: ls /mnt/nas triggers the automount
  6.) Install and sign in to the claude CLI
  7.) Check one Caddy-proxied site in Brave. If it complains about the certificate, Brave uses its own database; add a certutil step to install.sh.
  8.) Log out and back in, so the docker group and zsh shell take effect, and reboot for the NVIDIA changes
EOF
}

preflight() {
  log "Running preflight checks."

  if [[ $EUID -eq 0 ]]; then
    die "Run this as your normal user, not as root"
  fi
  if ! ping -n -c1 -W3 archlinux.org >/dev/null 2>&1; then
    die "No internet connection"
  fi
  sudo -v || die "Unable to use sudo"
}

main() {
  preflight
  load_local_config
  install_native
  install_aur_helper
  install_aur
  system_config
  system_basics
  enable_services
  setup_user
  link_dotfiles
  clone_repos
  setup_nas
  extras
  post_install_checklist
}

if [[ $# -gt 0 ]]; then
  load_local_config
  "$@"
else
  main
fi
