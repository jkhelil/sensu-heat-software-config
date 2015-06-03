#! /bin/bash
############################################################################
############################################################################
# Verification du service keepalived :
#       + presence du processus keepalived
#       + affichage du nombre d'ip montees
############################################################################
#
# Note : N.A.
#
############################################################################
# usage : check_keepalived.sh
# retour au format NAGIOS :
#		OUTPUT : etat | perfdata
#		CODE EXIT : code erreur
#			code erreur :
#			0 -> OK
#			1 -> Warning
#			2 -> Critical
#			3 -> Unkown (autre)
#############################################################################
#############################################################################

#############################################################################
# INITIALISATION
#############################################################################
HOSTNAME=`hostname|tr [a-z] [A-Z]`
home="/HOME/kadadm"
home_config=/etc/sensu/nagios/CFG
logfile="/HOME/kadadm/logs/keepalived.log"

# Vérification de la présence du fichier de configuration
if [ ! -f $home_config/keepalived.cfg ] ; then
        echo "KAD 3: Fichier $home_config/keepalived.cfg inexistant"
        exit 3
fi

# Repertoire de travail
wdir=$home/scripts/nagios/data

# Si le répertoire de travail de Nagios n'existe pas, on le crée avec les droits en écriture pour tout le monde
if [ ! -d $wdir ]; then
	mkdir $wdir 2>/dev/null
	if [ $? -ne 0 ]; then
		   echo "KAD 3 : probleme de droits sur $home/scripts/nagios"
		   exit 3
	fi
	chmod a+rw $wdir
elif [ ! -w $wdir ]; then
   echo "KAD 3 : probleme de droits d'écriture sur $wdir"
   exit 3
fi

#############################################################################
# FONCTIONS
#############################################################################

#############################################################################
# TRAITEMENT
#############################################################################
if [  -f $wdir/keepalived.nocheck ]; then
	echo "Service désactivé (Nocheck)"
	exit 0
fi	

# Etat du processus
ps -C keepalived 2>&1 >/dev/null

if [[ $? -ne 0 ]] ; then
	echo "PROCS=keepalived"
	exit 2
fi

# Purge des fichiers de logs
if [  -f $wdir/keepalived.err ]; then
	rm $wdir/keepalived.err
fi	
if [  -f $wdir/keepalived.warn ]; then
	rm $wdir/keepalived.warn
fi

# traitement du fichier de log keepalived.log si présent
if [ -f $logfile ] ; then
	#Chargement du fichier de conf
	. $home_config/keepalived.cfg		

	# seek=curseur sur logfile
	# Recuperation de la taille du fichier keepalived.log
	eof=`ls -lL $logfile|sed -e 's/\  */./g'|cut -d. -f5`

	# S il existe un curseur courant on le recupere, sinon on met
	# le curseur à 0 pour parcourir keepalived.log du debut
	if [ -f $wdir/keepalived.seek ]; then
		seek=`cat $wdir/keepalived.seek`
	else
		seek=0
	fi
	# si le curseur est plus grand que la taille du fichier keepalived.log : il y a eu rotation du fichier keepalived.log
	# on met le curseur a 0 pour lire le fichier keepalived.log du debut
	if [ $seek -gt $eof ]; then
		seek=0
	fi

	# Recherche des messages d erreurs
	# Dans keepalived.log
	if [ "x$messerr" != "x" ] ; then
		#On doit scruter les logs, on vérifie qu'on peut les lire!
		if [ ! -r $logfile ]; then
			echo "KAD 3 : $logfile non lisible."
			exit 3
		fi
		if [ "x$nomesserr" != "x" ] ; then
			tail -c +${seek} $logfile|egrep "$messerr"|egrep -v "${nomesserr}"|perl -ne '$_ =~ /(Keepalived_vrrp.*)$/ ; print $1."\n"' > $wdir/keepalived.err
		else
			tail -c +${seek} $logfile|egrep "$messerr"|perl -ne '$_ =~ /(Keepalived_vrrp.*)$/ ; print $1."\n"' > $wdir/keepalived.err
		fi
	fi

	# Messages warnings a remonter dans keepalived.cfg (cf commande source plus haut)
	# messwar : warnings a remonter
	# messwar_ : warnings a ne pas remonter
	if [ "x$messwar" != "x" ] ; then
		#On doit scruter les logs, on vérifie qu'on peut les lire!
		if [ ! -r $logfile ]; then
			echo "KAD 3 : $logfile non lisible."
			exit 3
		fi
		if [ "x$nomesswar" != "x" ] ; then
			tail -c +${seek} $logfile|egrep "$messwar"|egrep -v "${nomesswar}"|perl -ne '$_ =~ /(Keepalived_vrrp.*)$/ ; print $1."\n"' > $wdir/keepalived.warn
		else
			tail -c +${seek} $logfile|egrep "$messwar"|perl -ne '$_ =~ /(Keepalived_vrrp.*)$/ ; print $1."\n"' > $wdir/keepalived.warn
		fi
	fi

	# Mise a jour du curseur pour keepalived.log
	echo $eof > $wdir/keepalived.seek
fi

RC=0
message=""
num_err=0
num_war=0
if [ -s $wdir/keepalived.warn ] ; then
	message="WARN=`echo $(cat $wdir/keepalived.warn | awk '{print $2","}' | sort -u) | sed "s/, /,/g" | sed "s/,$//g"| sed "s/ /_/g"`"
	num_war=`wc -l $wdir/keepalived.warn 2>/dev/null | awk '{print $1}'`
	RC=1
fi
if [ -s $wdir/keepalived.err ] ; then
	if [ "x$message" == "x" ] ; then
		message="ERR="
	else
		message="$message ERR="
	fi
	message="${message}`echo $(cat $wdir/keepalived.err | awk '{print $2","}' | sort -u) | sed "s/, /,/g" | sed "s/,$//g"| sed "s/ /_/g"`"
	num_err=`wc -l $wdir/keepalived.err 2>/dev/null | awk '{print $1}'`
	RC=2
fi

if [ "x$message" == "x" ] ; then
	message="Service OK"
fi

# Nombre d'adresses sur le bonding
nombre_ip=`/sbin/ip -4 addr show dev bond0 | grep -v brd | grep inet | wc -l`

echo "${message}|hostname=$HOSTNAME;adresses_flottantes=$nombre_ip;num_err=$num_err;num_war=$num_war"
exit $RC

