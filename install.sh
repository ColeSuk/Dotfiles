#!/usr/bin/env bash

set -euo pipefail
# -e: stop the script when a command fails
# -u: treat using a variable that was never set as an error,
# -o pipefail: in a pipeline like a | b count a failure in any part, not only the last

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # stores the folder the script lives in.
PKG_DIR="$SCRIPT_DIR/packages"

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

deploy_file() {
  local rel="$1"
  local src="$SCRIPT_DIR/system/$rel"
  local dest="/$rel"
  [[ -f "$src" ]] || die "The system directory does not contain: $src"
  if sudo cmp -s "$src" "$dest"; then
    log "unchanged: $dest"
    return 0
  fi
  sudo install -Dm644 "$src" "$dest"
  log "updated: $dest"
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
}

enable_services() { log "enable_services (todo)"; }
link_dotfiles() { log "link_dotfiles (todo)"; }
extras() { log "extras (todo)"; }

preflight() {
  log "Running preflight checks."

  if [[ $EUID -eq 0 ]]; then
    die "Run this as your normal user, not as root"
  fi
  if ! ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
    die "No internet connection"
  fi
  sudo -v || die "Unable to use sudo"
}

main() {
  preflight
  install_native
  install_aur_helper
  install_aur
  system_config
  enable_services
  link_dotfiles
  extras
}

main "$@"
