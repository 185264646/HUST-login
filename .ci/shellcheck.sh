#!/bin/bash

readonly DISABLED_SC="SC1091,SC2016"
run_shellcheck() {
	shellcheck -s bash -e "$DISABLED_SC" "$@"
}

shopt -s globstar
if [ $# -eq 0 ]; then
	run_shellcheck ./**/*.sh
else
	run_shellcheck "$1"
fi
