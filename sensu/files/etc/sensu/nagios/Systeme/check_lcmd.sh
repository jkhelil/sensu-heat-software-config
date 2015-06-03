#!/bin/bash
#############################################################################
#############################################################################
# Vérifie si des commandes Nagios sont en attente dans le fichier local
# Si oui, alors elles sont envoyées à Nagios
#
# Si le répertoire CMD n'existe pas, c'est ce script qui le crée car nrpevsc
# est le propriétaire du répertoire parent
#############################################################################
# Usage: check_lcmd.sh
# Out : contenu du fichier de commande local
# RC : toujours 0 (pas d'alerte, juste check)
#############################################################################
# 14/10/10 (SBO): Version initiale
# 03/01/12 (SBO): Ajout test path pour Euronet
#############################################################################

#############################################################################
# INITIALISATION
#############################################################################
# Sous-répertoire de l'agent par sécu
if [ -d /appl/nrpevsc/ ] ; then
        nrpe_dir="/appl/nrpevsc/CMD"
elif [ -d /usr/local/nagios/ ] ; then
        nrpe_dir="/usr/local/nagios/CMD"
fi
NRPE_CMD_FILE="${nrpe_dir}/LOCAL_NAGIOS_CMD"

#############################################################################
# TRAITEMENT
#############################################################################

# On vérifie que nrpe_dir est bien accessible
if [ -e $nrpe_dir ] ; then
	# On teste si le fichier "tampon" existe
	if [ -r $NRPE_CMD_FILE ] ; then
		# On affiche son contenu
		cat $NRPE_CMD_FILE
		# Puis on le vide
		cat /dev/null > $NRPE_CMD_FILE
	fi
else
	mkdir $nrpe_dir
	chmod 777 $nrpe_dir
fi

