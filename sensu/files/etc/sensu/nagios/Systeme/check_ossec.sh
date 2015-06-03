#!/bin/bash

# --- SCRIPT VARIABLE ---

PROGNAME=`basename $0`
HOSTNAME=`hostname|tr [a-z] [A-Z]`
perfdata="hostname=$HOSTNAME"
processes="ossec-agentd"
rootprocesses="ossec-logcollector ossec-syscheckd"
server_processes="ossec-analysisd ossec-remoted ossec-monitord ossec"
server_rootprocesses="ossec-logcollector ossec-syscheckd"
home_script_generic=/etc/sensu/nagios/Generic
home_script_alert=/etc/sensu/nagios/Systeme


NAME_SERVER="$HOSTNAME"
status=0


#  --- Verification de la presence du check_processus ---

if [ ! -x $home_script_generic/check_processus.sh ]; then
	echo "OSSEC 3: le script $home_script_generic/check_processus.sh est introuvable ou non executable"
	exit 3
fi

# --- Verification de la presence du script notification ---

if [ ! -x $home_script_alert/ossec_alerting.pl ]; then
	echo "OSSEC 3: le script $home_script_alert/ossec_alerting.pl est introuvable ou non executable"
	exit 3
fi


# --- Fonction de traitement des processus ---

check_process()
{
	process=$1
	if [ -n "$2" ] ; then
		res=`$home_script_generic/check_processus.sh -n "$process" -u $2 2>/dev/null`
	else
		res=`$home_script_generic/check_processus.sh -n "$process" 2>/dev/null`
	fi
	if [ $? -ne 0 ]; then
		if [ "x$retour" == "x" ]; then
			retour="KO=$process"
		else
			retour="$retour,$process"
		fi
		status=2
	fi
}


if [ "$NAME_SERVER" == "RAPAGGIO" ] ||  [ "$NAME_SERVER" == "WISCONSIN" ] ||  [ "$NAME_SERVER" == "PATRIMONIO" ] ; then
	
	server_flag=0
	server_result=`perl $home_script_alert/ossec_alerting.pl`
	nb_alert=$(echo $server_result | tr -dc '[0-9]')

	if [[ "$server_result" != *OK* ]]; then
	status=2
	#perfdata=$server_result
	#nagios_alert="$server_result;$perfdata"
	
	server_flag=1
	fi

	for i in $server_processes
	do 
	check_process "$i"
	done
	
	for i in $server_rootprocesses
	do 
	check_process "$i" root
	done

	if [ "x$retour" == "x" ]; then
		
		if [ $server_flag == 1 ]; then
			echo "$server_result|perf_alerts=$nb_alert"
		
		else  
		echo "$server_result|perf_alerts=0"

	fi
	   # echo "$nagios_alert"
	else
	echo "$retour|$perfdata"
	fi
	exit $status

else


	for i in $processes
	do 
	check_process "$i"
	done
	for i in $rootprocesses
	do 
	check_process "$i" root
	done
	
	if [ "x$retour" == "x" ]; then
	echo "OSSEC process Agent OK|$perfdata"
	else
	echo "$retour|$perfdata"
	fi

	exit $status
fi
