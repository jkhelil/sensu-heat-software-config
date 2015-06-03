#! /usr/bin/perl -w
# sync::
# tsync::
############################################################################
############################################################################
# Verification du service RedHat Cluster :
#       + 
#       + 
############################################################################
#
# Note : N.A.
#
############################################################################
# usage : check_rhcluster.pl
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

use strict;
use warnings;

use lib '/HOME/uxwadm/scripts';
use lib '/etc/sensu/nagios/HAProxy/wip';

require ToolBox;

my $rhcluster_mib = "REDHAT-CLUSTER-MIB::RedHatCluster";

#############################################################################
# FONCTIONS
#############################################################################

#
# usage
#
# Donne la page d'utilisation du check
#
sub	usage {
}

#
# get_walk
#
# Retourne une table de hashage de l'etat du cluster
#
# @in	: undef
# @out	: hash
#
sub	get_walk {
}


#############################################################################
# TRAITEMENT
#############################################################################

