#!/usr/bin/env bash

# armhf
if [[ -f '/usr/lib/arm-linux-gnueabihf/libatlas.so' ]]; then
    export ATLASLIBDIR='/usr/lib/arm-linux-gnueabihf'
fi

# aarch64
if [[ -f '/usr/lib/aarch64-linux-gnu/libatlas.so' ]]; then
    export ATLASLIBDIR='/usr/lib/aarch64-linux-gnu'
fi
