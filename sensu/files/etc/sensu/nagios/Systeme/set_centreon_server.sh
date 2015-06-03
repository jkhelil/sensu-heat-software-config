#!/bin/sh
# Script permettant de mettre � jour le flag centreon_server
# pour indiquer au script shut_boot � quel serveur Centreon
# l'agent NSCA doit envoyer les �v�nements
################################################################
# Param�tres en entr�e:
# 	set_centreon_server.sh <nom_serveur_centreon>
# Sortie:
#	Message d'information et code retour 0 si tout va bien
#	Message d'erreur et WARNING si probl�me
################################################################
# 19 Avril 2012	(SBO)	: Cr�ation
################################################################

path_flag="/HOME/uxwadm/conf/nagios"
flag="centreon_server"
liste_serveurs="^imola$|^grado$|^dourges$" # sous forme de regexp

#Seuils Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

#Params
serveur_centreon=$1

#V�rifications
if [ `echo $serveur_centreon | awk 'BEGIN { ok=0 } $1 ~ "'$liste_serveurs'" { ok=1 } END {print ok}'` -eq 0 ] ; then
	echo "Serveur Centreon $serveur_centreon inconnu." | sed "s/  / /g"
	exit $UNKNOWN
fi

if [ ! -w $path_flag/$flag ] ; then
	echo "Probleme de droits sur $path_flag/$flag ."
	exit $UNKNOWN
fi

#V�rif ok => on peut mettre � jour le flag
echo $serveur_centreon > $path_flag/$flag

echo "$flag=`head -1 $path_flag/$flag`"
exit $OK