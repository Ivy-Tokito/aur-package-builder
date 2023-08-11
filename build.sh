#!/usr/bin/bash
set -e 

# commit your package name Here
PACKAGE="protonvpn-gui"

if [ "$1" = "setupenv" ]; then

# Env Config
sed -i "s/#NoProgressBar/NoProgressBar/" "/etc/pacman.conf"
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 4/" "/etc/pacman.conf"
sed -i "s/#Color/Color/" "/etc/pacman.conf"

# Install package
pacman -Syuu --noconfirm --needed base-devel mold ccache git sudo

# Build Configs
sed -i "s|#MAKEFLAGS=.*|MAKEFLAGS=-j$(nproc)|" /etc/makepkg.conf
sed -i 's|CFLAGS="-march=x86-64 -mtune=generic|CFLAGS="-march=native|' /etc/makepkg.conf
sed -i 's|#RUSTFLAGS="-C opt-level=2"|RUSTFLAGS="-C opt-level=2"|' /etc/makepkg.conf
sed -i 's|BUILDENV=(.*)|BUILDENV=(!distcc color ccache check !sign)|' /etc/makepkg.conf
sed -i 's|OPTIONS=(.*)|OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)|' /etc/makepkg.conf
sed -i 's/\(LDFLAGS=".*\)"$/\1 -fuse-ld=mold"/' /etc/makepkg.conf
sed -i 's/\(RUSTFLAGS=".*\)"$/\1 -C link-arg=-fuse-ld=mold"/' /etc/makepkg.conf
sed -i 's/\(COMPRESSZST=(.*\))$/\1-threads=0 -)/' /etc/makepkg.conf
sed -i 's/\(COMPRESSXZ=(.*\))$/\1-threads=0 -)/' /etc/makepkg.conf

get_env-var () {
mkdir -p /build/
echo "Package : $(cat PKGBUILD | grep -oP '^pkgname=\K[^ _]+')" >> /build/build.md
echo "Description : $(cat PKGBUILD | grep 'pkgdesc' | cut -d "=" -f 2)" >> /build/build.md
echo "Version : $(cat PKGBUILD | grep -oP '^pkgver=\K[^ _]+')" >> /build/build.md
echo "Arch : $(cat PKGBUILD | grep -oP '^arch=\K[^ _]+')" >> /build/build.md
echo "Source URL : $(cat PKGBUILD | grep -oP '^url=\K[^ _]+')" >> /build/build.md
echo "Dependency : $(awk -v RS=")" '/depends=\(/ && !/optdepends/ && !/makedepends/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD)" >> /build/build.md
echo "Optional Dependency : $(awk -v RS=")" '/optdepends=\(/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD)" >> /build/build.md
echo "Make Dependency Used : $(awk -v RS=")" '/makedepends=\(/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD)" >> /build/build.md
}

# Adduser
groupadd sudo
useradd -m user || true
usermod -aG sudo "user"
echo "## Allow user to execute any root command
%user ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> "/etc/sudoers"
cd /home/user

# Clone repo
git clone "https://aur.archlinux.org/$PACKAGE.git"
chown -R user:user "$PACKAGE"
cd "$PACKAGE"
get_env-var
sudo -u user bash <<EXC
makepkg -Cs --verifysource --noconfirm --needed
EXC
exit 0

elif [ "$1" = "build" ]; then
# Build Package
cd "/home/user/$PACKAGE"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 8G

sudo -u user bash <<EXC
makepkg -CLs --noconfirm --needed
EXC

# Copy compiled package
mkdir -p /build/packages
cp -v *.pkg*  "/build/packages"
# Copy logs
mkdir -p /build/logs
cp -v *.log /build/logs 2>/dev/null
echo "done"
fi
