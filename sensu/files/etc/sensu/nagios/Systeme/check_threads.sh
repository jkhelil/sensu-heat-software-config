#!/bin/bash
###########################################################################
###########################################################################
# Surveillance du nombre de threads utilises sous Solaris et Linux
###########################################################################
# usage : check_threads.sh -w <WARNING_THRESHOLD> -c <CRITICAL_THRESHOLD> [-Z]
#
# 22/01/10 (JCU): Version initiale
# 23/02/10 (MGK): Ajout du support linux
# 28/02/12 (SBO): Ajout flag pour compteur de process Zombies
# 29/01/13 (JCU): Fix Linux ps
#
###########################################################################
###########################################################################

function help {
	echo -e "\n\tCe plugin affiche le nombre de threads actifs sur le système\n\n\t`basename $0`:\n\t\t-c <critical_level>\tSi le nombre de threads actifsdépasse <critical_level>, le plugin renvoie l'état CRITICAL\n\t\t-w <warning_level>\tSi le nombre de threads actifs se situe entre <warning_level> et <critical_level>, le plugin renvoie l'état WARNING\n"
	exit -1
}

retour=""
perfdata=""

# Getting parameters:
ZOMBIES=""
while getopts "w:c:hZ" OPT; do
	case $OPT in
		"w") warning=$OPTARG;;
		"c") critical=$OPTARG;;
		"h") help;;
		"Z") ZOMBIES="eval grep defunct | grep -v grep |" ;;
	esac
done

# Checking parameters:
( [ "x$warning" == "x" ] || [ "x$critical" == "x" ] ) && echo "ERREUR: Vous devez spécifier les niveaux WARNING et CRITICAL" && exit 3
[[ "$warning" -ge  "$critical" ]] && echo "ERREUR: le niveau CRITICAL doit être supérieur au niveau WARNING" && exit 3


# Doing the actual check:
case `uname` in
	SunOS)
		threads=`ps -efL |$ZOMBIES wc -l| tr -s ' '`
		;;
	Linux)
		threads=`ps -efL |$ZOMBIES wc -l`
		#threads=`ps axms |$ZOMBIES wc -l`
		;;
	*)
		echo "OS non supporté par ce plugin"
		exit 3;;
esac

threads=`echo $threads | tr -s ' '`

# Comparing the result and setting the correct level:
if [[ $threads -ge $critical ]]; then
	retour="CRIT=${threads}"
	status=2
elif [[ $threads -ge $warning ]]; then
	retour="WARN=${threads}"
	status=1
else
	retour="OK - $threads"
	status=0
fi
#Message completion, depending of what is monitored here
if [ "x$ZOMBIES" == "x" ]; then
	retour="${retour}_threads_actifs"
	perfdata="threads=$threads"
else
	retour="${retour}_zombies"
	perfdata="zombies=$threads"
fi

# Printing the results
echo "$retour|$perfdata"

# Bye !
exit $status
