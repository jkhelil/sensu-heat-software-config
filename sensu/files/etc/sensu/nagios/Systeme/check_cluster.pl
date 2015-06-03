#! /usr/bin/perl -w
###########################################################################
# Vérification des services manager
# + Check etat des noeuds
# + Check etat des services
# + Check des IP
###########################################################################
# usage : ./check_cluster.pl
# retour au format NAGIOS : <liste des services en erreur>
#
# Check du cluster manager			-> KO=CMAN
# Check du statut "quorate"			-> KO=QUORUM
# Check du quorum disk				-> ERR=QDISK
# Check si le noeud est "Online"		-> KO=NODE
# Check du ressourge group manager		-> WARN=RGMANAGER
# Check de l'IP de chaque service		-> KO=service(ip)
# Check si chaque service est != "failed"	-> KO=service
#
# 01/04/11 (JCU):       Version initiale
# 15/09/11 (JCU):	Correction de bugs
# 29/02/12 (JCU):	Correction détection rgmanager
# 25/04/12 (JCU):	Output du clustat pour les DBA
# 02/10/14 (JCU);	Fix bugs, don't check qdisk if vm quorum as third node
#
###########################################################################

require 5.004;
use strict;
use lib qw(/HOME/nrpe/product/current/libexec); 
use utils qw($TIMEOUT %ERRORS &print_revision &support &usage);

sub cleanup($$);
sub append_msg($$$);

my $PROGNAME = "check_cluster";
my $uname = `/bin/uname -a`;
my $crit_msg="";
my $warn_msg="";
my $services_ko="";
my $clustat;

if ( $uname =~ /Linux/ ) {
	$clustat = "/usr/sbin/clustat";
} else {
	 cleanup("UNKNOWN", "OS not supported");
}

if ( ! -e $clustat) {
    cleanup("UNKNOWN", "$clustat not found");
} elsif ( ! -x $clustat) {
    cleanup("UNKNOWN", "$clustat not executable");
}

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
    cleanup("UNKNOWN", "clustat timed out");
};
alarm($TIMEOUT);

my $wdir = "/tmp";
my $hostname = `hostname`;
chomp($hostname);
my $hostpriv = $hostname . "-priv";
my $output = `sudo $clustat -x`;
my $retval = $?;

# Turn off alarm
alarm(0);

if ($output =~ /cman is not running/) {
    cleanup("CRITICAL", "KO=CMAN");
} else {
    `sudo $clustat > $wdir/cluster_status`;
    my $status = `sudo $clustat | grep "Member Status" | cut -d":" -f2`;

    # check quorum
    if ($status !~ /Quorate/) {
        cleanup("CRITICAL", "KO=QUORUM");
    }

    # check quorum disk
    $status = `sudo $clustat | grep "Quorum Disk" | wc -l`;
    if ($status > 0) {
    	$status = `sudo $clustat | grep "Quorum Disk" | grep "Online" | wc -l`;
    	if ($status < 1) {
		$crit_msg = append_msg("ERR", $crit_msg, "QDISK");
    	}
    }

    # check nodes
    $status = `sudo $clustat -m $hostpriv| grep "Online" | wc -l`;
    if ($status < 1) {
	cleanup("CRITICAL", "KO=NODE");
    } else {
	# Just in case of problems, let's not hang Nagios
	$SIG{'ALRM'} = sub {
		cleanup("UNKNOWN", "rgmanager timed out");
	};
	alarm($TIMEOUT);
	$status = `sudo /sbin/service rgmanager status`;
        # Turn off alarm
        alarm(0);
	if ($status !~ /is running/) {
		$warn_msg = append_msg("WARN", $warn_msg, "RGMANAGER");
	}
    }

    # check services
    $status = `sudo $clustat | grep $hostpriv | grep "service" | wc -l`;
    if ( $status == 0 ) {
	if ($crit_msg ne "" || $warn_msg ne "") {
		if ($crit_msg eq "") {
			cleanup("WARNING", "$warn_msg");
		} else {
			cleanup("CRITICAL", "$crit_msg $warn_msg");
		}
	} else {
		if ($hostname =~ /vmquorum/) {
			cleanup("OK", "VM Quorum");
		} else {
			cleanup("OK", "Noeud Passif");
		}
	}
    } else {
	my $services_ko="";
	$status = `sudo $clustat | egrep "$hostpriv|none" | grep "service" > /tmp/$hostname.clustat`;
	open FILE, "< /tmp/$hostname.clustat";
	while (<FILE>) {
		my $ligne = `echo "$_" | tr -s " "`;
		my @elems = split(/ /, $ligne);
		my @service = split(/:/, $elems[1]);
		my $ip = `host $service[1] | cut -d" " -f4`;
		chomp($ip);
		$status = `/sbin/ip addr list bond0 | grep $ip | wc -l`;
		if ( $status < 1 ) {
			$services_ko = append_msg("KO", $services_ko, "$service[1](${ip})");
		} else {
		        if ( $elems[3] =~ /failed/ || $elems[3] =~ /recoverable/) {
                        	$services_ko = append_msg("KO", $services_ko, $service[1]);
			}
                }
	}
	close(FILE);
	
	if ($services_ko ne "") {
		cleanup("CRITICAL", $services_ko);
	}
    }

    # check return value
    if ($retval) {
        cleanup("UNKNOWN",
                "Cluster appeared to be OK, but clustat returned $retval");
    }
}

if ($crit_msg ne "" || $warn_msg ne "") {
	if ($crit_msg eq "") {
        	cleanup("WARNING", "$warn_msg");
        } else {
                cleanup("CRITICAL", "$crit_msg $warn_msg");
        }
} else {
        #cleanup("OK", "Noeud Passif");
	cleanup("OK", "Cluster OK");
}
#cleanup("OK", "Cluster OK");

##############################
#   Subroutines start here   #
##############################
sub cleanup ($$) {
    my ($state, $answer) = @_;
    print "$answer\n";
    exit $ERRORS{$state};
}

sub append_msg ($$$) {
    my ($severity, $msg, $append)= @_;
    if ($msg eq "") {
	$msg=$severity . "=" . $append;
    } else {
	$msg=$msg . "," . $append;
    }
    return $msg;
}
