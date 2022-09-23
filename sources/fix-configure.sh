#!/usr/bin/env bash

if [ "$(uname --m)" = "aarch64" ]; then
    sed -i 's/-msse -msse2/-ftree-vectorize/g' /kaldi-master/src/kaldi.mk
fi
