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
    source "$cfg"
  else
    log "No local/config.sh found, asking for values"
    read -rp "LAN CIDR (e.g. 192.168.1.0/24): " LAN_CIDR
    read -rp "NAS host/IP: " NAS_HOST
    read -rp "NAS share name: " NAS_SHARE
    # TODO: save these to $cfg so you aren't asked next time
  fi
}

enable_services() {
  log "Enabling services"

  # started now and at boot
  local now_services=(
    systemd-resolved
    iwd
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

link_dotfiles() { log "link_dotfiles (todo)"; }
extras() { log "extras (todo)"; }

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
  enable_services
  link_dotfiles
  extras
}

main "$@"
