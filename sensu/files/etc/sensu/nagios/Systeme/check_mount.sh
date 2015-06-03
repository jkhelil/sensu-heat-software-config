#!/bin/sh
# Surveillance FS basique
# Permet de s'assurer que tous les montages 
# définis en auto sont effectivement montés
#
# Principe :
# Compare les FS en montage auto définis dans (v)fstab
# avec ceux remontés par une commande df
# S'il en manque au moins un dans la sortie du df,
# alors cela remonte un WARNING avec la liste des
# FS non montés.
#
# SBO - 08/10/2010 - Création
# SBO - 11/10/2010 - Ajout Check/NoCheck
# SBO - 19/11/2010 - Ajout wait_or_kill pour timeout sur la commande df
#					car peut ne pas rendre la main si pb montage nfs
# SBO - 23/11/2010 - Fix grep -v "^#" mal positionné dans les commandes
#					+ remplacement df par mount
# SBO - 10/05/2011 - montage_nas
# SBO - 21/03/2012 - Amélioration creation du fichier TO_MOUNT (cascade de grep remplacée par un seul awk)
###########################################################################

#Fonctions
wait_or_kill(){
	PID=$1
	cpt=0
	while [ $cpt -le $2 ]
	do
		if [ `ps -fp $PID | wc -l` -gt 1 ]; then
			cpt=`expr $cpt + 1`
			sleep 1
		else
			# On dépasse le compteur pour sortir de la boucle
			cpt=`expr $2 + 1`
		fi
	done

	if [ `ps -fp $PID | wc -l` -gt 1 ]; then
		kill -9 $PID
		echo "`date` Command killed: $3" >> $wdir/check_mount.killed
	fi
}

montage_nas(){
	NAS_FILE="$1"
	while read montage
	do
		mpt="${RACINE_NAS}/`echo $montage | awk '{print $1}'`"
		if [ "x$mpt" != "x${RACINE_NAS}/" ] && [ `echo $mpt | grep -c "#"` -eq 0 ] ; then	# pour ne pas prendre les lignes vides, ou les lignes commentées
			#On ajoute chaque point de montage NAS à la liste de ce qui doit être monté
			echo $mpt >> $TO_MOUNT_FILE
			#On simule un accès pour ajouter le montage, avec une petite sécurité de 5s de timeout max 
			#Il a été obligatoire de faire un ls par montage au lieu d'un ls pour tous, comme dans la première version
			#car certains montages n'étaient pas faits. On augmente légèrement le temps de traitement, mais on sécurise le résultat!
			ls ${mpt}/ 2>/dev/null 1>/dev/null &
			PID="$!"
			wait_or_kill $PID 10 "ls ${mpt}/" &
		fi
	done < $NAS_FILE
	# wait pour attendre toutes les occurrences de wait_or_kill
	# car ne peut pas bloquer sur un ls : le wait_or_kill correspondant fera le kill
	sleep 1
	wait
}


#Initialisation
HOST=`hostname | tr [a-z] [A-Z]`

wdir="/appl/nrpevsc/var"
if [ ! -w $wdir ] ; then
	wdir="/tmp"
fi
tmpfile="$wdir/check_mount.tmp"

CFG_DIR="/etc/sensu/nagios/CFG"

CHK_FILE_BY_HOST="${CFG_DIR}/mount_${HOST}.check"
NOCHK_FILE="${CFG_DIR}/mount.nocheck"
NOCHK_FILE_BY_HOST="${CFG_DIR}/mount_${HOST}.nocheck"

IS_MOUNTED_FILE="$wdir/is_mounted"
TO_MOUNT_FILE="$wdir/to_mount"

OS=`uname`

TYPE_FS="ext3|cifs|ufs|zfs|logs|nfs|gfs2"
RACINE_NAS="/nas"

# On nettoie les tests précédents
if [ -f $IS_MOUNTED_FILE ] ; then
	rm -f $IS_MOUNTED_FILE
fi
if [ -f $TO_MOUNT_FILE ] ; then
	rm -f $TO_MOUNT_FILE
fi

# On récupère les infos, en fonction de l'OS
case $OS in
	Linux)
		#Ce qui doit être monté
		awk '$0 !~ /^#|noauto/ && $3 ~ "'$TYPE_FS'" {print $2}' /etc/fstab | sed "s/\(.\)\/$/\1/g" | sort > $TO_MOUNT_FILE
		#Si auto montage nas
		if [ -s /etc/auto.nas ] ; then
			montage_nas /etc/auto.nas
		fi
		
		#Ce qui est vraiment monté
		#df -Pk 2>/dev/null | grep -v "Mounted on" | awk '{print $6}' | sort > $IS_MOUNTED_FILE &
		#On modifie légèrement TYPE_FS pour le awk
		AWK_TYPE_FS="`echo "type $TYPE_FS " | sed "s:|: |type :g"`"
		mount | awk '$5=/'"${AWK_TYPE_FS}"'/ {print $3}'| sort > $IS_MOUNTED_FILE &
		PID="$!"
		wait_or_kill $PID 10 "mount"
	;;
	SunOS)
		#Ce qui doit être monté
		awk '$0!~'"/^#/"' && $4~'/"$TYPE_FS"/' && $6=="yes" {print $3}' /etc/vfstab | sed "s/\(.\)\/$/\1/g" | sort > $TO_MOUNT_FILE
		#Si auto montage nas
		if [ -s /etc/auto_nas ] ; then
			montage_nas /etc/auto_nas
		fi
		
		#Ce qui est vraiment monté
		#df -k 2>/dev/null | grep -v "Mounted on" | awk '{print $6}' | sort > $IS_MOUNTED_FILE &
		mount | awk '{print $1}'| sort > $IS_MOUNTED_FILE &
		PID="$!"
		wait_or_kill $PID 10 "mount"
	;;
	*)
		echo "$OS n'est pas pris en charge par cette surveillance"
		exit 3
	;;
esac
	
# On ajoute les éventuels FS supplémentaires à checker sur ce serveur (ex: montages DRBD n'apparaissent pas dans /etc/fstab)
cat $TO_MOUNT_FILE ${CHK_FILE_BY_HOST} 2>/dev/null | grep -v "^#" | sort -u > $tmpfile
cp $tmpfile $TO_MOUNT_FILE

# On retire les éventuels FS qu'on ne doit surveiller sur aucun serveur(ex: montages NAS non permanents)
if [ -s ${NOCHK_FILE} ] ; then
	diff $TO_MOUNT_FILE ${NOCHK_FILE} | grep '^<' | awk '{print $2}' > $tmpfile
	cp $tmpfile $TO_MOUNT_FILE
fi

# On retire les éventuels FS qu'on ne doit pas surveiller spécifiquement sur ce serveur
if [ -s ${NOCHK_FILE_BY_HOST} ] ; then
	diff $TO_MOUNT_FILE ${NOCHK_FILE_BY_HOST} | grep '^<' | awk '{print $2}' > $tmpfile
	cp $tmpfile $TO_MOUNT_FILE
fi

# On compare ce qui est monté et ce qui devrait l'être
result="`diff $IS_MOUNTED_FILE $TO_MOUNT_FILE 2>/dev/null | grep '^>' | awk '{print $2","}'`"

if [ -n "$result" ] ; then
	echo "MOUNTKO=`echo $result|sed 's/, /,/g'|sed 's/,$//g'`|hostname=$HOST"
	# CRITICAL
	RC=2
else
	echo "Mount OK|hostname=$HOST"
	RC=0
fi

exit $RC


