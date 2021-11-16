#!/bin/bash -x

macString=
modulus=
exponent=
pem_path=
pass_path=
encrypted_path=
TMP_FILE=

function generate_asn() {
	head="
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
 "
	head="${head}n=INTEGER:0x${modulus}
e=INTEGER:0x${exponent}"
	echo "$head">$1
	return 0
}

function pass_pad_zero() {
	pass_path=$(mktemp)
	TMP_FILE="$TMP_FILE $pass_path"
	len=${#1}
	if [[ $len -gt $2 ]]; then
		echo "password too long."
		exit 1;
	fi
	let len=$2-len
	while [[ $len -ne 0 ]]; do
		let len--
		echo -ne \\0>>"$pass_path"
	done
	echo -n "$1">>"$pass_path"
}

function get_public_key_param() {
	URL="$1/eportal/InterFace.do?method=pageInfo"
	POST_DATA="queryString="
	JSON=$(curl -sd "$POST_DATA" "$URL")
	modulus=$(echo "$JSON" | jq -r .publicKeyModulus)
	exponent=$(echo "$JSON" | jq -r .publicKeyExponent)
	return 0
}

function get_public_key_pem() {
	openssl asn1parse -genconf $1 -out ${pem_path:=$(mktemp)} >/dev/null
	TMP_FILE="$TMP_FILE $pem_path"
	return 0
}

function generate_encrypted_password() {
	ASN_PATH=$(mktemp)
	TMP_FILE="$TMP_FILE $ASN_PATH"
	generate_asn "$ASN_PATH"
	get_public_key_pem "$ASN_PATH"
	pass_pad_zero "$1>$macString" 128
	encrypted_pass=$(openssl rsautl -encrypt -pubin -keyform=DER -inkey "$pem_path" -in "$pass_path" -raw | xxd -ps -c 256)
	return 0
}

function login() { # login(user_name password)
	REDIRECT=$(curl -s 123.123.123.123 | sed -e "s/[^']*'//" -e "s/'.*//")
	HOST=$(echo $REDIRECT|sed -e "s/http:\/\///" -e "s/\/.*//")
	QUERYSTRING=$(echo $REDIRECT|sed -e "s/.*?//")
	macString=$(echo $REDIRECT|sed -e s/.*\&mac=// -e s/\&.*//)
	get_public_key_param "$HOST"
	generate_encrypted_password "$2"
	send_login_request "$HOST" "$QUERYSTRING" "$1"
	return $?
}

function send_login_request() { #send_login_request(HOST queryString user_name) (get passsword from global variables)
	POST_DATA_1="userId=$3&password=$encrypted_pass&service="
	POST_DATA_2="$2"
	POST_DATA_3="operatorPwd=&opeeratorUserId=&validcode=&passwordEncrypt=true"
	URL="http://$1/eportal/InterFace.do?method=login"
	RET=$(curl -s -d "$POST_DATA_1" --data-urlencode "queryString=$POST_DATA_2" -d "$POST_DATA_3" "$URL")
	if [[ $(echo "$RET"| jq .result) = '"success"' ]]; then
		return 0
	else
		echo "$RET"| jq -r .message
		return 1
	fi
}

function judge_if_connected_to_internet() {
	if curl -s -m 3 123.123.123.123 >/dev/null; then
		return 1 
	else
		return 0
	fi
}

function exit_handler() { # delete all temp files before exiting for security
	if [[ -n "$TMP_FILE" ]];then
		rm $TMP_FILE
	fi
}

trap "exit_handler" exit 
while getopts 'u:p:' opt; do
	case "$opt" in
		u)
			user="$OPTARG"
			;;

		p)
			pass="$OPTARG"
			;;

		?)
			echo "Usage: $0 -u {UserID} -p {password}"
			exit 1
			;;
	esac
done
if [[ $# -ne 4 ]];then
	echo "Usage: $0 -u {UserID} -p {password}"
	exit 1
fi
if judge_if_connected_to_internet ;then
	echo "Seems that you have connected to the Internet."
	exit 0
fi

shift $(($OPTIND - 1))
if [[ $# -gt 0 ]]; then
	echo "Usage: $0 -u {UserID} -p {password}"
	exit 1
fi
if login "$user" "$pass";then
	echo "login success."
	exit 0
else
	echo "login failed."
	exit 1
fi
