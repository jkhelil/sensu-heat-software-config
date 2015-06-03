#!/bin/ksh
#
# Nagios CPU Plugin
#
# Description: Check the cpu status
# Author     : Rakesh Narang
# Version    : 1.0
# 
#
# 02/12/09 (JCU): Ne remonte en CRITICAL que si processus le plus consommateur > 20%
# 23/12/09 (ADH): Moyenne CPU sur 5 mesures
# 27/07/10 (JCU): Modification des sorties pour TIVOLI
# 20/10/10 (SBO): Ajout 0 à USED et PCT pour ne pas planter les if si commande ko
# 21/10/10 (SBO): Ajout LC_NUMERIC=C car certains Solaris utilisait "," en car décimal!
#				+ Affichage charge kernel
# 02/11/10 (SBO): Suppresion fichier tampon => variable VMSTAT pour optimisation

export LC_NUMERIC=C

prog=`basename $0`
os=`uname`
HOSTNAME=`hostname|tr [a-z] [A-Z]`

if [ $# -lt 2 ]; then
echo "Usage: $0 <warning> <critical>"
exit 2
fi

# CPU threshold values
CPU_WARNING=$1 
CPU_CRITICAL=$2

if (( $CPU_CRITICAL <= $CPU_WARNING ))
then
        echo "Critical value must be more than the warning value"
        exit 5
fi

VMSTAT=`vmstat 1 6 | tail -5`
case $os in
            Linux)
				USED=`echo "$VMSTAT" | awk '{sum=$15+sum} END {print 100-sum/5}'`
				SYS=`echo "$VMSTAT" | awk '{sum=$14+sum} END {print sum/5}'`
			;;
            SunOS)
				USED=`echo "$VMSTAT" | awk '{sum=$22+sum} END {print 100-sum/5}'`
				SYS=`echo "$VMSTAT" | awk '{sum=$21+sum} END {print sum/5}'`
			;;
            *) echo "OS not supported by this check."; exit 3;;
esac

if (( 0$USED >= $CPU_CRITICAL )) 
then
	case $os in
		SunOS) PROC=`prstat | head -2 | tail -1 | awk '{ print "PID="$1 " USER="$2 " PCT="$9}'`;;
		Linux) PROC=`top | head -8 | tail -1 | awk '{ print "PID="$1 " USER="$2 " PCT="$9}'`;;
	esac
	
	# Isole le pourcentage du processus le plus consommateur
	# et retire le symbole % s'il existe
	PCT=`echo $PROC|awk '{ print $3}'`
	USER=`echo $PROC|awk '{ print $2}'`
	PCT=`echo $PCT|awk -F"=" '{ print $2 }'`
	PCT=`echo $PCT|awk -F"%" '{ print $1 }'`
	USER=`echo $USER|awk -F"=" '{ print $2 }'`

	if (( 0$PCT >= 20 )); then
		echo "CRIT=used_>${CPU_CRITICAL}%($USER)|hostname=$HOSTNAME;used=$USED%;sys=$SYS%"
        exit 2
	else
		echo "CPU WARN - used=$USED% sys=$SYS%($PROC)|hostname=$HOSTNAME;used=$USED%;sys=$SYS%"
		exit 1
	fi

elif (( 0$USED >= $CPU_WARNING )) 
then
        echo "CPU WARN - used=$USED% sys=$SYS%|hostname=$HOSTNAME;used=$USED%;sys=$SYS%"
        exit 1

elif (( $CPU_WARNING > 0$USED ))
then
        echo "CPU OK - used=$USED% sys=$SYS%|hostname=$HOSTNAME;used=$USED%;sys=$SYS%"
        exit 0
else
        echo "CPU STATUS UNKNOWN"
        exit 3
fi
