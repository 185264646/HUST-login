#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2023, Yang Xiwen
#
# A script to test functions in login.sh

set -euo pipefail

source ../login.sh

### helper functions ###

# check return value, print error if non-zero
# paramter:
# $1 - eval string (mandatory)
# $2 - expected return value (optional, defaults to 0)
# $3 - expected output (optional, defaults to "")
assert() {
	ret=0
	output="$(eval "$1")" || ret=$?
	if [ "${2:-0}" -ne $ret ]; then
		printf "Assertion \"%s\" failed, expected return value %d, actual return value %d\n" "$1" "${2:-0}" "$ret"
		return 1
	fi
	if [ "$output" != "${3:-}" ]; then
		printf "Assertion \"%s\" failed, expected output %s, actual output %s\n" "$1" "${3:-}" "$output"
		return 2
	fi
	return 0
}

### Tests ###
test_parse_page() {
	# empty string
	assert 'parse_page ""' 1

	local login_page
	# shellcheck disable=SC2034
	read -r login_page <<EOF
<script>top.self.location.href='http://172.18.18.60:8080/eportal/index.jsp?wlanuserip=ab280e44c4035567e98182ed0053c8d8&wlanacname=90e89a42a2b53b8eeaeb783ea002a860&ssid=&nasip=df7f31558658bbf53ad63427680e662b&snmpagentip=&mac=288e667de9c47c2e9bd3041dca23d1a5&t=wireless-v2&url=2c0328164651e2b477e0c5f1b4858b01&apmac=&nasid=90e89a42a2b53b8eeaeb783ea002a860&vid=5539c754309b9fbd&port=26ef2a2baeda521b&nasportid=5b9da5b08a53a540806c821ff7c143818feb119a511f0bcaaf0bc043567e281f'</script>
EOF
	local url
	read -r url <<EOF
http://172.18.18.60:8080/eportal/index.jsp?wlanuserip=ab280e44c4035567e98182ed0053c8d8&wlanacname=90e89a42a2b53b8eeaeb783ea002a860&ssid=&nasip=df7f31558658bbf53ad63427680e662b&snmpagentip=&mac=288e667de9c47c2e9bd3041dca23d1a5&t=wireless-v2&url=2c0328164651e2b477e0c5f1b4858b01&apmac=&nasid=90e89a42a2b53b8eeaeb783ea002a860&vid=5539c754309b9fbd&port=26ef2a2baeda521b&nasportid=5b9da5b08a53a540806c821ff7c143818feb119a511f0bcaaf0bc043567e281f
EOF
	assert 'parse_page "$login_page"' 0 "$url"

	# a random page
	# shellcheck disable=SC2034
	local baidu='<html>
<meta http-equiv="refresh" content="0;url=http://www.baidu.com/">
</html>
'
	assert 'parse_page "$baidu"' 1
}

test_parse_url() {
	# empty string
	assert 'parse_url "" _test_var' 1
	# URL without path and parameters
	assert 'parse_url http://example.com _test_var && echo ${_test_var[_host]}' 0 example.com
	# URL without path
	assert 'parse_url "http://example.com?arg1=foo1&arg2=foo2" _test_var && echo ${_test_var[_host]} ${_test_var[arg1]} ${_test_var[arg2]}' 0 "example.com foo1 foo2"
	# URL without parameters
	assert 'parse_url "http://example.com/test/path/" _test_var && echo ${_test_var[_host]} ${_test_var[_path]}' 0 "example.com /test/path/"
	# full URL
	assert 'parse_url "http://example.com/test/path/?arg1=abc&arg2=cba" _test_var && echo ${_test_var[_host]} ${_test_var[_path]} ${_test_var[arg1]} ${_test_var[arg2]}' 0 "example.com /test/path/ abc cba"
}

test_parse_page
test_parse_url
# no need to test get_host_from_url etc..
# they are already tested during parse_url

# is there a way to test get_cur_network_state() ?
