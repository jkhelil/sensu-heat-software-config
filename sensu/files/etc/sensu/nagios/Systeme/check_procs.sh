#! /bin/sh
# tsync::spezia-bck falerna-bck fiore-bck pianoro-bck riola-bck pieve-bck rivalta-bck ragusa-bck dozza-bck amantea-bck cascina-bck cervia-bck gaeta-bck gaiole-bck faenza-bck    felice-bck     cannara-bck baia-bck barge-bck claviere-bck biella-bck caserta cecina-bck marino-bck ombra-bck serrara-bck sperlonga-bck sperlonga  sona-bck punta-bck  imola casole-bck
# sync::rodigo-bck rezzato-bck villongo-bck volpiano-bck noci-bck nemi-bck praiano-bck pozzuoli-bck pellio-bck peccioli-bck cesena budoni-bck bornio-bck ascoli-bck alassio-bck monteronni-bck molveno-bck letojanni-bck levico-bck gubbio-bck gaggi-bck ostuni-bck oliveto-bck noto-bck pianoro-bck todi-bck tempio-bck sestri-bck sasso-bck narni-bck duino-bck spoleto-bck dasso-bck mauro-bck pouilles-bck bonifacio-bck martino-bck paceco-bck palmi-bck rapallo-bck recanati-bck 10.101.144.43 selvino-bck saronno-bck sarnico-bck sanremo-bck sarnico sanremo pineto-bck siderno-bck   grado

warn=$1
crit=$2

if [ $# -lt 2 ] ; then
	echo "Usage: ./check_procs.sh <idle_warn> <idle_crit>"
	exit 3
fi

procs=`ps ax | grep -v grep | wc -l`
status="OK"
ret_code=0

if [ $procs -gt $crit ] ; then
	status="CRITICAL"
	ret_code=2
else
	if [ $procs -gt $warn ] ; then
		status="WARNING"
		ret_code=1
	fi
fi

echo "$status - $procs processus en cours|procs=$procs"
exit $ret_code

