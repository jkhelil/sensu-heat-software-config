#!/usr/bin/perl
############################################################################
# Verification des interfaces réseau :
#       Récupère les statistiques in/out de chaque interface pour
#		déterminer si celle-ci est saturée ou arrive à saturation
#		+ Ping de la gateway
############################################################################
#
# Note : 
#	01/04/2011 (SBO) Ajout du test ping gateway
#
############################################################################
# usage : check_netiface.pl <%saturation>
# retour au format NAGIOS :
#       OUTPUT : liste des interfaces en erreur | perfdata
#       CODE EXIT : code erreur
#       code erreur :   0 -> OK
#                       1 -> Warning
#                       2 -> Critical
#                       3 -> Unkown (autre)
#
#############################################################################
#############################################################################

#############################################################################
# INITIALISATION
#############################################################################

use strict;

my $bits = 8;
my $hostname = `hostname|tr [a-z] [A-Z]`;
chomp($hostname);
my $perfdata = "hostname=${hostname};";
my $ifaces_crit = "";
my $ifaces_warn = "";

# On vérifie le nombre de paramètres passés au script
# my $taille_argv	= scalar @ARGV;
# if ($taille_argv ne 0) {
	# print "Network 3 : mauvais format d'appel de $0 (invocation : $0 @ARGV)";
	# exit 3; 
# }

#On paramètre les différences entre OS
my $os_version=`uname`;
my $interfaces;
#pour récupérer la liste des interfaces réseau
if ($os_version =~ /Linux/) {
	$interfaces = `cat /proc/net/dev`;
}
elsif ($os_version =~ /SunOS/) {
	$interfaces = `kstat -p -m e1000g -s '*bytes' -n 'mac';kstat -p -m bnx -s '*bytes' -n 'mac'`;
}
else {
	print "OS not supported by this check";
	exit 3;
}	

$ENV{LC_ALL}="C";

###############################################################################
# TRAITEMENT
###############################################################################


#Heure de passage du script
my $actual_time = time ;
chomp($interfaces);
#Pour chaque interface eth ou bond, on va récupérer ses statistiques
foreach (split(/\n/, $interfaces)) {
	next if ( ! m/^\s*(bond|eth|e1000g:|bnx:)[0-9]*:/);
	#On est sur une ligne correspondant à des stats d'une interface à surveiller, on réinitialise les compteurs
	my ($interface, $ibytes, $obytes, $last_ibytes, $last_obytes, $ibytes_mb, $obytes_mb, $last_ibytes_time, $last_obytes_time);
	if ($os_version =~ /Linux/) {
		~ / *(.*):(\s.*?|.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+/;
		$interface=$1;
		$ibytes=$2;
		$obytes=$10;
	}
	elsif ($os_version =~ /SunOS/) {
		~ /(.*:\d+):mac:(\w+)\s+(\d+)/;
		$interface=$1;
		my $which_bytes=$2;
		my $value=$3;
		if ( $which_bytes =~ m/^rbytes$/ ) {
				$ibytes=$value;
		}
		elsif ( $which_bytes =~ m/^obytes$/ ) {
				$obytes=$value;
		}
		undef $which_bytes, $value;
	}
	#Astuce permettant de tester l'état d'une interface bond
	my $mii_status;
	my $nbslaves;
	my $mii_status_slaves;
	if ( -f "/proc/net/bonding/${interface}" ) {
		$mii_status=`egrep "MII Status" /proc/net/bonding/${interface} | head -1 | egrep -v "up"`;
		$nbslaves=`egrep "MII Status" /proc/net/bonding/${interface} | wc -l`;
		$nbslaves=$nbslaves - 1;
		$mii_status_slaves=`egrep "MII Status" /proc/net/bonding/${interface} | tail -${nbslaves} | egrep -v "up"`;

	}
	elsif ( -f "/proc/net/bonding/p${interface}" ) {
		$mii_status=`cat /proc/net/bonding/p${interface} | egrep "MII Status" | head -1 | egrep -v "up"`;
		$nbslaves=`egrep "MII Status" /proc/net/bonding/p${interface} | wc -l`;
		$nbslaves=$nbslaves - 1;
		$mii_status_slaves=`egrep "MII Status" /proc/net/bonding/p${interface} | tail -${nbslaves} | egrep -v "up"`;
	}
	else {
		undef $mii_status;
		undef $mii_status_slaves;
		undef $nbslaves;
	}
	if ( $mii_status ne "" ) {
		if ($ifaces_crit eq "") {
			$ifaces_crit="CRIT=${interface}_MII_Status_Error";
		}	
		else {
			$ifaces_crit="${ifaces_crit},${interface}_MII_Status_Error";
		}
	}
	if ( $mii_status_slaves ne "" ) {
		if ($ifaces_warn eq "") {
			$ifaces_warn="WARN=${interface}_MII_Slave_Status_Error";
		}	
		else {
			$ifaces_warn="${ifaces_warn},${interface}_MII_Slave_Status_Error";
		}
	}
	# IN
	if ( defined $ibytes ) {
		#On récupère les stats précédents si elles existent, sinon 0
		if ( -f "/tmp/${interface}_traffic_in.txt" ) {
			my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("/tmp/${interface}_traffic_in.txt");
			$last_ibytes_time = $mtime;
			$last_ibytes=`cat /tmp/${interface}_traffic_in.txt`;
			chomp($last_ibytes);
		} else {
			$last_ibytes_time = 0;
			$last_ibytes = 0;
		}
		#On stocke les statistiques pour le tour suivant
		`echo $ibytes > /tmp/${interface}_traffic_in.txt`;
		
		# On calcule la moyenne rapporté à la seconde, à partir du delta si disponible
		if ( $ibytes >= $last_ibytes ) {
			$ibytes=($ibytes - $last_ibytes) / ($actual_time - $last_ibytes_time);
		} else {
			#Les stats ont été réinitialisées
			$ibytes=$ibytes / ($actual_time - $last_ibytes_time);
		}
		#On convertit en Mb
		$ibytes_mb=$ibytes * $bits;
		$ibytes_mb=sprintf "%.5f", ($ibytes_mb / 1024);
		$ibytes_mb=sprintf "%.2f", ($ibytes_mb / 1024);
		
		$perfdata="${perfdata}${interface}_in=${ibytes_mb}Mb;";
	}
	#OUT
	if ( defined $obytes ) {
		#On récupère les stats précédents si elles existent, sinon 0
		if ( -f "/tmp/${interface}_traffic_out.txt" ) {
			my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("/tmp/${interface}_traffic_out.txt");
			$last_obytes_time = $mtime;
			$last_obytes=`cat /tmp/${interface}_traffic_out.txt`;
			chomp($last_obytes);
		} else {
			$last_obytes_time = 0;
			$last_obytes = 0;
		}
		#On stocke les statistiques pour le tour suivant
		`echo $obytes > /tmp/${interface}_traffic_out.txt`;
		
		# On calcule la moyenne rapporté à la seconde, à partir du delta si disponible
		if ( $obytes >= $last_obytes ) {
			$obytes=($obytes - $last_obytes) / ($actual_time - $last_obytes_time);
		} else {
			#Les stats ont été réinitialisées
			$obytes=$obytes / ($actual_time - $last_obytes_time);
		}
		
		#On convertit en Mb
		$obytes_mb=$obytes * $bits;
		$obytes_mb=sprintf "%.5f", ($obytes_mb / 1024);
		$obytes_mb=sprintf "%.2f", ($obytes_mb / 1024);
		
		$perfdata="${perfdata}${interface}_out=${obytes_mb}Mb;";

		#Quelle est la vitesse de cette interface?
		my $vitesse;
		if ($os_version =~ /Linux/) {
			$vitesse=`dmesg | grep $interface | grep -i duplex | tail -1`;
			if ( $vitesse=~ m/^.*\s+(\d+)\s*Mb.*/ ) {
				$vitesse=$1;
			}
		}
		elsif ($os_version =~ /SunOS/) {
			$vitesse=`kstat -m e1000g -s 'ifspeed' -n 'mac' -p;kstat -m bnx -s 'ifspeed' -n 'mac' -p`;
			foreach (split(/\n/, $vitesse)) {
				next if ( ! m/^$interface:mac:ifspeed\s+(\d+)/); 
				$vitesse=$1 / 1000000;
			} 
		}
		if (defined $vitesse && $vitesse=~ m/\d+/ ) {
			#$perfdata="${perfdata}${interface}_speed=${vitesse}Mb;";
			#Le seuil en sortie est-il dépassé?
			if ($obytes_mb > $vitesse)
			{
				if ($ifaces_warn eq "") {
					$ifaces_warn="WARN=${interface}_(>${vitesse}Mb)";
				}	
				else {
					$ifaces_warn="${ifaces_warn},${interface}_(>${vitesse}Mb)";
				}
			} 
			undef $vitesse;
		}
	}
	undef $ibytes, $obytes;
}

my $code_retour=0;
my $message = "";
if ( $ifaces_warn ne "" ) {
	$message="$ifaces_warn";
	$code_retour=1;
}
if ( $ifaces_crit ne "" ) {
	$message="$message $ifaces_crit";
	$code_retour=2;
}

# Ajout du test de ping gateway, info à différents endroits selon serveur
my $ipgw;
my $gwping;
if ( -r "/etc/network/interfaces" ) {
	$ipgw=`grep gateway /etc/network/interfaces | awk '{print $2}'`;
	chomp($ipgw);
	$gwping=`ping -c 3 $ipgw 2>/dev/null 1>/dev/null; echo $?`;
	if ( $gwping != 0 ) {
		$message="$message Gateway=PINGKO($ipgw)";
		$code_retour=2;
	}
}
elsif ( -r "/etc/sysconfig/network" ) {
	$ipgw=`grep GATEWAY /etc/sysconfig/network`;
	$ipgw=~ s/GATEWAY=//g;
	chomp($ipgw);
	$gwping=`ping -c 3 $ipgw 2>/dev/null 1>/dev/null; echo $?`;
	if ( $gwping != 0 ) {
		$message="$message Gateway=PINGKO($ipgw)";
		$code_retour=2;
	}
}
elsif ( -r "/etc/defaultrouter" ) {
	$ipgw=`cat /etc/defaultrouter| egrep -v "^#"`;
	chomp($ipgw);
	if ( $ipgw eq "" ) {
		$ipgw=`netstat -rn 2>/dev/null|grep default| tr -s " " | cut -d" " -f2`;
		chomp($ipgw);
	}
	$gwping=`ping -s $ipgw 100 3 2>/dev/null 1>/dev/null; echo $?`;
	if ( $gwping != 0 ) {
		$message="$message Gateway=PINGKO($ipgw)";
		$code_retour=2;
	}
}
else {
	$ipgw=`netstat -rn 2>/dev/null|grep default| tr -s " " | cut -d" " -f2`;
	if ( $ipgw eq "" ) {
		# Cas gateway non identifiee
		$message="$message Gateway=no_gw_found";
		if ( $code_retour < 2 ) {
			$code_retour=1;
		}
	}
	else {
		chomp($ipgw);
		$gwping=`ping -s $ipgw 100 3 2>/dev/null 1>/dev/null; echo $?`;
		if ( $gwping != 0 ) {
			$message="$message Gateway=PINGKO($ipgw)";
			$code_retour=2;
		}
	}
}

# Sortie
if ( $code_retour == 0 ) {
	print "Trafic reseau normal|$perfdata";			
} else {
	$message =~ s/^ //;
	print "$message|$perfdata";
}

exit $code_retour;
