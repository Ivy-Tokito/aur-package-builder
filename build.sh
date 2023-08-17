#!/usr/bin/bash

set -x

source utils.sh
source config.conf

print_usage() {
	echo -e "Usage:\n${0} build|setupenv|checkpkg|buildeps|clean|logs"
}

if [ -z ${1+x} ]; then
	print_usage
	exit 0
elif [ "$1" = "clean" ]; then
	rm -rf "$PACKAGE"
	exit 0
elif [ "$1" = "checkpkg" ]; then
	check-pkg
	exit 0
elif [ "$1" = "setupenv" ]; then
	setupenv
	add-nroot-user "$NR_USER"
	exit 0
elif [ "$1" = "buildeps" ]; then
	cd "/home/$NR_USER" || exit 1
	clone-repo "$PACKAGE"
	ci-depends
	exit 0
elif [ "$1" = "build" ]; then
	verify-source
	build
	get-builds
	pr "Package : $PACKAGE Built Successfuly"
	exit 0
elif [ "$1" = "logs" ]; then
	get-logs
else
	print_usage
	exit 1
fi
