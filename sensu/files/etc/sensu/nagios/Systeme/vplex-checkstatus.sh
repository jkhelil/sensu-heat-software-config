#!/bin/bash 
###
### Check VPLEX status
###
# Author : Daniel Polombo
# Version : 1.0
# Release date : 2014/02

SCRIPT=$(readlink -f $0)
SCRIPTDIR=$(dirname $SCRIPT)

. $SCRIPTDIR/vplex-lib.sh

# Variables
NAMESONLY=""
LOGPREFIX="CHECK>"

ERRMSG=""

# Functions
usage () {
  BINNAME=`basename $0`
  echo "Usage : $BINNAME [-hvwo] <vplex>"
}

fullusage () {
  echo "        -h : this help"
  echo "        -v : verbose"
  echo "        -w : check witness status"
  echo "        -o : check operational status"
  echo "        vplex : vscvplex1 or vscvplex2"
}

opstatus() {
  ITEMPATH="/clusters"
  vverb "Building operational status command ..."
  LCVPLEX=$(echo $VPLEX | tr "A-Z" "a-z")
  OPSTATUSCOMMAND="expopstatus $LCVPLEX | awk -v cluster=\"$1\" '\$1 ~ cluster { print \$6; }'"
  verb "Running operational status command on $1 ..."
  RESULT=$(eval $OPSTATUSCOMMAND)
  SHORTRESULT=$(echo $RESULT | cut -c1-2)
  [ "$SHORTRESULT" = "ok" ] && return 0 || { ERRMSG="$1 operational status : $RESULT"; return 1; }
}

witstatus() {
  ITEMPATH="/cluster-witness/components"
  vverb "Building witness status command ..."
  WITSTATUSCOMMAND="expopstatus | awk '!/witness/ && /cluster/ || /server/ { sub(/\\r/,\"\",\$5); printf \"%s\", \$5; }'"
  verb "Running witness status command  ..."
  RESULT=$(eval $WITSTATUSCOMMAND)
  [ "$RESULT" = "okokok" ] && return 0 || { ERRMSG="Witness status : $RESULT"; return 2; }
}

expopstatus() {
  expect << EOF
match_max -d 50000
log_user 1
spawn -noecho ssh $1
expect "service"
send "vplexcli\n"
expect "Enter User Name:"
send "service\n"
expect "Password:"
send "Mi@Dim7T\n"
expect "VPlexcli:"
send "cd $ITEMPATH\n"
expect "VPlexcli:"
send "ll\n"
log_user 1
expect "VPlexcli:"
log_user 0
send "exit\n"
expect "service"
send "exit\n"
EOF
}

getopstatus() {
  opstatus cluster-1
  RETCODE=$((RETCODE+$?))
  opstatus cluster-2
  RETCODE=$((RETCODE+$?))
}

getwitstatus() {
  witstatus
  RETCODE=$?
}

##
## Main
##
while getopts hviwo o
do
  case "$o" in
    h) usage
       fullusage
       exit 0;;
    v) VERBOSE=$(($VERBOSE+1));;
    w) COMMAND="getwitstatus";;
    o) COMMAND="getopstatus";;
    h) help;;
  [?]) usage
       exit 1;;
  esac
done

shift $((OPTIND-1))

[ -z "$1" ] && {
  usage
  exit 1
}

VPLEX=$1
pickarray
RETCODE=0

eval $COMMAND

[ $RETCODE -ne 0 ] && echo $ERRMSG || echo "VPLEX operational status OK"
exit $RETCODE
