#!/bin/bash
#############################################################################
# Check du service NTP
#############################################################################
# Script lancé par NAGIOS pour vérifier qu'il existe un processus "ntpd" 
#
#############################################################################
# Usage: ./check_ntp.sh
#############################################################################
# 24/05/11	(SBO) : Création
# 27/05/14	(JCU) : test binaire ntpq (proxmox)
#############################################################################

# Emplacement des outils
home_script_generic=/etc/sensu/nagios/Generic

# Variables
PROGNAME=`basename $0`
HOSTNAME=`hostname|tr [a-z] [A-Z]`
process="ntpd"

# Vérification de la présence du check_processus
if [ ! -x $home_script_generic/check_processus.sh ]; then
        echo "DNS 3 : le script $home_script_generic/check_processus.sh est introuvable ou non executable"
        exit 3
fi

# Initialisation
seuil_offset=1000
seuil_dispersion=1000
status=0
procs=""
offset_err=""
perfdata="hostname=$HOSTNAME"

[ -x /usr/sbin/ntpq ] && NTP="/usr/sbin/ntpq" || NTP="/usr/bin/ntpq"

# Test de la présence du process
res=$(/etc/sensu/nagios/Generic/check_processus.sh -n $process 2>/dev/null)
if [ $? -ne 0 ]; then 
	procs="PROCS=$process"
	status=2
fi

#On interroge le client FTP
ntpqresult=$($NTP -p | grep -v clusternode | egrep "[0-9]")
#On vérifie le décalage de temps
offset=`echo "$ntpqresult" | egrep "^\*"`
if [ "x$offset" != "x" ]; then
	perfdata="$perfdata;`echo "$offset"| awk '{print "offset_"$1"="$(NF-1)"ms"}' | sed "s/\*//g"`"
	val_abs_offset=`echo "$offset"| awk '{print $(NF-1)}' | sed "s/-//g" | awk -F"." '{print $1}'`
	#Si offset > $seuil_offset(ms) alors pb de synchro
	if [ $val_abs_offset -ge $seuil_offset ] ; then
		offset_err="WARN=offset>${seuil_offset}ms"
		if [ $status -le 1 ] ; then status=1; fi
	fi
else
	#Si on n'a pas récupéré l'offset, on est dans un cas d'erreur ntp
	offset_err="WARN=ntp_conf_error"
	#Si pas déjà critical, alors on monte un warning
	if [ $status -le 1 ] ; then status=1; fi
fi

#On vérifie la dispersion (règle : si 2 lignes avec une dispersion > seuil, alors on prévient)
# on enlève les virgules et ajoute donc 00 à la fin du seuil : astuce pour les serveurs où les nombres à virgule engendrent des faux positifs
dispersion=`echo "$ntpqresult" | sed 's/\.//g' | awk '$NF > '"$seuil_dispersion"00' {print $1}'`
nb_dispersion_crit=`echo "$dispersion" | wc -l`
if [ $nb_dispersion_crit -gt 1 ]; then
	# On a au moins 2 serveurs de synchro avec une dispersion trop importante
	# On alerte donc avant que cela soit complètement KO (à partir de 3)
	disp_err="WARN=disp>${seuil_dispersion}ms"
	if [ $status -le 1 ] ; then status=1; fi
fi

#Sortie
if [ "x$procs" == "x" ] && [ "x$offset_err" == "x" ] && [ "x$disp_err" == "x" ]; then
	retour="Service NTP OK (`echo "$offset"| awk '{print $1}' | sed "s/\*//g"`)"
else
	retour="$procs $offset_err $disp_err"
fi
echo "$retour|$perfdata" | sed "s/^ *//g"
exit $status
