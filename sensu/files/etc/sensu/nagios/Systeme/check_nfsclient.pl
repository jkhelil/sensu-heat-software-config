#!/usr/bin/perl -w
#
# check_nfs.pl
#
# Monitor NFSv4 servers (and clients)
#
# ADH: 24/11/11 - custom version du script officiel...

use strict;
use File::Basename;
use lib "/HOME/nrpe/product/current/libexec";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use vars qw($PROGNAME);

sub exit_error($$);
sub print_help();
sub print_usage();

$PROGNAME = 'check_nfs';

my ($opt_V, $opt_H, $client, $opt_S, $opt_w, $verbose, $state, $status, $perfs);

$opt_V = $opt_H = $client = $opt_S = '';
$opt_w = 100;
$verbose = 0;
$state = 'OK';
$status = '';
$perfs = '|';

$ENV{'BASH_ENV'}='';
$ENV{'ENV'}='';
$ENV{'PATH'}='';
$ENV{'LC_ALL'}='C';

# Get the options
use Getopt::Long;
Getopt::Long::Configure('bundling');
GetOptions(
	   'V'  => \$opt_V,     'version'   => \$opt_V,
	   'h'  => \$opt_H,     'help'      => \$opt_H,
	   's'  => \$opt_S,     'sec'       => \$opt_S,
	   'v+'  => \$verbose,  'verbose+'  => \$verbose,
	   'w=s' => \$opt_w,    'warning=s' => \$opt_w,
	   );

# -h|--help displays help
if ($opt_H) {
    print_help();
    exit $ERRORS{'OK'};
}

# -V|--version displays version number
if ($opt_V) {
    print_revision($PROGNAME,'$Revision: 0.2 $ '); 
    exit $ERRORS{'OK'};
}

my (@rpc_nfs,@rpc_nfs_old);

    my (@proc3_nfs);
    open(RPC_NFS, '/proc/net/rpc/nfs') ||
    exit_error('UNKNOWN', "cannot read the file: '/proc/net/rpc/nfs'\n");
    while (my $line = <RPC_NFS>) {
	if ($line =~ /^rpc/) { @rpc_nfs = split(' ', $line); }
	elsif ($line =~ /^proc3/) { @proc3_nfs = split(' ', $line); }
    }
    close RPC_NFS;

    my (@proc3_nfs_old);
    if (-f "/tmp/nfs_datas") {
    	open(RPC_NFS, '/tmp/nfs_datas') ||
    	exit_error('UNKNOWN', "cannot read the file: '/tmp/nfs_datas'\n");
    	while (my $line = <RPC_NFS>) {
		if ($line =~ /^rpc/) { @rpc_nfs_old = split(' ', $line); }
		elsif ($line =~ /^proc3/) { @proc3_nfs_old = split(' ', $line); }
    	}
    	#printf "@rpc_nfs_old\n@proc3_nfs_old\n";
    	#printf "@rpc_nfs\n@proc3_nfs";
    	close RPC_NFS;
    } else  {
	@rpc_nfs_old = (0,0,0,0,0,0,0,0,0,0);
	@proc3_nfs_old = (0,0,0,0,0,0,0,0,0,0);
    }	

    open(RPC_NFS, '>', '/tmp/nfs_datas') ||
    exit_error('UNKNOWN', "cannot read the file: '/tmp/nfs_datas'\n");
    print RPC_NFS "@rpc_nfs\n@proc3_nfs";
    close RPC_NFS;

    if ($verbose) {
	#$status = $status . "nfsd threads = $nb_th ; ";
    }
    $perfs = $perfs . "nfs_read=".($proc3_nfs[8]-$proc3_nfs_old[8]).";";
    $perfs = $perfs . "nfs_write=".($proc3_nfs[9]-$proc3_nfs_old[9]).";";
    $perfs = $perfs . "rpc_calls=".($rpc_nfs[1]-$rpc_nfs_old[1]).";";
    $perfs = $perfs . "rpc_retrans=".($rpc_nfs[2]-$rpc_nfs_old[2]).";";
    $perfs = $perfs . "rpc_authrefrsh=".($rpc_nfs[3]-$rpc_nfs_old[3]).";";

# Check rpc errors
my ($rpc_error);
$rpc_error = 0;

shift(@rpc_nfs);

    if ($rpc_nfs[1] != 0) { 
	$rpc_error = 1;
	if ($verbose) { $status = $status . "Client retrans = $rpc_nfs[1] ; "; }
    }
    if ($rpc_nfs[2] != 0) {
	#$rpc_error = 1;
	if ($verbose) { $status = $status . "Client authrefrsh = $rpc_nfs[2] ; "; }
    }

if ($rpc_error) { 
    if (!$verbose) { $status = $status . "RPC errors ; "; }
}

exit_error($state, $status);

#
# subroutines
#
sub exit_error ($$) {
    my $the_state = shift;
    my $the_line = shift;
    chomp $the_line;
    if ($the_line =~ / $/) { chop($the_line); }
    if ($the_line =~ /;$/) { chop($the_line); }
    print "$the_state $the_line$perfs \n";
    exit $ERRORS{$the_state};
}

sub print_help () {
    print_revision($PROGNAME, '$Revision: 0.2 $ ');
    print "Copyright (c) 2005 Frédéric Jolly\n\n";
    print "NFS plugin for Nagios\n";
    print_usage();
    print "\n";
    print "   [-v]                    Verbose\n";
    print "\n";
    print "$PROGNAME monitors on an NFS client the following NFS features:\n";
    print "  - check if there are rpc errors\n";
    print "\n";
    print "$PROGNAME returns also performance data:\n";
    print "  - the rpc stats\n";
    print "  - the transfer rates\n";
    print "\n";
    support();
}

sub print_usage () {
    	print "Usage: \n";
	print " $PROGNAME [-v] [-i | --client] [-s | --sec] [-w=xx | --warning=xx]\n";
	print " $PROGNAME [-h | --help]\n";
	print " $PROGNAME [-V | --version]\n";
}

