#!/bin/bash
#############################################################################
#############################################################################
# Checke si le serveur va rebooter
# Si le flag a été déposé par le script de reboot -> avertit nagios
#
#############################################################################
# Usage: check_reboot.sh
#############################################################################
# 12/05/10 (JCU): Version initiale
# 15/04/11 (JCU): Ajout d'un timeout pour supprimer le flag_shutdown
#		  en cas de problème
# 03/01/12 (SBO) : ajout test pour arbo Euronet
#############################################################################

#############################################################################
# INITIALISATION
#############################################################################
home_scripts=/usr/lib/nagios/plugins
if [ -d /appl/nrpevsc/ ] ; then
        home_flag=/appl/nrpevsc/
elif [ -d /usr/local/nagios/ ] ; then
        home_flag=/usr/local/nagios/
fi
flag_shutdown=$home_flag/SURV.flag
flag_disabled=$home_flag/SURV.disabled
timeout=3600
# Perl
PERL="/usr/bin/perl"

#############################################################################
# TRAITEMENT
#############################################################################

if [ ! -f $flag_shutdown ] && [ -f $flag_disabled ]; then
	echo "BOOT"
	rm $flag_disabled	
elif [ -f $flag_shutdown ] && [ ! -f $flag_disabled ]; then
	echo "SHUTDOWN"
	touch $flag_disabled
elif [ -f $flag_shutdown ] && [ -f $flag_disabled ]; then
	now=`$PERL -e 'print int(time)'`
	fic=`$PERL -e 'use File::stat;$sb=stat("'$flag_shutdown'");printf "%s",scalar $sb->mtime;'`
	delta=$(( now - fic ))
	if [ $delta -gt $timeout ]; then
		rm -f $flag_shutdown
	fi
	echo "DISABLED"
else
	echo "RUNNING"
fi

exit 0
