#!/bin/bash
#############################################################################
# Check du service SYSLOG-NG
#############################################################################
# Script lanc� par NAGIOS pour v�rifier:
# - Qu'il existe le process SYSLOG-NG
#
#############################################################################
# Usage: ./check_syslogng.sh
#############################################################################
# 30/03/12 (SBO): Version initiale
# ??/??/?? (SBO): Ajout metro syslogng si stats dispo (g�n�ralement serveurs Flume)
# 					Test 1: dropped > seuil
# 					Test 2 : processed �gal entre destination et source
# 						->Pr�requis: norme de nommage des "files" non encore respect�e
# ??/??/13 (SBO): Ajout	test 3: stored > seuil
# 27/11/13 (SBO): Evolution pour passage en param et/ou surcharge seuils dropped et stored
#############################################################################


# Emplacement des outils
home_script_generic=/etc/sensu/nagios/Generic
home_toolbox=/HOME/uxwadm/scripts
home_config=/etc/sensu/nagios/CFG


#Fonction qui r�cup�re les seuils param�tr�s dans le fichier de conf du service
get_thresholds() {
	seuil=""
	#Attention, dans le fichier de param il faut remplacer les # par _DIESE_ sinon erreur de syntaxe
	attr="`echo $1 | sed 's/-/_/g' | sed 's/#/_/g'`"
	metrique="$2"
	#Si le fichier existe, on tente de r�cup�rer les seuils qui y sont d�finis
	if [ -f $home_config/syslogng_thresholds.cfg ] ; then
		if [ "x$attr" != "x" ] && [ "x$metrique" != "x" ] ; then
			# Attribut sp�cifique pass� en param�tre de la fonction, on cherche pr�cis�ment ce seuil
			eval seuil=\$\{${attr}_${metrique}\}
		fi
	fi
	
	#Au cas o� on n'a rien trouv�, on prend les seuils par d�faut du service
	if [ "x$seuil" == "x" ] || [ "x$seuil" == "x$" ]; then
			eval seuil=\$seuil_${metrique}
	fi
}


# Variables
PROGNAME=`basename $0`
HOSTNAME=`hostname|tr [a-z] [A-Z]`
perfdata="hostname=$HOSTNAME"
status=0
processes="supervising.*syslog-ng syslog-ng"
OS=`uname`
to_check=0
case $OS in
	SunOS) 
		rootprocesses=".syslogd"
		to_check=1
	;;
	Linux) 
		RPMQA=`rpm -qa 2>/dev/null`
		if [ -n "`echo "$RPMQA" | egrep "sys.+logd"`" ] ; then
			rootprocesses=".{0,1}syslogd"
			to_check=1
		fi
	;;
esac

#Seuils en param, en fichier de conf, ou par d�faut?
if [ $# -ge 2 ]; then
	seuil_dropped=$1
	seuil_stored=$2
else
	# Seuil par d�faut si aucun autre trouv�
	seuil_dropped=1000 
	seuil_stored=100000
fi
# + On charge les seuils sp�cifiques s'ils existent
if [ -f $home_config/syslogng_thresholds.cfg ]; then
		. $home_config/syslogng_thresholds.cfg
fi
retour=""


check_process()
{
	process=$1
	if [ -n "$2" ] ; then
		res=`/etc/sensu/nagios/Generic/check_processus.sh -n "$process" -u $2 2>/dev/null` 
	else
		res=`/etc/sensu/nagios/Generic/check_processus.sh -n "$process" 2>/dev/null` 
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

# V�rification de la pr�sence du check_processus
if [ ! -x $home_script_generic/check_processus.sh ]; then
        echo "Syslog 3: le script $home_script_generic/check_processus.sh est introuvable ou non executable"
        exit 3
fi

#Process root, syslogd par d�faut
for i in $rootprocesses
do
	check_process "$i" root
done
retour="`echo $retour | sed 's/.{0,1}//g'`"

flag_ng=0
flag_stats=0
#Process syslog-ng si install�
if [ -n "`echo "$RPMQA"| egrep "syslogng|syslog-ng"`" ]; then
	flag_ng=1
	
	#Cas particulier pour les serveurs haproxy
	if [ -n "`echo "$RPMQA"| grep "haproxy"`" ] ; then
		user=hapadm
	else
		#Syslog-ng install� pour la centralisation (si home user syslogng)
		if [ -d "/HOME/syslogng" ]; then
			if [ -s /HOME/syslogng/current/etc/syslog-ng.conf ] ; then
				user=syslogng
			else
				flag_ng=0	# ce syslogng n'est pas configur�
			fi
		else
			if [ -z "`echo "$RPMQA"| egrep "syslogng|syslog-ng"|grep "applicatif"`" ]; then
				flag_ng=0	# on limite la surveillance au syslogng applicatif de la centralisation
			else
				#il y a un syslog-ng install�, mais non standard � la centralisation ou haproxy
				user=root
			fi
		fi
	fi
fi

if [ $flag_ng -eq 1 ] ; then	
	#On v�rifie les processes
	for i in $processes
	do
		check_process "$i" $user
	done
	
	#Est-ce que l'outil de stats est accessible?
	if [ -n "`sudo -l 2>/dev/null | grep syslog-ng-ctl`" ] ; then
		flag_stats=1
		stats_syslogng="`sudo -u $user /export/product/syslogng/current/sbin/syslog-ng-ctl stats 2>/dev/null`"
		
		#Test 1 et 3 regroup�s suite � �vol possibilit� surcharge seuils%appli
		#Test 2 ne peut tjrs pas �tre r�alis�
		for metrique in dropped stored
		do
			eval $metrique=""
			for bad_metrique in `echo "$stats_syslogng" | awk -F";" '$(NF-1) ~ "'$metrique'"{print $2";"$NF}'`
			do
				appli="`echo $bad_metrique | cut -d\; -f1`"
				val=`echo $bad_metrique | cut -d\; -f2`
				get_thresholds "$appli" $metrique
				if [ $val -gt $seuil ] ; then
					eval tmp=\$$metrique
					if [ "x$tmp" == "x" ] ; then
						type_err=`echo $metrique| tr "[a-z]" "[A-Z]"`
						eval $metrique="$type_err=${appli}\(\>${seuil}\)"
					else
						eval $metrique="\$tmp,$appli\(\>${seuil}\)"
					fi
				fi
			done
		
			#Si on a des erreurs, on l'ajoute � la sortie, et on force en CRITICAL
			eval tmp=\$$metrique
			if [ "x$tmp" != "x" ] ; then
				retour="$tmp $retour"
				if [ $status -lt 2 ] ; then
					status=1
				fi
			fi
		done
	fi
fi

if [ "x$retour" == "x" ]; then
	if [ $flag_ng == 1 ] ; then
		retour="Syslogng OK"
		if [ $flag_stats == 1 ] ; then
			retour="$retour Stats OK"
		fi
	elif [ $to_check == 1 ] ; then
		retour="Syslogd OK $retour"
	else
		retour="No Syslog process to check"
	fi
fi

echo "$retour|$perfdata"
exit $status
