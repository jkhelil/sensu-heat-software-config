#!/bin/bash
#############################################################################
#############################################################################
# Check générique d'un processus sur serveur distant
#############################################################################
# Script lancé par NAGIOS pour vérifier qu'un processus est bien opérationnel
# Le check peut être réalisé à plusieurs niveaux sur le processus:
# - sur le nom du processus
# - sur l'utilisateur qui exécute le processus
# - sur l'IP d'écoute du processus
# - sur le port d'écoute du processus
#
#############################################################################
# Usage: ./check_processus.sh -n $proc_name [-u $user] [-h $ipaddress] [-p $port]
#############################################################################
# 17/11/09 (JCU) : Version initiale
# 07/01/10 (JCU) : Adapation pour compatibilité Solaris
# 26/04/10 (MGK) : Ajout taille mÃmoire processus
# 27/02/12 (SBO) : Ajout "mega ps SunOS" si dispo (pour WAS Euronet par ex)
# 08/11/12 (JCU) : Modification de la detection du user dans le ps 
# 27/12/13 (SBO) : Ajout check_service pour Linux si ip:port (évite le netstat)
#############################################################################

#############################################################################
# FONCTIONS
#############################################################################
print_usage() {
	PROGNAME=`basename $0`
        echo "Usage: $PROGNAME -n proc_name [-u <user>] [-h <ipaddress>] [-p <port>] [-m]"
}

function wait_or_kill {
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
		return 3
	else
		return 0
	fi
}

function check_service {
	echo -n > /dev/tcp/$1/$2 2>/dev/null &
	PID="$!"
	wait_or_kill $PID 5
	if [ $? -eq 0 ] ; then
		#la commande rend bien la main en moins de 5s, on l'execute de nouveau, pour en connaitre le RC réel
		echo -n > /dev/tcp/$1/$2 2>/dev/null
		return $?
	else
		return 3
	fi
}

#############################################################################
# USAGE
#############################################################################
# cas d erreur : mauvais nombre d argument
if [ $# -lt 1 ]; then
	print_usage
        exit 3
fi

#############################################################################
# INITIALISATION
#############################################################################

# Récupère les paramètres
while getopts "N:n:u:h:p:m" OPT; do
	case $OPT in
		"n") procname=$OPTARG;;
		"u") user=$OPTARG;;
		"h") host=$OPTARG;;
		"p") port=$OPTARG;;
		"m") size=0;;
		"N") NETSTAT="$OPTARG";;
	esac
done

# Il faut au moins le nom du processus 
if [ "$procname" == "" ]; then
        print_usage
        exit 3
fi

PROGNAME=`basename $0`
OS=`uname`

OS=`uname`
PS_ALL="ps -ef "
if [ "$OS" == "SunOS" ] ; then
	if [ `hostname | grep -c uvsctu | awk '{print $1}'` -eq 0 ] ; then
		#Est-ce qu'on a le sudo pour le ps "de la mort" ? => utilisé pour WAS Euronet  ---- SAUF POUR LES TUXEDO
		dummytest=`/usr/local/bin/sudo /usr/ucb/ps auxwww 2>/dev/null`
		if [ $? -eq 0 ] ; then
			PS_ALL="/usr/local/bin/sudo /usr/ucb/ps auxwww "
		fi
	fi
fi

# Si un user est défini, on fait un PS sur le nom du processus et
# l'utilisateur qui l'exécute. Sinon uniquement sur le nom
if [ "$user" != "" ]; then
	case $OS in
		SunOS) 	nbproc=`$PS_ALL | grep -w "$user" | egrep "$procname" | grep -v $PROGNAME | grep -v grep | wc -l`;;
		Linux) 	nbproc=`ps -fu $user | egrep -w "$procname" | grep -v $PROGNAME | grep -v grep | wc -l`;;
	esac

	if [ $size ] ; then
		case $OS in
			Linux) size=`ps ax -o size,cmd -u $user | perl -ne "BEGIN { my \\$size = 0 } next if \\$_ !~ m/$procname/ ; /^\s*(\d+).*?$/ ; \\$size += \\$1 ; END { printf '%skb', \\$size }"`
		esac
	fi
else
	nbproc=`$PS_ALL | egrep "$procname" | grep -v $PROGNAME | grep -v grep | wc -l`

	if [ $size ] ; then
		case $OS in
			Linux) size=`ps ax -o size,cmd -C $procname | perl -ne "BEGIN { my \\$size = 0 } next if \\$_ !~ m/$procname/ ; /^\s*(\d+).*?$/ ; \\$size += \\$1 ; END { printf '%skb', \\$size }"`
		esac
	fi
fi

listen=""

# Si un host et un port sont définis, on fait un NETSTAT sur ip:port 
# Sinon uniquement sur l'ip
if [ "$host" != "" ]; then
	host=`echo $host| sed 's/\\./\\\./g'`
	if [ "$port" != "" ]; then
		case $OS in
				SunOS)
					if [ "$NETSTAT" == "" ] ; then
						NETSTAT="`netstat -an`"
					fi
					listen=`echo "$NETSTAT" | grep LISTEN | awk '{ print $1 }' | grep "$host.$port" | wc -l|tr -d " "`
					;; 
				Linux) #listen=`netstat -an | grep LISTEN | awk '{ print $4 }' | grep "$host:$port" | wc -l|tr -d " "`;;
				#on déprotège pour ce cas-ci :-D
				host=`echo $host| sed 's/\\\./\./g'`
				if ! check_service "$host" $port ; then
					listen=0
				else
					listen=1
				fi
				;;
		esac
	else
		case $OS in
			SunOS)
					if [ "$NETSTAT" == "" ] ; then
						NETSTAT="`netstat -an`"
					fi
					listen=`echo "$NETSTAT" | grep LISTEN | awk '{ print $1 }' | grep "$host" | wc -l|tr -d " "`
					;;
			Linux)
					if [ "$NETSTAT" == "" ] ; then
						NETSTAT="`netstat -an`"
					fi
					listen=`echo "$NETSTAT" | grep LISTEN | awk '{ print $4 }' | grep "$host" | wc -l|tr -d " "`
					;;
		esac
	fi
fi

# Si uniquement un port est défini, on fait un NETSTAT sur le port
if [ "$port" != "" ] && [ "$host" == "" ]; then
	case $OS in
	        SunOS)
					if [ "$NETSTAT" == "" ] ; then
						NETSTAT="`netstat -an`"
					fi
					listen=`echo "$NETSTAT" | grep LISTEN | awk '{ print $1 }' | grep "$port" | wc -l|tr -d " "`
					;;
			Linux) 
					if [ "$NETSTAT" == "" ] ; then
						NETSTAT="`netstat -an`"
					fi
					listen=`echo "$NETSTAT" | grep LISTEN | awk '{ print $4 }' | grep "$port" | wc -l|tr -d " "`
					;;
        esac
fi

# Si aucun check NETSTAT n'a été fait, il faut juste
# que le nombre de processus actifs soit > 1
if [ "$listen" == "" ]; then
	if [ $nbproc -ge 1 ]; then
		if [[ $size =~ "kb" ]] ; then
			echo "OK|memory=$size"
		else
			echo "OK"
		fi

		exit 0
	else
		echo "KO"
		exit 2
	fi

# Si des checks NETSTAT ont été faits, il faut que le
# nombre de processus actifs soit > 1 ET que le nombre
# de processus en écoute soit aussi > 1
else
	if [ $nbproc -ge 1 ]&&[ $listen -ge 1 ]; then
                echo "OK"
                exit 0
        else
                echo "KO"
                exit 2
        fi
fi
