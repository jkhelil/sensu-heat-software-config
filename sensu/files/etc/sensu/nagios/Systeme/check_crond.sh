#!/bin/bash
#############################################################################
# Check du service CRON
#############################################################################
# Script lancé par NAGIOS pour vérifier qu'il existe un processus "crond" 
#
#############################################################################
# Usage: ./check_crond.sh
#############################################################################
# 13/09/11	(SBO) : Création
# 27/05/14	(JCU) : process cron au lieu de crond sur Proxmox
#############################################################################

# Emplacement des outils
home_script_generic=/etc/sensu/nagios/Generic

# Variables
PROGNAME=$(basename $0)
HOSTNAME=$(hostname|tr [a-z] [A-Z])
OS=$(uname)

case $OS in
	SunOS)
		process="/usr/sbin/cron";;
	Linux)
		PVEVERSION=$(pveversion 2>/dev/null)
		echo $PVEVERSION | grep "pve-manager" > /dev/null
		[ $? -eq 0 ] && process="cron" || process="crond"
		# Est-ce que incron est installé sur ce serveur?
		rpm -q vsc_incron >/dev/null 2>&1 && process="$process incrond"
		;;
	*)
		echo "OS $OS non pris en charge"
		exit 3
		;;
esac

# Vérification de la présence du check_processus
if [ ! -x $home_script_generic/check_processus.sh ]; then
        echo "CRON 3 : le script $home_script_generic/check_processus.sh est introuvable ou non executable"
        exit 3
fi

# Initialisation
status=0
retour=""
perfdatas="hostname=$HOSTNAME"

for p in $process
do
	# Test de la présence du process
	res=`/etc/sensu/nagios/Generic/check_processus.sh -n $p -u root 2>/dev/null` 
	if [ $? -ne 0 ] ; then 
		if [ "x$retour" == "x" ] ; then
			retour="PROCS=$p"
		else
			retour="$retour,$p"
		fi
		status=2
	fi
done
if [ "x$retour" == "x" ] ; then
	retour="CRON Daemon OK"
fi
echo "$retour|$perfdatas"
exit $status
