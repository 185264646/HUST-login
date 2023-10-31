#!/bin/bash

shopt -s globstar
if [ $# -eq 0 ]; then
	shellcheck -s bash ./**/*.sh
else
	shellcheck -s bash "$1"
fi
