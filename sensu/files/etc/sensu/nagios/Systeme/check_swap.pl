#!/usr/bin/perl -w
# Nagios plugin to check free swap space on Solaris/Linux
# Copy to Nagios libexec directory (requires utils.pm from Nagios plugins).
#
# $Id: check_swap.pl,v 1.2 2008/08/28 14:44:44 kivimaki Exp $
#
# Copyright (C) 2006-2008  Hannu Kivimäki / CSC - Scientific Computing Ltd.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# 
# Juillet 09: Reprise du script check_solaris_swap.pl par Hannu Kivimäki sur nagiosexchange.org
#
# 04/09/09 (JCU): Adapations pour environnement VSC et prise en compte OS Linux
# 23/06/10 (JCU): Modification des sorties pour limiter les alertes Tivoli
# 19/11/10 (JCU): Force la langue en anglais
# 27/05/14 (JCU): detection nagios plugins directory (proxmox)
#
# ------------------------------ SETTINGS --------------------------------------

use strict;
use Getopt::Long;

use vars qw($opt_h $opt_l $opt_V $opt_w $opt_c);

my ($CMD_SWAP,$SWITCH);
my ($swap_used,$swap_available,$swap_available_m,$swap_total_m,$swap_available_g,$swap_total_g,$swap_free_pct);
my ($state_text,$perf_text);
my (@swap_results);

my $os_version=`uname`;
my $pve_version=`pveversion 2>/dev/null`;

use lib "/etc/sensu/nagios/libexec/";


use utils qw(%ERRORS);

if ($os_version =~ /Linux/) {
	$CMD_SWAP = "/proc/meminfo";
	$SWITCH = "cat";
}
elsif ($os_version =~ /SunOS/) {
	$CMD_SWAP = "/usr/sbin/swap";
	$SWITCH ="-s";
}
else {
	print "OS not supported by this check";
	exit 3;
}	

$ENV{LC_ALL}="C";

# ------------------------------ FUNCTIONS -------------------------------------

sub check_params() {
    GetOptions("h", "l", "V", "w=i", "c=i");

    if ($opt_V) {
        print_info();
        print_version();
        exit $ERRORS{'UNKNOWN'};
    }

    if ($opt_l) {
        print_info();
        print_license();
        exit $ERRORS{'UNKNOWN'};
    }

    if ($opt_h || !$opt_w || !$opt_c || $opt_w < 1 || $opt_w > 100
               || $opt_c < 1 || $opt_c > 100 ) {
        print_info();
        print_help();
        exit $ERRORS{'UNKNOWN'};
    }
}

sub print_info() {
    print "Nagios plugin to check free swap space on Solaris.\n";
    print "Copyright (C) 2006-2008  Hannu Kivimäki / CSC - Scientific Computing Ltd.\n";
}

sub print_help() {
    print "\n";
    print "Usage: check_swap.pl -h | -w <1-100> -c <1-100>\n";
    print "\n";
    print "   -w  warning threshold percentage (integer)\n";
    print "   -c  critical threshold percentage (integer)\n";
    print "   -h  help (this text)\n";
    print "   -l  license info\n";
    print "   -V  version info\n";
    print "\n";
    print "The critical threshold has always priority, i.e. if\n";
    print "both thresholds are exceeded, a CRITICAL message is returned.\n";
    print "\n";
}

sub print_license() {
    print "\n";
    print "This program is free software; you can redistribute it and/or\n";
    print "modify it under the terms of the GNU General Public License\n";
    print "as published by the Free Software Foundation; either version 2\n";
    print "of the License, or (at your option) any later version.\n";
    print "\n";
    print "This program is distributed in the hope that it will be useful,\n";
    print "but WITHOUT ANY WARRANTY; without even the implied warranty of\n";
    print "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n";
    print "GNU General Public License for more details.\n";
    print "\n";
    print "You should have received a copy of the GNU General Public License\n";
    print "along with this program; if not, write to the Free Software\n";
    print "Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.\n";
    print "\n";
}

sub print_version() {
    my $dollar = "\$";
    print "\n";
    print "\$Id: check_swap.pl,v 1.2 2008/08/28 14:44:44 kivimaki Exp $dollar\n";
    print "\n";
}

# ----------------------------- MAIN PROGRAM -----------------------------------

check_params();

if ($os_version =~ /Linux/) {
	if (! -e $CMD_SWAP) {
		print "Erreur: $CMD_SWAP introuvable\n";
		exit $ERRORS{'UNKNOWN'};
	}

	$swap_available = `$SWITCH $CMD_SWAP | grep SwapFree`;
	$swap_available =~ /SwapFree:\s+(.*?) kB/mg;
	$swap_available = $1;
	my $swap_total=`$SWITCH $CMD_SWAP | grep SwapTotal`;
	$swap_total=~ /SwapTotal:\s+(.*?) kB/mg;
	$swap_total=$1;
	$swap_used = int($swap_total-$swap_available);
}

elsif ($os_version =~ /SunOS/) {
	if (! -x $CMD_SWAP) {
		print "Erreur: $CMD_SWAP introuvable ou non exécutable\n";
		exit $ERRORS{'UNKNOWN'};
	}

        @swap_results = split(/ +/, `$CMD_SWAP $SWITCH`);
        $swap_used = $swap_results[8];
        $swap_available = $swap_results[10];
}

# Strip 'k' for kilobytes (tr removes all non numeric characters):
$swap_used =~ tr/[0-9]//cd;
$swap_available =~ tr/[0-9]//cd;

# Calculate swap in megabytes:
$swap_available_m = sprintf "%.2f", ($swap_available / 1024);
$swap_total_m = sprintf "%.2f", (($swap_used + $swap_available) / 1024);

# Calculate swap in gigabytes
$swap_available_g = sprintf "%.2f", ($swap_available_m / 1024);
$swap_total_g = sprintf "%.2f", ($swap_total_m / 1024);

# Calculate free swap percentage and round to integer:
$swap_free_pct = int( ($swap_available / ($swap_used + $swap_available)) * 100 + 0.5);

$state_text = "- free: $swap_free_pct% ($swap_available_g Gb)";
$perf_text = "FREE=${swap_available_g}Gb;TOTAL=${swap_total_g}Gb";

if ($swap_free_pct < $opt_c) {
    print "CRIT=free_<${opt_c}%|$perf_text\n";
    exit $ERRORS{'CRITICAL'};
} elsif ($swap_free_pct < $opt_w) {
    print "SWAP WARN - free < $opt_w%|$perf_text\n";
    exit $ERRORS{'WARNING'};
}

print "SWAP OK $state_text|$perf_text\n";
exit $ERRORS{'OK'};
