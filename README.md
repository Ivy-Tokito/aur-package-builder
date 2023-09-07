#### ⚠️ Not Recomended For Running Locally.

# AUR-Package-Builder

[![AUR Package Builder](https://github.com/Tokito-Kun/aur-package-builder/actions/workflows/build.yml/badge.svg)](https://github.com/Tokito-Kun/aur-package-builder/actions/workflows/build.yml)

Extensive AUR Package builder

## Usage:
* Star the repo :eyes:
 * [Fork the repo](https://github.com/Tokito-Kun/aur-package-builder/fork) or use it as a template.
 * Add your Package Name in Variable **PACKAGE** [config.conf](./config.conf).
 * On commit Push the [workflow](../../actions/workflows/build.yml) will Run.
 * Grab your Packages [releases](../../releases).

## Note:
 * commit the package name exactly as in [AUR Package Repository](https://aur.archlinux.org/).
 * if build fails due to Prerequisite Packages add them in Variable **PREQ** [config.conf](./config.conf).
 * Add any custom commands to run before build starts in Variable **CMD** [config.conf](./config.conf).
 ##
```console
$ # commit your package name Here
$ PACKAGE=""
```
