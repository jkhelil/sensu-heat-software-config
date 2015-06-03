#!/usr/bin/perl 

########################################
#  
#
#(08-07-14 VWA  initial              #
########################################

use strict;
use warnings;


# --- OSSEC ALERT FILE ---
my $_ossec_alert_log='/var/ossec/server/logs/alerts/alerts.log';

# --- OSSEC LEVEL CRITICAL ---
my $critical="7";

# --- OSSEC SERVER NAME ---
chomp(my $ossec=`hostname`);

# --- SCRIPT VARIABLES ---
my @level="";
my @alert="";
my $_msg="";
my @host="";
my $_ossec_nagios_msg="";
my $_count=0;
my $_num=0;
my $_nagiosdata='/var/ossec/server/nagios/data';
my $_ossec_nagios_path="/var/ossec/server/nagios/data/tmp";
my $_countocheck="$_ossec_nagios_path/count.ocheck";
my $_tmpcheck="$_ossec_nagios_path/tmpcheck";
my $_startline=0;
my $_endline=0;
my $_countcheck="";
my @_command="";
my @date="";
my @date_err="";
# --- END SCRIPT VARIABLES ---

mkdir $_nagiosdata unless -d $_nagiosdata;
mkdir $_ossec_nagios_path unless -d $_ossec_nagios_path;
system("test ! -e '$_countocheck' >> $_countocheck; chmod 777 $_countocheck");
system("test ! -e '$_tmpcheck' >> $_tmpcheck; chmod 777 $_tmpcheck");

if (!-e $_countocheck)
{
open (my $_file_count, ">$_countocheck") or die "Could not open file";
    print $_file_count "0";
    close $_file_count;
}
#`echo 0 > '$_countocheck'`;


$_countcheck="cat $_countocheck";
chomp($_startline=`$_countcheck`);

chomp(@date=`date '+%d/%m/%Y [%H:%M:%S]'`);
chomp(@date_err=`date '+%d-%m-%Y-%H:%M:%S'`);


if (! -r $_ossec_alert_log)
{
 print ("OSSEC alert file is not readable");
 exit 3;
}
else
{
@_command="cat $_ossec_alert_log | wc -l";
chomp($_endline=`@_command`);
}
if ( $_startline gt $_endline )
{
$_startline = 0;
}

$_startline = $_startline + 1;

open (my $_myfile, ">$_countocheck") or die "Could not open file";
print $_myfile $_endline;
close $_myfile;

#`echo $_endline > '$_countocheck'`;

system ("> '$_tmpcheck'");

# --- ALERT FILE PARSING ---
my @_text=`head -n $_endline $_ossec_alert_log | tail -n +$_startline | grep '(level' -B 1 -A 2`;

my $size=@_text;

for ($_count=0;$_count<$size;$_count++){
    if ($_text[$_count] =~ m/level/){
        @level="";
        @level=split(/\(level /, $_text[$_count]);
        @level=split(/\) ->/, $level[1]);
        if ($level[0] >= $critical){
	    chomp ($level[1]);
	    if ($_text[$_count-1] !~ m/$ossec/){
                @host=$_text[$_count-1];
                @host=split(/ \(/, $host[0]);
                @host=split(/\) /,$host[1]);
		        $_text[$_count+1]=~ s/[<>;()']//g; 
                chomp(@alert=$_text[$_count+1]);
                $host[0]=uc ($host[0]);
                #$host[0]=~ s|/?$|;|;
            }else{
                $host[0]= uc ($ossec);
            }
            $_num++;
            $_msg=$_msg.";"."$host[0]";
	    system ("echo '$_msg' >> '$_tmpcheck'");
      
  }   
      system ("echo @date [$host[0]] @alert >> '$_nagiosdata/ossec-nagios.log.@date_err.err'");

    }
}

$_msg=~ s/^;// ;

# --- Send Alert to Nagios ---
$_ossec_nagios_msg=`cat '$_tmpcheck' | uniq`;


if ($_ossec_nagios_msg eq ""){
    print "OSSEC Server OK";
    exit 0;
}else{
#    print "ERR= $_num alert(s) found: $_msg";
#     print "ERR=$_msg|alert=$_num";
      print "ALERT(s)=$_num";
   exit 2;
}
print "Something is wrong, script went out of bounds?";
exit 1;