#!/usr/bin/env bash

set -e
source custom_package_list.sh

pr() { echo -e "\033[0;32m[+] ${1}\033[0m"; }

setupenv() {
  # Pacman Config
  sed -i "s/#NoProgressBar/NoProgressBar/" "/etc/pacman.conf"
  sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 4/" "/etc/pacman.conf"
  sed -i "s/#Color/Color/" "/etc/pacman.conf"

  # makepkg Configs
  sed -i "s|#MAKEFLAGS=.*|MAKEFLAGS=-j$(nproc --all)|" /etc/makepkg.conf
  if [ "$umarch" = "true" ];then sed -i 's|CFLAGS="-march=x86-64 -mtune=generic|CFLAGS="-march=native|' /etc/makepkg.conf ;fi
  sed -i 's|#RUSTFLAGS="-C opt-level=2"|RUSTFLAGS="-C opt-level=2"|' /etc/makepkg.conf
  sed -i 's|BUILDENV=(.*)|BUILDENV=(!distcc color ccache check !sign)|' /etc/makepkg.conf
  sed -i 's|OPTIONS=(.*)|OPTIONS=(strip docs libtool staticlibs emptydirs zipman purge !debug lto)|' /etc/makepkg.conf
  if [ "$umold" = "true" ];then
    sed -i 's/\(LDFLAGS=".*\)"$/\1 -fuse-ld=mold"/' /etc/makepkg.conf
    sed -i 's/\(RUSTFLAGS=".*\)"$/\1 -C link-arg=-fuse-ld=mold"/' /etc/makepkg.conf
  fi
  sed -i 's/\(COMPRESSZST=(.*\))$/\1-threads=0 -)/' /etc/makepkg.conf
  sed -i 's/\(COMPRESSXZ=(.*\))$/\1-threads=0 -)/' /etc/makepkg.conf

  # Install & Upgrade Packages
  pacman -Syuu --noconfirm --needed base-devel psmisc mold ccache jq git sudo
}

add-nroot-user() {
  # Add a non-root user (makepkg doesn't accept root)
  groupadd sudo
  useradd -m user || true
  usermod -aG sudo user
  echo "## Allow user to execute any root command
  %user ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> "/etc/sudoers"
}

install-yay() {
  cd /home/user/ || exit 1
  sudo -u user bash <<EXC
  git clone "https://aur.archlinux.org/yay.git"
  cd yay || exit 1
  makepkg -Csi --noconfirm --needed
EXC
}

check-pkg() {
  local AUR_PKG=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].PackageBase');
  if [ "$AUR_PKG" = null ];then
    pr "$PACKAGE Package not found in AUR Repo || Abort"
    exit 1
  else
    pr "$PACKAGE Package is Available Continue to Build"
    install-yay
  fi
}

build (){
  cd "/home/user/" || exit 1
  local AUR_PKG=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].PackageBase');
  # Build Package
  export USE_CCACHE=1
  export CCACHE_EXEC=/usr/bin/ccache
  ccache -M "$CCACHE_SIZE"
  sudo -u user bash <<EXU
  mkdir -p /home/user/build
  yay -S --rebuildall --noconfirm --noprogressbar --builddir="/home/user/build" "$PACKAGE"
EXU
}

get-env-vars() {
  local AUR_PKG=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].PackageBase');
  # Get Env Vars
  cd "/home/user/build/$AUR_PKG" || exit 1
  mkdir -p /build/; {
  echo "Package : $(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].PackageBase')"
  echo "Description : $(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].Description')"
  echo "Version : $(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].Version')"
  echo "Arch : $(grep -E '^arch=' PKGBUILD | cut -d'=' -f2)"
  echo "Source URL : $( curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].URL')"
  echo "Dependency : $(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].Depends[]' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')"
  echo "Optional Dependency : $(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].OptDepends[]' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')"
  echo "Make Dependency Used : $(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].MakeDepends[]' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')"
  } >> /build/build.md
}

get-packages() {
  # Copy compiled package
  mkdir -p /build/packages
  find "/home/user/build" -type f -name "*.pkg*" -exec cp -v {} "/build/packages" \;
}

get-logs() {
  # Copy logs
  mkdir -p /build/logs
  find "/home/user/$AUR_PKG" -type f -name "*.log" -exec cp -v {} "/build/logs" \; 2>/dev/null
  pr "check /build/logs for build logs"
}
