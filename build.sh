#!/usr/bin/bash
set -ex 

# commit your package name Here
PACKAGE="atom"

declare -A broken=(
  ["python-dbus"]="dbus-python"
  ["electron11"]="electron11-bin"
)

if [ "$1" = "setupenv" ]; then

# Env Config
sed -i "s/#NoProgressBar/NoProgressBar/" "/etc/pacman.conf"
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 4/" "/etc/pacman.conf"
sed -i "s/#Color/Color/" "/etc/pacman.conf"

# Install package
pacman -Syuu --noconfirm --needed base-devel mold ccache jq git sudo

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
pwd

# Check Depends
PACKDEPS=$(awk -v RS=")" '/depends=\(/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD | grep -o '"[^"]\+"' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')
echo "begin for loop for $PACKDEPS"
for _package in $PACKDEPS; do
if [[ -n ${broken[$PACKDEPS]} ]]; then PACKDEPNDS="${broken[$PACKDEPS]}"; else PACKDEPNDS="$PACKDEPS"; fi
echo "$PACKDEPNDS"
    if ! pacman -Si "$PACKDEPNDS" &> /dev/null; then
        echo "Warning: pacman: target not found: $PACKDEPNDS" && echo "Building and installing package $PACKDEPNDS via AUR Repo"
        CHECK_REPO=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$PACKDEPNDS" | jq -r ".resultcount")
        if [ "$CHECK_REPO" -eq 0 ];then echo "$PACKDEPNDS Package not found in AUR Repo" && exit 1;fi
        git clone "https://aur.archlinux.org/$PACKDEPNDS.git"
        cd "$PACKDEPNDS" || exit
    
    SUB_PACKDEPS=$(awk -v RS=")" '/depends=\(/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD | grep -o '"[^"]\+"' | sed 's/"//g' | sed 's/>=[^"]*//g' | tr '\n' ' ')
    if [[ -n ${broken[$SUB_PACKDEPS]} ]]; then SUB_PACKDEPNDS="${broken[$SUB_PACKDEPS]}"; else SUB_PACKDEPNDS="$SUB_PACKDEPS"; fi
        for _sub_package in $SUB_PACKDEPNDS; do
        echo "$SUB_PACKDEPNDS"
            if ! pacman -Si "$SUB_PACKDEPNDS" &> /dev/null; then
                echo "Warning: pacman: target not found: $SUB_PACKDEPNDS" && echo "Building and installing package $SUB_PACKDEPNDS via AUR Repo"
                CHECK_SUB_REPO=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$SUB_PACKDEPNDS" | jq -r ".resultcount")
                if [ "$CHECK_SUB_REPO" -eq 0 ];then echo "$SUB_PACKDEPNDS Package not found in AUR Repo" && exit 1;fi
                git clone "https://aur.archlinux.org/$SUB_PACKDEPNDS.git"
                cd "$SUB_PACKDEPNDS" || exit
                makepkg -Csi --noconfirm --needed
            fi
        done
        makepkg -Csi --noconfirm --needed
    fi
done

# Get Env Vars
mkdir -p /build/
{ 
echo "Package : $(PKGBUILD | grep -oP '^pkgname=\K[^ _]+')"
echo "Description : $(PKGBUILD | grep 'pkgdesc' | cut -d "=" -f 2)"
echo "Version : $(PKGBUILD | grep -oP '^pkgver=\K[^ _]+')"
echo "Arch : $(PKGBUILD | grep -oP '^arch=\K[^ _]+')"
echo "Source URL : $(PKGBUILD | grep -oP '^url=\K[^ _]+')"
echo "Dependency : $(awk -v RS=")" '/depends=\(/ && !/optdepends/ && !/makedepends/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD)"
echo "Optional Dependency : $(awk -v RS=")" '/optdepends=\(/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD)"
echo "Make Dependency Used : $(awk -v RS=")" '/makedepends=\(/ {gsub(/^.*\(/,""); gsub(/'\''/,""); print}' PKGBUILD)"
} >>/build/build.md

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
find "/home/user/$PACKAGE" -type f -name "*.pkg*" -exec cp -v {} "/build/packages" \;
# Copy logs
mkdir -p /build/logs
find "/home/user/$PACKAGE" -type f -name "*.log" -exec cp -v {} "/build/logs" \; 2>/dev/null
echo "done"
fi
