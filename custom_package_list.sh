#!/usr/bin/env bash

#Package Redirects Should Be Added Here
#i.e Packages with Diffrent names in AUR Repo or Offical Pacman Repo

declare -A broken=(
  ["python-dbus"]="dbus-python"
  ["electron11"]="electron11-bin"
)
