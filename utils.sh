#!/usr/bin/env bash

source custom_package_list.sh

pr() { echo -e "\033[0;32m[+] ${1}\033[0m"; }

log() { echo -e "$1  " >>"$2"; }

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
  local USER=$1
  # Add a non-root user (makepkg doesn't accept root)
  groupadd sudo
  useradd -m "$USER" || true
  usermod -aG sudo "$USER"
  echo "## Allow $USER to execute any root command
  %user ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> "/etc/sudoers"
}

get-base-pkg() {
  local PACKAGE=$1
  AUR_PKG=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].PackageBase')
}

check-pkg() {
  CHECK_REPO=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r ".resultcount")
  if [ "$CHECK_REPO" -eq 0 ];then
    pr "$PACKAGE Package not found in AUR Repo"
  else
    pr "$PACKAGE Package is Available Continue to Build"
  fi
}

clone-repo() {
  local PACKAGE=$1
  # Clone repo
  get-base-pkg "$PACKAGE"
  check-queue && PKGQ="$PKGQ $AUR_PKG"
  if [ "$SCLONE" = false ];then
    pr "Package $AUR_PKG Already in Queue"
  else
    git clone "https://aur.archlinux.org/$AUR_PKG.git"
    chown -R "$NR_USER":"$NR_USER" "$AUR_PKG"
    cd "$AUR_PKG" || exit 1
  fi
}

build-depends() { sudo -u "$NR_USER" makepkg -Csi --noconfirm --needed; }

verify-source() { sudo -u "$NR_USER" makepkg -Cs --verifysource --noconfirm --needed; }

build-package() { sudo -u "$NR_USER" makepkg -CLs --noconfirm --needed; }

get-depends() {
  local PACKAGE=$1
  # Get Depends
  MDEPS=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].MakeDepends[]' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')
  DEPS=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].Depends[]' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')
  ODEPS=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKAGE" | jq -r '.results[0].OptDepends[]' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')
  if [ "$2" = "SUB" ];then
    SUB_PACKDEPS="${MDEPS} ${DEPS} ${ODEPS}"
  else
    PACKDEPS="${MDEPS} ${DEPS} ${ODEPS}"
  fi
}

check-broken-packages() {
  local DEPENDS=$1
  if [ "$2" = "SUB" ];then
    if [[ -n ${broken[$SUBDEPENDS]} ]]; then SUB_PACKDEPNDS="${broken[$SUBDEPENDS]}"; else SUB_PACKDEPNDS="$SUBDEPENDS"; fi
  else
    if [[ -n ${broken[$DEPENDS]} ]]; then PACKDEPNDS="${broken[$DEPENDS]}"; else PACKDEPNDS="$DEPENDS"; fi
  fi
}

check-package-availability() {
  local PACKDEPNDS=$1
  if ! pacman -Si "$PACKDEPNDS" &> /dev/null; then
    killall pacman 2>/dev/null
    pr "pacman: target not found: $PACKDEPNDS" && pr "Checking For $PACKDEPNDS In AUR Repo"
    CHECK_REPO=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKDEPNDS" | jq -r ".resultcount")
    if [ "$CHECK_REPO" -eq 0 ];then pr "$PACKDEPNDS Package not found in AUR Repo Too" && exit 1
      else
      pr "$PACKDEPNDS Package found in AUR Repo | build it!"
      clone-repo "$PACKDEPNDS"
    fi
  fi
}

check-queue(){
  for package in $PKGQ; do
    if [ "$package" = "$AUR_PKG" ];then SCLONE=false; fi
  done
}

ci-depends() {
  local PACKAGE="$1"
  get-depends "$PACKAGE"
  for DEPENDS in $PACKDEPS; do
    check-broken-packages "$DEPENDS"
    check-package-availability "$PACKDEPNDS"
    ci-depends "$PACKDEPNDS"
    build-depends
  done
}

get-env-vars() {
  # Get Env Vars
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

build (){
  get-base-pkg "$PACKAGE"
  # Build Package
  cd "/home/user/$AUR_PKG" || exit 1
  export USE_CCACHE=1
  export CCACHE_EXEC=/usr/bin/ccache
  ccache -M "$CCACHE_SIZE"
  build-package
}

get-packages() {
  get-base-pkg "$PACKAGE"
  # Copy compiled package
  mkdir -p /build/packages
  find "/home/user/$AUR_PKG" -type f -name "*.pkg*" -exec cp -v {} "/build/packages" \;
}
get-logs() {
  # Copy logs
  get-base-pkg "$PACKAGE"
  mkdir -p /build/logs
  find "/home/user/$AUR_PKG" -type f -name "*.log" -exec cp -v {} "/build/logs" \; 2>/dev/null
  pr "check /build/logs for build logs"
}
