#!/bin/bash
###########################################################################
# Healthcheck des baies EMC Clariion
# Wrapper pour le check_clariion.pl
###########################################################################
# usage : check_clariion.sh <SERVICEDESC> <HOSTNAME>
#
# 18/07/11 (JCU): 	Version initiale
###########################################################################

PROGNAME=`basename $0`

###########################################################################
# USAGE
###########################################################################
# cas d erreur : taille de l'argument différente de 2
if [ $# -ne 2 ]; then
	echo "EMC 3: $PROGNAME <SERVICEDESC> <HOSTNAME>"
	exit 3
fi

###########################################################################
# INITIALISATION
###########################################################################
script=`echo ${PROGNAME} | cut -d. -f1`
perl_script=/etc/sensu/nagios/Systeme/${script}.pl
check=`echo $1 | tr [A-Z] [a-z]`
baie=`echo $2 | cut -d_ -f1`
baie=`echo $baie | tr [A-Z] [a-z]`
sp=`echo $2 | cut -d_ -f2`
sp=`echo $sp | tr [A-Z] [a-z]`

if [ "$check" == "sp" ]; then
	elem=`expr substr $sp ${#sp} 1`
	elem=`echo $elem | tr [a-z] [A-Z]`
	check="$check --sp $elem"
elif [ `echo $check | grep hba` ]; then
        elem=`expr substr $sp ${#sp} 1`
        elem=`echo $elem | tr [a-z] [A-Z]`
	elem2=`expr substr $check ${#check} 1`
	check="portstate --sp $elem --port $elem2"
fi

retour=`${perl_script} -H ${baie}_${sp} -t ${check} 2>/dev/null`
status=$?

if [ $status -eq 3 ]; then
	echo "EMC 3: appel incorrect de `basename $perl_script`"
	exit 3
else
	echo $retour
	exit $status
fi
