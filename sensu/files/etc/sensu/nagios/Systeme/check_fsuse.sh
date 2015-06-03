#!/bin/ksh
#
# Surveillance des FS Unix/Linux
#
# 01/06/11 (SBO) : Création
#			Inspiré du check_disk de JCU et d'une surveillance précédemment créée pour ITM par moi-même ;)
# 13/10/14 (JCU) : ignore les alertes "df ne repond pas". Si NAS inacessible, remonte quand même les FS locaux
#


# Initialisation
home_config=/etc/sensu/nagios/CFG
CFG_FILE=filesystems_tresholds
HOST=$(hostname | tr "[a-z]" "[A-Z]")
OS_TYPE=$(uname)

# On initialise les perfdata et les sorties en erreur
WARN=""
CRIT=""

# Commande DF selon l'OS
case $OS_TYPE in
	Linux)
		DF="df -P"
		DFLOCAL="df -P -l"
		;;
	SunOS)
		DF="df -k"
		;;
	 *)
		echo "OS non supporté par ce plugin"
		exit 3;;
esac

#Répertoire de travail
wdir="/appl/nrpevsc/var"
if [ ! -w $wdir ] ; then
	wdir="/tmp"
	[ ! -w "$wdir" ] && echo "$wdir non accessible en écriture" && exit 3
fi

#Avant de contrôler tous les FS, on vérifie celui de travail
seuil_wdir=$($DF $wdir | awk '{print $(NF-1)}' | tail -1 | sed "s/%//g")

if [ 0$seuil_wdir -ge 98 ] ; then
	fs_wdir="$($DF $wdir | tail -1 | awk '{print $NF}')"
	echo "CRIT=$fs_wdir|$perfdata;$fs_wdir=${seuil_wdir}%"
	exit 2
fi

#Separateur utilisé pour le awk dans le fichier de conf
separator="@"


#Fonctions
wait_or_kill(){
	PID=$1
	cpt=0
	while [ $cpt -le $2 ]
	do
		if [ $(ps -fp $PID | wc -l) -gt 1 ]; then
			cpt=$(( $cpt + 1 ))
			sleep 1
		else
			# On dépasse le compteur pour sortir de la boucle
			cpt=$(( $2 + 1 ))
		fi
	done

	if [ $(ps -fp $PID | wc -l) -gt 1 ]; then
		kill -9 $PID
		echo "$(date) Command killed: $3" >> $wdir/check_fsuse.killed
		return 3
	else
		return 0
	fi
}

## MAIN

# mise à zéro des sorties pour Centreon
perfdata=""
status=0

#Initialisation des seuils avec les valeurs par défaut
warning=90
critical=95
#... ou récupération des seuils par défaut éventuellement passés en paramètres
while getopts "w:c:" OPT; do
	case $OPT in
		"w") warning=$OPTARG;;
		"c") critical=$OPTARG;;
	esac
done

# Vérification des contraintes
( [ "x$warning" == "x" ] || [ "x$critical" == "x" ] ) && echo "ERREUR: Vous devez spécifier les niveaux WARNING et CRITICAL" && exit 3
[[ "$warning" -ge  "$critical" ]] && echo "ERREUR: le niveau CRITICAL doit être supérieur au niveau WARNING" && exit 3

# Traitement

# On execute la commande df, avec un timeout, pour vérifier qu'elle répond
($DF 2>/dev/null | grep -v "/var/run/.patch" 1>$wdir/df_nrpe 2>/dev/null) &
PID="$!"
wait_or_kill $PID 15 "df"
rc=$?
wait

# On prépare la liste éventuelle des conf spécifiques
liste_cfg=$(ls ${home_config}/${CFG_FILE}_*.cfg 2>/dev/null | sort)

# La commande ne s'est pas bien exécuté, on l'exécute de nouveau en ignorant les montages NFS
[ $rc -ne 0 ] && {
  ($DFLOCAL 2>/dev/null | grep -v "/var/run/.patch" 1>$wdir/df_nrpe 2>/dev/null) &
  PID="$!"
  wait_or_kill $PID 15 "df"
  rc=$?
  wait
  status=1
}

# Problème avec le résultat de la commande df, on sort en inconnu
if [ ! -s $wdir/df_nrpe ]; then
        retour="PROBLEME=resultat_df_vide"
        status=3

# Si la commande df s'est bien exécutée, on analyse les résultats
else
	grep -v "Mounted on" $wdir/df_nrpe | while read ligne_fs
	do
		device="$(echo $ligne_fs | awk '{print $6}')"
		used=$(echo $ligne_fs | awk '{ print $5 }' | cut -d% -f1)
		free=$(echo $ligne_fs | awk '{ print $4 }')
		
		# On prend les seuils par défaut du service
		SEUIL1=$warning
		SEUIL2=$critical

		# A moins qu'ils soient définis dans un des fichiers de conf
		# On parse d'abord le fichier global pour que les spécificités soient prioritaires sur le fichier global
		if [ -f "${home_config}/${CFG_FILE}.cfg" ] ; then
			treshold="$(grep "^$device${separator}" ${home_config}/${CFG_FILE}.cfg 2>/dev/null)"
			if [ -n "$treshold" ] ; then
				SEUIL1="$(echo $treshold | awk -F"${separator}" '{print $2}')"
				SEUIL2="$(echo $treshold | awk -F"${separator}" '{print $3}')"
			fi
		fi
		# Ensuite, on parse les fichiers plus spécifiques s'ils existent
		if [ "x$liste_cfg" != "x" ] ; then
			for file_cfg in $liste_cfg
			do
				treshold="$(grep "^$device${separator}" $file_cfg 2>/dev/null)"
				if [ -n "$treshold" ] ; then
					SEUIL1="$(echo $treshold | awk -F"${separator}" '{print $2}')"
					SEUIL2="$(echo $treshold | awk -F"${separator}" '{print $3}')"
				fi
			done
		fi
		
		if [ "x$used" != "x" ] && [ "x$free" != "x" ] && ([ $SEUIL1 -le 100 ] || [ $SEUIL2 -le 100 ]); then
			# On teste chaque seuil par rapport au % utilisé
			if [ $used -ge 100 ] && [ $SEUIL2 -le 100 ]; then # si seuil critical réel et FS full
				[ "x$CRIT" == "x" ] && CRIT="$device"_"(FULL)" || CRIT="$CRIT,$device"_"(FULL)"
			elif [ $used -ge $SEUIL2 ] && [ $SEUIL2 -le 100 ]; then
				[ "x$CRIT" == "x" ] && CRIT="$device"_"(>${SEUIL2}%)" || CRIT="$CRIT,$device"_"(>${SEUIL2}%)"
			elif [ $used -ge $SEUIL1 ] && [ $SEUIL1 -le 100 ]; then
				[ "x$WARN" == "x" ] && WARN="$device"_"(>${SEUIL1}%)" || WARN="$WARN,$device"_"(>${SEUIL1}%)"
			fi

			# Perfdata
			if [ "x$HOST" == "xOHIO" ] || [ ! `echo $device | grep "/U"` ] && [ ! `echo $device | grep "/export/dmg/oracle"` ]; then
				[ "x$perfdata" == "x" ] && perfdata="$device=${used}%" || perfdata="$perfdata;$device=${used}%"
			fi
		fi
	done
	
	# On sort les résultats
	if [ "x$WARN" != "x" ]||[ "x$CRIT" != "x" ]; then
		if [ "x$WARN" != "x" ]; then
			retour="WARN=$WARN"
			status=1
		fi
		if [ "x$CRIT" != "x" ]; then
			if [ "x$retour" == "x" ]; then
				retour="CRIT=$CRIT"
			else
				retour="CRIT=$CRIT $retour"
			fi
			status=2
		fi
	else
		[ $status -eq 0 ] && retour="FileSystems OK" || retour="FileSystems OK (local only)"
	fi
fi

[ -f $wdir/df_nrpe ] && rm -f $wdir/df_nrpe >/dev/null 2>&1

echo "$retour|$perfdata"

exit $status
