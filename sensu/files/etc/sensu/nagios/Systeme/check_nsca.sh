#!/bin/bash
#
# NSCA Nagios service results monitor plugin for Nagios
# Written by Thomas Sluyter (nagios@kilala.nl)
# By request of KPN-IS, i-Provide, the Netherlands
# Last Modified: 16-08-2006
# 
# Usage: ./check_nsca
#
# Description:
# Aside from checking whether the NSCA process is still running, this script
# also attempts to insert a message into the Nagios queue. After sending a 
# message to the NSCA daemon, it will verify that the message is received by
# Nagios, by checking the nagios.log file. 
#
# Limitations:
#   This script should work properly on all implementations of Linux, Solaris
# and Mac OS X.
#
# Output:
# If the NSCA daemon, or something along the message path, is borked, a 
# CRIT message will be issued. 
#

# You may have to change this, depending on where you installed your
# Nagios plugins
PROGNAME="check_nsca"
PATH="/usr/bin:/usr/sbin:/bin:/sbin"

HOSTNAME=`hostname | tr '[A-Z]' '[a-z]' | sed 's/^./\u&/'`

NAGIOSHOME="/usr/local/nagios"
LIBEXEC="/export/xsou/nrpe/product/current/libexec"
NAGVAR="/var/log/nagios"
NAGBIN="/usr/sbin"
NAGETC="/etc/nagios"

. $LIBEXEC/utils.sh


### REQUISITE NAGIOS COMMAND LINE STUFF ###

print_usage() {
	echo "Usage: $PROGNAME"
	echo "Usage: $PROGNAME --help"
}

print_help() {
	echo ""
	print_usage
	echo ""
	echo "NSCA Nagios service results monitor plugin for Nagios"
	echo ""
	echo "This plugin not developped by the Nagios Plugin group."
	echo "Please do not e-mail them for support on this plugin, since"
	echo "they won't know what you're talking about :P"
	echo ""
	echo "For contact info, read the plugin itself..."
}

while test -n "$1" 
do
	case "$1" in
	  --help) print_help; exit $STATE_OK;;
	  -h) print_help; exit $STATE_OK;;
	  *) print_usage; exit $STATE_UNKNOWN;;
	esac
done


### PLATFORM INDEPENDENCE ###

case `uname` in
	Linux) PSLIST="ps -ef";;
	SunOS) PSLIST="ps -ef";;
	Darwin) PSLIST="ps -ajx";;
	*) ;;
    esac


### CHECKING FOR THE NSCA PROCESS ###

[ `$PSLIST | grep nsca | grep -v grep | wc -l` -lt 1 ] && (echo "NSCA process not running."; exit $STATE_CRITICAL)


### INSERTING A TEST MESSAGE ###

DATE=`date +%Y%m%d%H%M`
STRING="$HOSTNAME\tFOOBAR\t0\t$DATE This is a test of the emergency broadcast system.\n"

echo -e "$STRING" | $NAGBIN/send_nsca -H `hostname`-bck -c $NAGETC/send_nsca.cfg >/dev/null 2>&1


### CHECKING THE NAGIOS LOG FILE ###

sleep 10

if [ `tail -1000 $NAGVAR/nagios.log | grep "emergency broadcast system" | grep $DATE | wc -l` -lt 1 ] 
then
	# Giving it a second try
	sleep 10
	if [ `tail -5000 $NAGVAR/nagios.log | grep "emergency broadcast system" | grep $DATE | wc -l` -lt 1 ]	
	then
		echo "NSCA daemon not processing check results."
		exit $STATE_CRITICAL
	fi
fi


### EXITING NORMALLY ###

echo "OK - NSCA working like it should."
exit $STATE_OK
