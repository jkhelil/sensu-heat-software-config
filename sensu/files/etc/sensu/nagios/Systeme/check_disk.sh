#!/bin/bash
#
#  Version initiale adaptée du script récupéré sur Nagios Exchange
#	de Thiago Varela - thiago@iplenix.com
#
# 09/11/09 (JCU): Utilisation de "df -P" sous Linux
# 11/01/10 (JCU): Modification pour checker tous les filesystems
#		  par groupes récupérés dans un fichier de CFG
# 11/02/10 (JCU): Correction sur la valorisation de $status
# 26/07/10 (JCU): Modification des sorties pour TIVOLI
# 16/05/11 (SBO): -Ajout "$" dans grep device pour match exclusif
#                 -Mise en place récup groupe spéc par host dans filesystems.cfg pour simplifier gestion groupes Centreon
#

function help {
	echo -e "\n\tCe plugin affiche le % d'espace utilisé sur une partition montée, en utilisant la commande df\n\n\t`basename $0`:\n\t\t-c <critical_level>\tSi le % d'espace utilisé dépasse <critical_level>, le plugin renvoie l'état CRITICAL\n\t\t-w <warning_level>\tSi le % d'espace utilisé se situe entre <warning_level> et <critical_level>, le plugin renvoie l'état WARNING\n\t\t-d <groups>\t\tLe groupe de FS à checker. Ex: SYS, APP, ORA\n"
	exit -1
}

home_config=/etc/sensu/nagios/CFG
perfdata=""
status=0

# Getting parameters:
while getopts "d:w:c:h" OPT; do
	case $OPT in
		"d") groups=$OPTARG;;
		"w") warning=$OPTARG;;
		"c") critical=$OPTARG;;
		"h") help;;
	esac
done

# Checking parameters:
[[ "x$groups" == "x" ]] && groups="SYS,APP,ORA,MYS"
( [ "x$warning" == "x" ] || [ "x$critical" == "x" ] ) && echo "ERREUR: Vous devez spécifier les niveaux WARNING et CRITICAL" && exit 3
[[ "$warning" -ge  "$critical" ]] && echo "ERREUR: le niveau CRITICAL doit être supérieur au niveau WARNING" && exit 3

# Vérification de la présence du fichier de configuration
if [ ! -f $home_config/filesystems.cfg ]; then
        echo "SYS 3: Fichier $home_config/filesystems.cfg inexistant"
        exit 3
else
	# Recuperation des FS à checker en fonction du groupe:
        # SYS : filesystems SYSTEME
        # APP: filesystems APPLICATIF
        . $home_config/filesystems.cfg
fi

# On initialise les perfdata
HOSTNAME="`hostname | cut -d '-' -f 1 | tr [a-z] [A-Z]`"
perfdata="hostname=$HOSTNAME"
# On regarde si ce serveur a des groupes spécifiques supplémentaires à ceux du service.
eval tmp=\$$HOSTNAME
[[ "x$tmp" != "x" ]] && groups="${groups},${tmp}"

groups=`echo $groups | sed 's/,/ /g'`

WARN=""
CRIT=""

for group in $groups
do
        eval tmp=\$$group
	for device in `ls -d $tmp 2>/dev/null`
	do
		# Doing the actual check:
		case `uname` in
	            Linux)
			used=`df -P | grep "${device}$" | head -1 | grep -v "Mounted on" | awk '{ print $5 }' | cut -d% -f1`
			free=`df -P | grep "${device}$" | head -1 | grep -v "Mounted on" | awk '{ print $4 }'`
			;;
        	    SunOS)
			used=`df -k | grep "${device}$" | head -1 | grep -v "Mounted on" | awk '{ print $5 }' | cut -d% -f1`
			free=`df -k | grep "${device}$" | head -1 | grep -v "Mounted on" | awk '{ print $4 }'`
			;;
           	 *)
			echo "OS non supporté par ce plugin"
			exit 3;;
		esac
			
		if [ "x$used" != "x" ] && [ "x$free" != "x" ]; then

			free_percent=$((100-used))

			if [[ $free -le 1048576 ]]; then
				free_size="$(bc <<< "${free}/1024")"
				free_size="${free_size} Mb"
			else
				free_size="$(bc <<< "scale=2;${free}/1024/1024")"
				free_size="${free_size} Gb"
			fi

			# Comparing the result and setting the correct level:
			if [[ $used -ge $critical ]]; then
				if [ "x$CRIT" == "x" ]; then
					CRIT="$device"_"(>${critical}%)"
				else
					CRIT="$CRIT,$device"_"(>${critical}%)"
				fi
			elif [[ $used -ge $warning ]]; then
				if [ "x$WARN" == "x" ]; then
                                        WARN="$device"_"(${free_percent}%)"
                                else
                                        WARN="$WARN,$device"_"(${free_percent}%)"
                                fi
     			fi


			# Perf Datas
			if [ ! `echo $device | grep "/U"` ] && [ ! `echo $device | grep "/export/dmg/oracle"` ]; then
				if [ "x$perfdata" == "x" ]; then
					perfdata="$device=${free_percent}%"
				else
					perfdata="$perfdata;$device=${free_percent}%"
				fi
			fi
		fi
	done
done

# Printing the results
if [ "x$WARN" != "x" ]||[ "x$CRIT" != "x" ]; then
	if [ "x$WARN" != "x" ]; then
		retour="WARN=$WARN"
		status=1
	fi
	if [ "x$CRIT" != "x" ]; then
		if [ "x$retour" == "x" ]; then
			retour="CRIT=$CRIT"
		else
			retour="$retour CRIT=$CRIT"
		fi
		status=2
	fi
else
	retour="FileSystems OK"
fi

echo "$retour|$perfdata"

# Bye !
exit $status
