#!/bin/sh
# Surveillance des messages Système
#
# Principe :
#	analyse les logs système indiqués dans la variable VARFILES
#	récupère les lignes contenant messerr et messwar en filtrant
#	les lignes contenant nomesserr et nomesswar
#	ces mots clés sont définis dans le fichier syslog.cfg
# SBO - 26/10/2010 - Création
# SBO - 13/06/2012 - Correction/Evolution en vue utilisation pour Alteon
#######################################################

#PARAMETRES
UNKNOWN=3
CRITICAL=2
WARNING=1
OK=0


#INITIALISATION
#Répertoire de travail (surv transverse)
wdir="/appl/nrpevsc/var"
if [ ! -w $wdir ] ; then
	wdir="/tmp"
	if [ ! -w "$wdir" ] ; then
		echo "$wdir non accessible en écriture"
		exit 3
	fi
fi

# On récupère les infos, en fonction de l'OS
SERVICE=SYSLOG
OS=`uname`
case $OS in
	Linux)
		VARDIR=/var/log
		VARFILES="messages"
		TAIL="tail -n"
	;;
	SunOS)
		VARDIR=/var/log
		VARFILES="syslog"
		TAIL="tail"
	;;
	*)
		echo "$SERVICE $UNKWNON: $OS n'est pas pris en charge par cette surveillance"
		exit $UNKNOWN
	;;
esac

# Si des arguments sont passés en paramètres, alors on contourne
# l'utilisation de la sonde pour des logs techniques spécifiques
if [ $# -ge 3 ] ; then
	SERVICE=$1
	VARDIR=$2
	VARFILES="$3"
fi
#Faut-il découper à partir d'un autre champ ...
if [ $# -eq 4 ] ; then
	DECOUPAGE=$4
fi
#...que le 6e par défaut pour les messages type syslog?
if [ -z "$DECOUPAGE" ] ; then
	DECOUPAGE=6
fi

#Délai inactivité heartbeat
if [ $# -eq 5 ] ; then
	HEARTBEAT=$5
else
	HEARTBEAT=600
fi

home_config="/etc/sensu/nagios/CFG"
conf_file="`echo $SERVICE | tr "[A-Z]" "[a-z]"`.cfg"
# Vérification de la présence du fichier de configuration
if [ ! -f $home_config/$conf_file ]; then
	echo "$SERVICE $UNKWNON: Fichier $home_config/$conf_file inexistant"
	exit $UNKWNON
else
	. $home_config/$conf_file 
fi

#TRAITEMENT
code_retour=$OK
now=`date +%s`
for varfile in $VARFILES
do
	if [ ! -r $VARDIR/$varfile ] ; then
		echo "$SERVICE $UNKNOWN: impossible de lire le log $varfile"
		exit $UNKNOWN
	fi
	
	if [ -f $wdir/${SERVICE}:${varfile}.idx ] ; then
		idx=`awk '{print $1}' $wdir/${SERVICE}:${varfile}.idx`
	else
		idx=0
	fi
	if [ -z $idx ] ; then
		idx=0
	fi

	nblignes=`wc -l $VARDIR/$varfile | awk '{print $1}'`
	if [ $idx -gt $nblignes ] ; then
		idx=0 # le fichier a été écrasé, on reprend au début
	fi

	#Sur Linux, idx +1 
	case $OS in
		Linux)
		idx=`expr $idx + 1`
		;;
	esac
	
	#ajout cut pour supprimer partie date+hostname, pour permettre le repeat_count Tivoli
	if [ "x$messerr" != "x" ] ; then 
		if [ "x$nomesserr" != "x" ] ; then 
			$TAIL +${idx} $VARDIR/$varfile  2>/dev/null|egrep "$messerr" 2>/dev/null|egrep -v "${nomesserr}"  2>/dev/null | cut -d" " -f$DECOUPAGE- > $wdir/${SERVICE}:${varfile}.err
		else
			$TAIL +${idx} $VARDIR/$varfile  2>/dev/null|egrep "$messerr" 2>/dev/null| cut -d" " -f$DECOUPAGE- > $wdir/${SERVICE}:${varfile}.err
		fi
	else
		rm -f $wdir/${SERVICE}:${varfile}.err
	fi
	if [ "x$messwar" != "x" ] ; then 
		if [ "x$nomesswar" != "x" ] ; then 
			$TAIL +${idx} $VARDIR/$varfile  2>/dev/null|egrep "$messwar" 2>/dev/null|egrep -v "${nomesswar}"  2>/dev/null | cut -d" " -f$DECOUPAGE- > $wdir/${SERVICE}:${varfile}.warn
		else
			$TAIL +${idx} $VARDIR/$varfile  2>/dev/null|egrep "$messwar" 2>/dev/null| cut -d" " -f$DECOUPAGE- > $wdir/${SERVICE}:${varfile}.warn
		fi
	else
		rm -f $wdir/${SERVICE}:${varfile}.warn
	fi
	
	# Message type heartbeat
	if [ "x$messheartbeat" != "x" ] ; then 
		lastheartbeat=`cat $wdir/${SERVICE}.heartbeat`
		if [ "x$lastheartbeat" == "x" ] || [ ! -s $wdir/${SERVICE}.heartbeat ] ; then
			echo 0 > $wdir/${SERVICE}.heartbeat
		fi
		if [ `$TAIL +${idx} $VARDIR/$varfile  2>/dev/null|egrep -c "$messheartbeat" 2>/dev/null` -gt 0 ] ; then
			date +%s > $wdir/${SERVICE}.heartbeat
		fi
	else
		rm -f $wdir/${SERVICE}.heartbeat
	fi
	
	#Construction de la sortie en fonction des résultats
	result=$OK
	if [ -s $wdir/${SERVICE}:${varfile}.err ] ; then
		result=$CRITICAL
		if [ -n "$file_err" ] ; then
			file_err="${SERVICE}:${varfile},$file_err"
		else
			file_err="${SERVICE}:${varfile}"
		fi
	elif [ -s $wdir/${SERVICE}:${varfile}.warn ] ; then
		result=$WARNING
		if [ -n "$file_warn" ] ; then
			file_warn="${SERVICE}:${varfile},$file_warn"
		else
			file_warn="${SERVICE}:${varfile}"
		fi
	fi
	#Heartbeat?
	if [ -s $wdir/${SERVICE}.heartbeat ] ; then
		lastheartbeat=`cat $wdir/${SERVICE}.heartbeat`
		heartbeatmini=`expr $now - $HEARTBEAT`
		if [ $lastheartbeat -lt $heartbeatmini ] ; then
			result=$CRITICAL
			if [ -n "$missed_heartbeat" ] ; then
				missed_heartbeat="${SERVICE}:${varfile},$missed_heartbeat"
			else
				missed_heartbeat="${SERVICE}:${varfile}"
			fi
		fi
	fi
			
	
	#Mise à jour de l'index
	idx=$nblignes
	echo $idx > $wdir/${SERVICE}:${varfile}.idx
	
	#code retour global
	if [ $code_retour -lt $result ] ; then
		code_retour=$result
	fi
done	

#Sortie
if [ $code_retour -eq $OK ] ; then
	message="Messages $SERVICE OK"
else
	if [ -n "$missed_heartbeat" ] ; then
		message="HEARTBEAT=$missed_heartbeat"
	fi
	if [ -n "$file_err" ] ; then
		message="$message MSGERR=$file_err"
	fi
	if [ -n "$file_warn" ] ; then
		message="$message MSGWARN=$file_warn"
	fi
fi
echo $message | sed "s/^ //g" | sed "s/  / /g"
exit $code_retour