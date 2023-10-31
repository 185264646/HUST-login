#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (r) 2023, Yang Xiwen
#
# A bash script to login to HUST_WIRELESS
# Dependency: openssl, jq, curl and many utils provided by coreutils or busybox

### Config Variables ###

# Default timeout for curl operations (sec)
readonly CURL_TMOUT=3

### Global Variables ###
username=
password=
cert_path=
padded_pass_path=

### Helper Functions ###

# A wrapper around curl
quiet_curl() {
	if ! curl -s --connect-timeout $CURL_TMOUT "$@"; then
		network_error_handler
	fi
}

# print all arguments to stderr
log() {
	# move stderr to stdout, and print to stdout
	# see https://www.gnu.org/software/bash/manual/html_node/Redirections.html Section 3.6.9 Moving File Descriptors
	1>&2- printf %s\\n "$*"
}

internal_err() {
	log "Internal Error"
	exit 2
}

### Exception Handlers ###
#
network_error_handler() {
	log "Network is down!"
	exit 2
}

exit_handler() {
	rm -f "$cert_path" "$padded_pass_path"
}

### Main functions ###

# parse login page, echo the redirect URL
#
# parameters:
# $1: page
# 
# returns:
# 0 - OK
# 1 - Invalid page
parse_page() {
	ret="$(sed -ne "s/^<script>.*='\(.*\)'<\/script>/\1/p" <<< "$1")"
	if [ -z "$ret" ]; then
		# no matching
		return 1
	fi
	printf %s "$ret"
}

# get host from url
# parse URL to get host
# example: http://baidu.com/?abc -> baidu.com
# 
# echo:
# host
#
# return:
# 0 - success
# 1 - invalid URL
#
# note: for simplicity, this function is not robust. don't feed with unauthorized content
get_host_from_url() {
	# URL has 3 parts: prefix, host, path
	local host
	host="$(sed -ne 's/^[[:alnum:]]*:\/\/\([^/?]*\).*$/\1/p' <<< "$1")"
	if [ -z "$host" ]; then
		return 1
	fi
	printf %s "$host"
}

# get path from URL
#
# return: always 0
#
# echo path in URL
#
# if missing, nothing will be echoed
#
# example: http://example.com/test/to/path -> /test/to/path
get_path_from_url() {
	sed -ne 's/^[[:alnum:]]*:\/\/[^/?]*\([^?]*\).*$/\1/p' <<<"$1"
}

# parse URL
# e.g.: http://baidu.com/?param1=2&param2=3
# -> [[_host] = baidu.com, [param1]=2, [param2]=3]
#
# param:
# $1 - URL
# $2 - var name
parse_url() {
	# nested variable is not allowed in bash
	unset _url_param
	unset "$2"
	declare -gA _url_param
	declare -gn "$2"=_url_param
	_url_param[_host]="$(get_host_from_url "$1")" || return
	_url_param[_path]="$(get_path_from_url "$1")" || return
	local params
	params="$(extract_params_from_url "$1")" || return
	for i in $(tr '&' ' ' <<< "$params")
	do
		# $i is xx=xxx
		local name="${i%=[^=]*}"
		local val="${i#[^=]*=}"
		_url_param["$name"]="$val"
	done
}

# extract arguments in URL
# e.g.: http://baidu.com/?param1=2&param2=3 -> param1=2&param2=3
# param:
# $1: URL
# 
# return 0
#
# echo: arguments
extract_params_from_url() {
	local params
	params=$(sed -ne 's/^[^?]*?\(.*\)$/\1/p' <<< "$1")
	if [ -z "$params" ]; then
		return 0
	fi
	printf %s "$params"
}

# extract a paramter from URL
# param
# $1 - param
# $2 - URL
extract_param_from_url() {
	local params
	# extract parameters from URL
	params="$(extract_params_from_url "$1")" || return
	# split arguments to multiple records
	<<<"$params" awk "BEGIN { RS=\"&\" } { if (\$1 ~ /^$1=/) { print \$1; exit 0 } } END { exit 1 }"
}

# get current internet connection state
#
# side effects:
# none
#
# echo:
# redirection URL
#
# returns:
# 0 - have internet access
# 1 - need login
# 2 - network is down
# other - internal error
get_cur_network_state() {
	local page
	local url
	# TODO
	# Enable DoT, DoH etc.. may also prevent us fron getting the redirect URL
	page="$(quiet_curl http://detectportal.firefox.com/)" || exit 2
	# page="$(quiet_curl http://34.107.221.82/)" || exit 2
	if [ "$page" = success ]; then
		return 0
	else
		url="$(parse_page "$page")" || return 3
		# Invalid redirection page
		# Maybe either not HUST_WIRELESS or API changed
		# Please file a Issue on Github
	fi

	printf %s "$url"
	return 1
}

# get encryption cert
# get the RSA cert to encrypt password
#
# $1 - redir_url
#
# echo:
# 	cert absolute path
#
# return:
# 	0 - success
# 	other - failure
get_pub_cert() {
	local host post_data url page_info
	host="$(get_host_from_url "$1")" || return
	post_data="queryString="
	url="$host/eportal/InterFace.do?method=pageInfo"

	page_info="$(quiet_curl -d "$post_data" "$url")" || return

	# parse page_info to get exponent and modulus
	local exp mod
	exp=$(printf %s "$page_info" | jq -r -e .publicKeyExponent) || return 1
	mod=$(printf %s "$page_info" | jq -r -e .publicKeyModulus) || return 1

	# output the public key file
	# DER
	local cert
	cert="$(mktemp)"
	openssl asn1parse -out "$cert" -noout -genconf - <<EOF ||
# Copied directly from https://www.openssl.org/docs/manmaster/man3/ASN1_generate_nconf.html#EXAMPLES
# Start with a SEQUENCE
asn1=SEQUENCE:pubkeyinfo

# pubkeyinfo contains an algorithm identifier and the public key wrapped
# in a BIT STRING
[pubkeyinfo]
algorithm=SEQUENCE:rsa_alg
pubkey=BITWRAP,SEQUENCE:rsapubkey

# algorithm ID for RSA is just an OID and a NULL
[rsa_alg]
algorithm=OID:rsaEncryption
parameter=NULL

# Actual public key: modulus and exponent
[rsapubkey]
n=INTEGER:0x$mod
e=INTEGER:0x$exp
EOF
	{
		local ret=$?
		rm "$cert"
		return $ret
	}
	printf %s "$cert"
}

# pad zero to string
#
# echo: '\0' padded(truncated) string
#
# param:
# $1: string
# $2: length
pad_zero() {
	local len=${#1}
	if [ "$len" -gt "$2" ]; then
		# truncate
		head -c "$2" <<<"$1"
	else
		dd if=/dev/zero bs=1 count=$(( $2 - len )) 2>/dev/null
		printf %s "$1"
	fi
}

# encrypt password
#
# echo:
# encrypted password(hex)
#
# param:
# $1 - password
# $2 - cert path
# $3 - macString
#
encrypt_pass() {
	# pad password to 128
	# must be padded to the end
	local pass="$1>$3"
	padded_pass_path="$(mktemp)"
	>"$padded_pass_path" pad_zero "$pass" 128

	# encrypt with cert
	# use rsautl?
	openssl pkeyutl -encrypt -pubin -keyform DER -inkey "$2" -in "$padded_pass_path" -pkeyopt rsa_padding_mode:none | xxd -ps -c 256

	local ret=$?
	rm -f "$padded_pass_path"

	return $ret
}

# send login request
#
# param:
# $1 - host
# $2 - username
# $3 - password
# $4 - query string
#
# echo:
# reason
#
# return:
# 0 - success
# non-zero - fail
#
send_login_req() {
	local url="http://$1/eportal/InterFace.do?method=login"
	local data_1="userId=$2&password=$3&service=&operatorPwd=&opeeratorUserId=&validcode=&passwordEncrypt=true"

	local msg result
	msg="$(quiet_curl -d "$data_1" --data-urlencode "queryString=$4" "$url")" || return
	result="$(jq -r .result <<<"$msg")" || return
	if [ "$result" = "success" ]; then
		return 0
	else
		jq -r .message <<<"$msg"
		return 1
	fi
}

# $1 - program name
print_syntax() {
	echo "Usage: $1 -u UserId -p Password"
	echo ""
	echo "Example: $1 -u U202301001 -p 123456"
}

parse_args() {
	local opt
	while getopts "u:p:" opt; do
		case "$opt" in
			u)
				username="$OPTARG"
				;;

			p)
				password="$OPTARG"
				;;

			?)
				return 1
				;;
		esac
	done
	shift $(( OPTIND - 1 ))
	if [ -z "$username" ] || [ -z "$password" ] || [ $# -gt 0 ]; then
		return 1;
	fi
	return 0
}

# check if we are sourced
# if we are sourced, it will succeed and return to parent shell
# otherwise proceed login
2>/dev/null return || true

set -euo pipefail

trap exit_handler exit

parse_args "$@" || { print_syntax "$0"; exit 2; }

ret=0
# ensure this compound statement never fails
redir_url="$(get_cur_network_state)" || { ret=$?; true; }
case $ret in
	0)
		log "Already connected to Internet"
		exit 0
		;;

	1)
		# need login
		;;

	2)
		# network is down
		exit 1
		;;

	*)
		internal_err
		;;
esac

# Try to get login parameters from login page
cert_path=$(get_pub_cert "$redir_url") || internal_err

query_string="$(extract_params_from_url "$redir_url")" || internal_err

# the shellcheck has a false positive on this
# declare it explicitly
declare -gA redir_url_info
parse_url "$redir_url" "redir_url_info" || internal_err

host="${redir_url_info[_host]}"
[ -z "$host" ] && internal_err
mac="${redir_url_info[mac]}"
[ -z "$mac" ] && internal_err
# encrypt password
encrypted_pass=$(encrypt_pass "$password" "$cert_path" "$mac") || internal_err
if send_login_req "$host" "$username" "$encrypted_pass" "$query_string"; then
	echo success
else
	echo failed
	exit 1
fi

