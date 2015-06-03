#!/usr/bin/perl
# Metrologie de l'etat des connexions TCP
# 12/07/2011 (SBO) : Creation (version express)
# 13/07/2011 (SBO) : Amelioration code + ajout gestion seuils
# 08/03/2012 (ADH) : Reecriture en perl
# 08/03/2012 (SBO) : Qq corrections de mauvais copier/coller ;) (param/seuils) 
# 27/03/2012 (SBO) : Ajout option filtre sur liste de ports/ip
# 27/03/2012 (SBO) : Ajout possibilite de preciser les etats a remonter (pour reduire la liste)

use strict;
use vars qw/ %opt /;
use Sys::Hostname;

my ($established_treshold,$closewait_treshold,$listen_treshold,$timewait_treshold);
my ($result,$retour,$flag_state,%count);
my $perfdata = "hostname=".lc(hostname).";";

#Filtre optionnel
my $optional_filters;

my $states_to_trap="NONE ESTABLISHED SYN_SENT SYN_RECV SYN_RCVD FIN_WAIT TIME_WAIT CLOSE CLOSE_WAIT LAST_ACK LISTEN";

use Getopt::Std;
my $opt_string = 'e:c:l:t:f:s:';
getopts( "$opt_string", \%opt );

if ($opt{e}) {$established_treshold=$opt{e}};
if ($opt{c}) {$closewait_treshold=$opt{c}};
if ($opt{l}) {$listen_treshold=$opt{l}};
if ($opt{t}) {$timewait_treshold=$opt{t}};
if ($opt{f}) {$optional_filters=$opt{f}};
if ($opt{s}) {
	$states_to_trap=$opt{s};
	$states_to_trap =~ s:,: :g;
}

no warnings 'exec';
my $netstat;
my $netstat_param="-n";
#Attention si on demande les cnx en LISTEN il faut le -a
if ( $states_to_trap =~ /LISTEN/ ) {
	$netstat_param="-an";
}
unless (open $netstat, "-|", "netstat", $netstat_param)
  { $retour="Aucune connexion trouvee";
    $flag_state=3;
    #die "$0: cannot start netstat: $!";
  }

#Est-ce qu'on a precise un filtre?
my $filter = "";
if ($optional_filters) {
	#On met le resultat dans un tableau pour pouvoir le parcourir plusieurs fois
	my @netstat;
	while (<$netstat>) {
		push @netstat, $_; 
	}
	#On prepare une nouvelle liste d'etats par filtre
	my $states_tmp = "";
	my $new_states = "";
	my @array_states = split(/ /,$states_to_trap);
	#On va boucler sur chaque filtre
	foreach (split(/,/,$optional_filters)) {
		$filter = $_ ;
		foreach (@netstat) {
		  next if ( ! m/$filter/ );
		  my @f = split;
		  if ($states_to_trap =~ /\Q$f[$#f]\E/) {
		  $result .= " ".$f[$#f]."_".$filter;}
		}
		#Astuce pour le comptage qui suit
		$new_states = join(" ",  map "$_\_$filter", @array_states);
		$states_tmp .= $new_states." ";
	}
	$states_to_trap = $states_tmp ;
}
else {
	# On parse tout le netstat
	while (<$netstat>) {
	  my @f = split;
	  if ($states_to_trap =~ /\Q$f[$#f]\E/) {
	  $result .= " ".$f[$#f];}
	}
}

#On compte chaque etat trouve
for (split(/ /,$result)){$count{$_}++;}

foreach (split(/ /,$states_to_trap)) {
        if (!defined $count{$_}) {
                $perfdata .= lc($_)."=0;";
        } else {
                $perfdata .= lc($_)."=".$count{$_}.";";
        }
}

#Est-ce qu'on a depasse un seuil?
#par filtre?
if ($optional_filters) {
	my $max_flag=0;
	#On va boucler sur chaque filtre
	my ($ESTABLISHED_filter, $LISTEN_filter, $TIME_WAIT_filter, $CLOSE_WAIT_filter);
	my ($ESTABLISHED_retour, $LISTEN_retour, $TIME_WAIT_retour, $CLOSE_WAIT_retour);
	
	foreach (split(/,/,$optional_filters)) {
		$filter = $_ ;
		$ESTABLISHED_filter = "ESTABLISHED_".$filter;
		if ($established_treshold && $count{$ESTABLISHED_filter} > $established_treshold) { 
			if ($ESTABLISHED_retour) {
				$ESTABLISHED_retour .= ",".$filter."_($count{$ESTABLISHED_filter})"; 
			} else {
				$ESTABLISHED_retour = "ESTABLISHED=".$filter."_($count{$ESTABLISHED_filter})"; 
			}
			$flag_state=1 ;
		}
		
		$LISTEN_filter = "LISTEN_".$filter;
		if ($listen_treshold && $count{$LISTEN_filter} > $listen_treshold) { 
			if ($LISTEN_retour) {
				$LISTEN_retour .= ",".$filter."_($count{$LISTEN_filter})"; 
			} else {
				$LISTEN_retour = "LISTEN=".$filter."_($count{$LISTEN_filter})"; 
			}
			$flag_state=1 ;
		}
		
		$TIME_WAIT_filter = "TIME_WAIT_".$filter;
		if ($timewait_treshold && $count{$TIME_WAIT_filter} > $timewait_treshold) { 
			if ($TIME_WAIT_retour) {
				$TIME_WAIT_retour .= ",".$filter."_($count{$TIME_WAIT_filter})"; 
			} else {
				$TIME_WAIT_retour = "TIME_WAIT=".$filter."_($count{$TIME_WAIT_filter})"; 
			}
			$flag_state=1 ;
		}
		
		$CLOSE_WAIT_filter = "CLOSE_WAIT_".$filter;
		if ($closewait_treshold && $count{$CLOSE_WAIT_filter} > $closewait_treshold) { 
			if ($CLOSE_WAIT_retour) {
				$CLOSE_WAIT_retour .= ",".$filter."_($count{$CLOSE_WAIT_filter})"; 
			} else {
				$CLOSE_WAIT_retour = "CLOSE_WAIT=".$filter."_($count{$CLOSE_WAIT_filter})"; 
			}
			$flag_state=2 ;
		}
		
		if ( $flag_state > $max_flag ) { $max_flag=$flag_state ; }
	}
	
	# On synthetise la sortie et prend la criticite max
	$flag_state=$max_flag;
	if ($ESTABLISHED_retour) { $retour .= $ESTABLISHED_retour." " ;}
	if ($LISTEN_retour) { $retour .= $LISTEN_retour." " ;}
	if ($TIME_WAIT_retour) { $retour .= $TIME_WAIT_retour." " ;}
	if ($CLOSE_WAIT_retour) { $retour .= $CLOSE_WAIT_retour." " ;}
}
#ou global?
else {
	if ($established_treshold) { if ($count{ESTABLISHED} > $established_treshold) { $retour .= "ESTABLISHED=$count{ESTABLISHED} "; $flag_state=1 ;} }
	if ($listen_treshold) { if ($count{LISTEN} > $listen_treshold) { $retour .= "LISTEN=$count{LISTEN} "; $flag_state=1 ;} }
	if ($timewait_treshold) { if ($count{TIME_WAIT} > $timewait_treshold) { $retour .= "TIME_WAIT=$count{TIME_WAIT} "; $flag_state=1 ;} }
	if ($closewait_treshold) { if ($count{CLOSE_WAIT} > $closewait_treshold) { $retour .= "CLOSE_WAIT=$count{CLOSE_WAIT} "; $flag_state=2 ;} }
}
if (!defined $retour) { $retour="Analyse des connexions TCP OK" ; $flag_state=0 ;}

$perfdata =~ s/.$//;
print "$retour|$perfdata";
exit $flag_state;
