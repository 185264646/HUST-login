# SPDX-License-Identifier: GPL-2.0-or-later
# Cooyright 2023 Yang Xiwen

.PHONY: all check shellcheck unittest

all: check

check: shellcheck unittest

shellcheck:
	.ci/shellcheck.sh

unittest:
	cd tests && ./tests.sh
