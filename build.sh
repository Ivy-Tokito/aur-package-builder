#!/usr/bin/bash

source utils.sh
source config.conf

print_usage() {
	echo -e "Usage:\n${0} clean|setupenv|checkpkg|build|logs"
}

if [ -z ${1+x} ]; then
	print_usage
	exit 0
elif [ "$1" = "clean" ]; then
	rm -rf "/home/user/build/"
	exit 0
elif [ "$1" = "setupenv" ]; then
	setupenv
	add-nroot-user
    check-pkg
	exit 0
elif [ "$1" = "build" ]; then
	build
	get-env-vars
	get-packages && pr "Package : $PACKAGE Built Successfuly"
  exit 0
else
	print_usage
	exit 1
fi