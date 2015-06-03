#! /bin/sh
# Metrologie iostat
# Permet d'alerter sur dépassement de seuils warning ou critical
# inspiré du check_vmstat qui n'était pas compatible avec tous les
# serveurs (colonnes attendues différentes selon serveurs)
#
# 29/02/2012 (SBO) : Création
# 01/03/2012 (SBO) : suite à remarque man pages iostat sur Sun (wt obsolète, toujours à 0)
#					refonte du mécanisme pour mesurer les iostats par device
# /!\	Les métriques diffèrent d'un OS à l'autre
#####################################################################

warn=$1
crit=$2

#Bon nombre de paramètres?
if [ $# -lt 2 ] ; then
	echo "Usage: ./check_iostat.sh <io_warn> <io_crit>"
	exit 3
fi

HOSTNAME=`hostname|tr [a-z] [A-Z]`

#SunOS ou Linux?
OS=`uname`

#Liste des devices à interroger, puis commande de stats pour tous
case $OS in
	SunOS)
		big_stats=`iostat -xn 1 10`
		devices=`echo "$big_stats" | grep -v "NFS mounted" | egrep [0-9] | awk '{print $NF}' | sort -u`
	;;
	Linux)
		big_stats=`iostat -dx 1 10`
		devices=`echo "$big_stats" | grep -v "NFS mounted" | egrep [0-9] | grep -v "^Linux" | awk '{print $1}' | sort -u`
	;;
esac

#Mise à 0 des données de métrologie
perfdata="hostname=$HOSTNAME"
#Interrogation de chaque device
for device in $devices
do
	stats=""
	case $OS in
		SunOS)
			#sortie :
			# r/s    w/s   kr/s   kw/s wait actv wsvc_t asvc_t  %w  %b device
			stats=`echo "$big_stats" | grep $device | awk '{n++;asvc_t+=$(NF-3);;wsvc_t+=$(NF-4)} END {print "'${device}'_asvc_t="asvc_t/n ";'${device}'_wsvc_t="wsvc_t/n}'| sed "s/:/_/g"`
			iowait=`echo $stats | tr ';' '\n' | grep wsvc_t | cut -d '=' -f 2 | cut -d '.' -f 1| cut -d '%' -f 1`
		;;
		Linux)
			#sortie:
			#Device:         rrqm/s   wrqm/s   r/s   w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
			stats=`echo "$big_stats" | awk '$1=="'$device'" {n++;svctm+=$(NF-1);util+=$NF} END {print "'${device}'_svctm="svctm/n ";'${device}'_util="util/n"%"}'`
			iowait=`echo $stats | tr ';' '\n' | grep util | cut -d '=' -f 2 | cut -d '.' -f 1| cut -d '%' -f 1`
		;;			
	esac

	if [ $iowait -ge $crit ] ; then
		if [ -z "$crit_status" ] ; then
			crit_status="CRIT=${device}_wsvc_t"
		else
			crit_status="$crit_status,${device}_wsvc_t"
		fi
	elif [ $iowait -ge $warn ] ; then
		if [ -z "$warn_status" ] ; then
			warn_status="WARN=${device}_wsvc_t"
		else
			warn_status="$warn_status,${device}_wsvc_t"
		fi
	fi
	# Mise à jour de la métrologie
	perfdata="$perfdata;$stats"	
done

#Sortie
status=""
if [ -n "$warn_status" ] ; then
	status="$warn_status"
	ret_code=1
fi
if [ -n "$crit_status" ] ; then
	status="$crit_status $status"
	ret_code=2
fi
if [ -z "$status" ] ; then
	status="OK"
	ret_code=0
fi
echo "$status |$perfdata"
exit $ret_code

