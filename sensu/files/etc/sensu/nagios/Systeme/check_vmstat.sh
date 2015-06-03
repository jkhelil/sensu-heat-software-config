#! /bin/sh

warn=$1
crit=$2

if [ $# -lt 2 ] ; then
	echo "Usage: ./check_vmstat.sh <io_warn> <io_crit>"
	exit 3
fi

case `uname` in
	SunOS)
		stats=`iostat 1 16 | tail -16 | awk '{n++;user+=$(NF-3);sys+=$(NF-2);idle+=$NF;iowait+=$(NF-1)} END {print "user="user/n ";sys="sys/n ";idle="idle/n ";iowait="iowait/n}'`
		;;
	Linux)
		stats=`vmstat 1 16 | tail -15 | awk '{n++;user+=$(NF-4);sys+=$(NF-3);idle+=$(NF-2);iowait+=$(NF-1)} END {print "user="user/n ";sys="sys/n ";idle="idle/n ";iowait="iowait/n}'`
		;;
esac

status="OK"
ret_code=0
iowait=`echo $stats | tr ';' '\n' | grep iowait | cut -d '=' -f 2 | cut -d '.' -f 1`

if [ $iowait -gt $crit ] ; then
	status="CRIT=iowait(>$crit)"
	ret_code=2
else
	if [ $iowait -gt $warn ] ; then
		status="WARN=iowait(>$warn)"
		ret_code=1
	fi
fi

echo "$status | $stats"
exit $ret_code

