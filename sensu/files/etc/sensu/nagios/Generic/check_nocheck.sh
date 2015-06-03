#!/bin/sh
# Vérification de présence de nocheck
#
# Principe :
# Remonte un Warning si un nocheck dont l'âge est 
# compris entre MIN_AGE et MAX_AGE est trouvé
#
# 27/10/2010 (SBO): Création
#				+ajout comparaison check précédent
#				pour ne pas alerter 2 fois pour même flag
#				+modif précédente permet de mettre MAX_AGE
#				en paramètre optionnel
# 01/08/2011 (SBO) : Ajout check flags haproxy (Jira DTSUIVIPROD-157)
######################################################################

#Initialisation des variables
HOSTNAME=`hostname|tr [a-z] [A-Z]`
## Niveau de sévérité Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3
## Répertoire et fichiers de travail
paths_nocheck="/HOME/webadm/*/scripts/nagios/data /appl/*/scripts/nagios/data /appl/*/*/scripts/nagios/data"
paths_haproxy="/appl/*/haproxy /appl/*/*/haproxy"
metro_haproxy="/etc/sensu/nagios/CFG/haproxy_*.cfg"
wdir=/appl/nrpevsc/var
work_file=${wdir}/flags_nocheck_haproxy.tmp
swap_file=${wdir}/flags_nocheck_haproxy.swp
metro_work_file=${wdir}/flags_nocheck_haproxy.tmp
metro_swap_file=${wdir}/flags_nocheck_haproxy.swp
nocheck_file=${wdir}/nocheck.lst
haproxy_file=${wdir}/haproxy_flags.lst
metro_haproxy_file=${wdir}/metro_haproxy_flags.lst
old_param_file=${wdir}/flags_nocheck_haproxy.old_param
case `uname` in
            Linux)
				RPMQA=`rpm -qa 2>/dev/null`
			;;
            SunOS)
				RPMQA=""
			;;
            *) echo "OS not supported by this check."; exit 3;;
esac
if [ ! -f $nocheck_file ] || [ ! -f $haproxy_file ]; then
	if [ -w $wdir ] ; then
		touch $nocheck_file
		touch $haproxy_file
		touch $metro_haproxy_file
	else
		echo "NOCHECK $UNKNOWN : impossible d'écrire dans $wdir"
		exit $UNKNOWN
	fi
fi


#Vérification des paramètres, sinon valeur par défaut
if [ $# -eq 0 ] ; then
	MIN_AGE="+1"
else
	MIN_AGE=$1
	if [ $# -eq 2 ] ; then
		MAX_AGE=$2
		if [ $MAX_AGE -lt $MIN_AGE ] ; then
			echo "NOCHECK $UNKNOWN : MAX_AGE ($MAX_AGE) doit être supérieur à MIN_AGE ($MIN_AGE)"
			exit $UNKNOWN
		fi
	fi
fi

#On vérifie si les paramètres MIN_AGE et MAX_AGE ont changé depuis le précédent check
if [ -s $old_param_file ] ; then
	# Petite protection si le fichier contient n'importe quoi
	OLD_MIN_AGE=$MIN_AGE
	OLD_MAX_AGE=$MAX_AGE
	# Ensuite on le charge
	. $old_param_file
	if [ $MIN_AGE -ne $OLD_MIN_AGE ] ; then
		# On vide la précédente liste car les critères ont changé
		cat /dev/null > $nocheck_file
		cat /dev/null > $haproxy_file
		cat /dev/null > $metro_haproxy_file
	fi
	if [ 0$MAX_AGE -ne 0$OLD_MAX_AGE ] ; then
		# On vide la précédente liste car les critères ont changé
		cat /dev/null > $nocheck_file
		cat /dev/null > $haproxy_file
		cat /dev/null > $metro_haproxy_file
	fi
fi
#On backup les paramètres pour le prochain test
echo "OLD_MIN_AGE="$MIN_AGE > $old_param_file
echo "OLD_MAX_AGE="$MAX_AGE >> $old_param_file

#Cherche tous les nocheck compris entre MIN_AGE et MAX_AGE si celui-ci est défini
#sinon remonte tous les nocheck plus vieux que MIN_AGE
cat /dev/null > $swap_file
for path_nocheck in $paths_nocheck
do
	if [ -n "$MAX_AGE" ] ; then
		find $path_nocheck -type f -name "*.nocheck" -mtime $MIN_AGE -mtime -$MAX_AGE 2>/dev/null | awk -F"/" '{print $NF}' | awk -F"." '{print $1}' >> $swap_file
	else
		find $path_nocheck -type f -name "*.nocheck" -mtime $MIN_AGE 2>/dev/null | awk -F"/" '{print $NF}' | awk -F"." '{print $1}'  >> $swap_file
	fi
done
sort -u $swap_file > $work_file

# On compare avec ce qui avait été trouvé au check précédent pour ne pas alerter plusieurs fois si pas de changement
liste_nocheck_inst="`diff $nocheck_file $work_file 2>/dev/null | grep '^>' | awk '{print $2}'`"
cp $work_file $nocheck_file

#Est-ce qu'on est sur un des serveurs HAProxy (=user haproxy adm déclaré)
if [ -n "`grep hapadm /etc/passwd`" ] || [ -n "`echo "$RPMQA"| grep "haproxy"`" ]; then
	#Cherche tous les flags haproxy compris entre MIN_AGE et MAX_AGE si celui-ci est défini
	#sinon remonte ceux plus vieux que MIN_AGE
	cat /dev/null > $swap_file
	for path_haproxy in $paths_haproxy
	do
		if [ -n "$MAX_AGE" ] ; then
			find $path_haproxy -type f -name "down" -mtime $MIN_AGE -mtime -$MAX_AGE 2>/dev/null | sed "s:/: :g" | sed "s: down$::g" |awk '{print $NF}' >> $swap_file
			find $path_haproxy -type f -name "stop" -mtime $MIN_AGE -mtime -$MAX_AGE 2>/dev/null | sed "s:/: :g" | sed "s: stop$::g" |awk '{print $NF}' >> $swap_file
		else
			find $path_haproxy -type f -name "down" -mtime $MIN_AGE 2>/dev/null | sed "s:/: :g" | sed "s: down$::g" |awk '{print $NF}' >> $swap_file
			find $path_haproxy -type f -name "stop" -mtime $MIN_AGE 2>/dev/null | sed "s:/: :g" | sed "s: stop$::g" |awk '{print $NF}' >> $swap_file
		fi
	done
	sort -u $swap_file > $work_file

	# On compare avec ce qui avait été trouvé au check précédent pour ne pas alerter plusieurs fois si pas de changement
	liste_haproxy_inst="`diff $haproxy_file $work_file 2>/dev/null | grep '^>' | awk '{print $2}'`"
	cp $work_file $haproxy_file

	#Cherche les flags de metro haproxy compris entre MIN_AGE et MAX_AGE si celui-ci est défini
	cat /dev/null > $metro_swap_file
	if [ -n "$MAX_AGE" ] ; then
		find $metro_haproxy -type f -mtime $MIN_AGE -mtime -$MAX_AGE 2>/dev/null | xargs grep "_metro_nocheck=1" | grep -v "^#" | awk -F"_" '{print $2}' | sed "s/\.cfg//g" >> $metro_swap_file
	else
		find $metro_haproxy -type f -mtime $MIN_AGE 2>/dev/null | xargs grep "_metro_nocheck=1" | grep -v "^#" | awk -F"_" '{print $2}' | sed "s/\.cfg//g" >> $metro_swap_file
	fi
	sort -u $metro_swap_file > $metro_work_file

	# On compare avec ce qui avait été trouvé au check précédent pour ne pas alerter plusieurs fois si pas de changement
	liste_metro_haproxy_inst="`diff $metro_haproxy_file $metro_work_file 2>/dev/null | grep '^>' | awk '{print $2}'`"
	cp $metro_work_file $metro_haproxy_file
fi

#Sortie selon résultat de la recherche 
if [ -z "$liste_nocheck_inst" ] && [ -z "$liste_haproxy_inst" ] && [ -z "$liste_metro_haproxy_inst" ] ; then
	RC=$OK
	#Mais pour info, on va afficher les flags existants pour lesquels on aurait déjà été alerté
	if [ -s $nocheck_file ] ; then
		liste_nocheck_inst="`cat $nocheck_file`"
		message="NOCHECK=`echo $liste_nocheck_inst | sed "s/ /,/g"` $message"
	fi
	if [ -s $haproxy_file ] ; then
		liste_haproxy_inst="`cat $haproxy_file`"
		message="FlagHAPROXY=`echo $liste_haproxy_inst | sed "s/ /,/g"` $message"
	fi
	if [ -s $metro_haproxy_file ] ; then
		liste_metro_haproxy_inst="`cat $metro_haproxy_file`"
		message="MetroHAPROXY=`echo $liste_metro_haproxy_inst | sed "s/ /,/g"` $message"
	fi
	if [ -z "$message" ] ; then
		message="No flag older than $MIN_AGE day(s) found"
	fi
else
	RC=$WARNING
	if [ -n "$liste_nocheck_inst" ] ; then
		liste_nocheck_inst="`echo $liste_nocheck_inst`"
		message="NOCHECK=`echo $liste_nocheck_inst | sed "s/ /,/g"` $message"
	fi
	if [ -n "$liste_haproxy_inst" ] ; then
		liste_haproxy_inst="`echo $liste_haproxy_inst`"
		message="FlagHAPROXY=`echo $liste_haproxy_inst | sed "s/ /,/g"` $message"
	fi
	if [ -n "$liste_metro_haproxy_inst" ] ; then
		liste_metro_haproxy_inst="`echo $liste_metro_haproxy_inst`"
		message="MetroHAPROXY=`echo $liste_metro_haproxy_inst | sed "s/ /,/g"` $message"
	fi
fi
echo "$message"
exit $RC