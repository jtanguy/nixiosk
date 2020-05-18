#!/usr/bin/env nix-shell
#!nix-shell -i bash -p rsync coreutils nix

set -eu -o pipefail

NIXIOSK="$PWD"

if [ "$#" -lt 1 ]; then
    echo Need to provide device path for SD card
    exit 1
fi

if [ "$1" = --help ]; then
    echo Usage: "$0" sdcard nixiosk.json.sample
fi

dev="$1"
if ! [ -f "$dev/dev" ]; then
    dev="/sys/block/$(echo "$1" | sed s,/dev/,,)"
fi

if ! [ -f "$dev/dev" ]; then
    echo "$dev is not a valid device."
    exit 1
fi

dev=$(readlink -f "$dev")

block="/dev/$(basename "$dev")"

shopt -s nullglob
if [ -n "$(echo "$dev"/*/partition)" ]; then
    echo "$dev has parititions! Reformat the table to avoid loss of data."
    echo
    echo "You can remove the partitions with:"
    echo "$ sudo wipefs $block"
    echo
    echo "You may need to remove and reinsert the SD card to proceed."
    exit 1
fi
shopt -u nullglob

if ! [ -b "$block" ]; then
    echo "The device file $block does not exist."
    exit 1
fi

shift

custom=./nixiosk.json
if [ "$#" -gt 0 ]; then
    if [ "${1:0:1}" != "-" ]; then
        custom="$1"
        shift
    fi
fi

if ! [ -f "$custom" ]; then
    echo "No custom file provided, $custom does not exist."
    echo "Consult README.md for a template to use."
    exit 1
fi

if ! [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    echo No default ssh key exists.
    exit 1
fi

SUDO=
if ! [ -w "$block" ]; then
    echo "Device $block not writable, trying sudo."
    SUDO=sudo
    sudo -v
fi

sd_drv=$(nix-instantiate --no-gc-warning --show-trace \
          --arg custom "builtins.fromJSON (builtins.readFile $(realpath "$custom"))" \
          "$NIXIOSK/boot" -A config.system.build.sdImage)

# nix build --keep-going --no-out-link "$sd_drv"
out=$(nix-build --keep-going --no-out-link "$sd_drv" "$@")
sd_image=$(echo "$out"/sd-image/*.img)

echo "SD image is: $sd_image"

echo "Writing to $dev, may require password."

"$SUDO" dd bs=1M if="$sd_image" of="$block" status=progress conv=fsync
