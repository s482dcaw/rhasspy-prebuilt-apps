#!/usr/bin/env bash
while [[ ! -z "$1" ]];
do
    # Check if actually a symbolic link
    if [[ -L "$1" ]]; then
        # Replace link with target
        cp --remove-destination "$(readlink "$1")" "$1"
    fi

    shift
done
