#!/bin/ksh
#
# Surveillance hardware
# via hpasmcli
# 
# 24/11/2010 (SBO) : Création
# Concaténation de tous les "petits scripts"
export LANG=C

#Initialisation des variables
prog=`basename $0`
HOSTNAME=`hostname|tr [a-z] [A-Z]`
liste_crit=""
liste_warn=""

#Fonctions
wait_or_kill(){
	PID=$1
	cpt=0
	while [ $cpt -le $2 ]
	do
		if [ `ps -fp $PID | wc -l` -gt 1 ]; then
				cpt=`expr $cpt + 1`
					sleep 1
			else
					# On dépasse le compteur pour sortir de la boucle
					cpt=`expr $2 + 1`
			fi
	done

	if [ `ps -fp $PID | wc -l` -gt 1 ]; then
		kill -9 $PID 2>/dev/null 1>/dev/null
		return 1
	else
		return 0
	fi
}

## Niveau de sévérité Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

if [ $# -lt 2 ]; then
echo "Usage: $prog <warning temperature threshold (%)> <critical temperature threshold (%)>"
exit $UNKNOWN
fi

# TEMP threshold values (%)
TEMP_WARNING=$1 
TEMP_CRITICAL=$2

if (( $TEMP_CRITICAL <= $TEMP_WARNING ))
then
        echo "Critical threshold value must be more than the warning threshold value"
        exit $UNKNOWN
fi
#HP-Health up sur le serveur?
home_script_generic=/etc/sensu/nagios/Generic
# Vérification de la présence du check_processus
if [ ! -x $home_script_generic/check_processus.sh ]; then
        echo "Le script $home_script_generic/check_processus.sh est introuvable ou non executable"
        exit 3
fi
$home_script_generic/check_processus.sh -n hpasmxld -u root 2>&1 1>/dev/null
if [ $? -ne 0 ]; then
	$home_script_generic/check_processus.sh -n hpasmlited -u root 2>&1 1>/dev/null
	if [ $? -ne 0 ]; then
		echo "Le service HP-health n'est pas démarré sur ce serveur."
		exit 3
	fi
fi

#HPASM ok sur ce serveur?
if (( `ls -l /sbin/hpasmcli 2>/dev/null| wc -l`==1 )) ; then
	HPASMCLI_CMD="sudo /sbin/hpasmcli -s"
	if (( `sudo -l 2>/dev/null | grep -c "hpasmcli"`==0 )) && [ -f /sbin/hpasmcli ]
	then
		# Si l'utilisateur nrpe n'a pas le droit d'exécuter hpasmcli en tant que root, on le lance pour avoir le message d'erreur explicite, et on sort
		echo "Impossible d'exécuter hpasmcli : `${HPASMCLI_CMD} "help" 2>&1 | awk -F"." '{print $1}'`"
		exit $UNKNOWN
	fi
elif (( `ls -l /opt/HPQhealth/sbin/hpasmcli 2>/dev/null| wc -l`==1 )) ; then
	#HP Solaris => Apache PRA
	HPASMCLI_CMD="echo q | sudo /opt/HPQhealth/sbin/hpasmcli -s"
	if (( `sudo -l 2>/dev/null | grep -c "hpasmcli"`==0 )) && [ -f /opt/HPQhealth/sbin/hpasmcli ]
	then
		# Si l'utilisateur nrpe n'a pas le droit d'exécuter hpasmcli en tant que root, on le lance pour avoir le message d'erreur explicite, et on sort
		echo "Impossible d'exécuter hpasmcli : `${HPASMCLI_CMD} "help" 2>&1 | awk -F"." '{print $1}'`"
		exit $UNKNOWN
	fi
else
	echo "La commande hpasmcli n'existe pas sur ce serveur."
	exit $UNKNOWN
fi

#On vérifie que la commande HPASMCLI fonctionne
# 1- est-ce que l'occurence précédente s'est bien terminée (commande parfois gelée)
if (( `ps -ef | grep "hpasmcli -s help" | grep -v grep | wc -l` >= 1 )) ; then
	echo "Erreur : la commande hpasmcli ne se termine pas."
	exit $UNKNOWN
else
	# 2- est-ce qu'elle fonctionne?
	${HPASMCLI_CMD} "help" 2>&1 1>/dev/null &
	PID="$!"
	wait_or_kill $PID 10
	if (( $? != 0 )); then
		if (( `ps -ef | grep hpasmcli | grep -v grep | wc -l` == 0 )) ; then
			echo "Impossible de communiquer avec le démon hpasmd."
		else
			echo "Erreur lors de l'exécution de la commande hpasmcli."
		fi
		exit $UNKNOWN
	fi
fi


#HPACUCLI ok sur ce serveur?
if (( `ls -l /usr/sbin/hpacucli 2>/dev/null| wc -l`==1 )) ; then
	HPACUCLI_CMD="sudo /usr/sbin/hpacucli"
	if (( `sudo -l 2>/dev/null | grep -c "hpacucli"`==0 )) && [ -f /usr/sbin/hpacucli ]
	then
		# Si l'utilisateur nrpe n'a pas le droit d'exécuter hpacucli en tant que root, on le lance pour avoir le message d'erreur explicite, et on sort
		echo "Impossible d'exécuter hpacucli : `${HPACUCLI_CMD} "help" 2>&1 | awk -F"." '{print $1}'`"
		exit $UNKNOWN
	fi
elif (( `ls -l /opt/HPQacucli/sbin/hpacucli 2>/dev/null| wc -l`==1 )) ; then
	#HP Solaris => Apache PRA
	HPACUCLI_CMD="sudo /opt/HPQacucli/sbin/hpacucli"
	if (( `sudo -l 2>/dev/null | grep -c "hpacucli"`==0 )) && [ -f /opt/HPQacucli/sbin/hpacucli ]
	then
		# Si l'utilisateur nrpe n'a pas le droit d'exécuter hpacucli en tant que root, on le lance pour avoir le message d'erreur explicite, et on sort
		echo "Impossible d'exécuter hpacucli : `${HPACUCLI_CMD} "help" 2>&1 | awk -F"." '{print $1}'`"
		exit $UNKNOWN
	fi	
else
	echo "La commande hpacucli n'existe pas sur ce serveur."
	exit $UNKNOWN
fi


#On vérifie que la commande HPACUCLI fonctionne
# 1- est-ce que l'occurence précédente s'est bien terminée (commande parfois gelée)
if (( `ps -ef | grep "hpacucli help" | grep -v grep | wc -l` >= 1 )) ; then
	echo "Erreur : la commande hpacucli ne se termine pas."
	exit $UNKNOWN
else
	# 2- est-ce qu'elle fonctionne?
	${HPACUCLI_CMD} "help" 2>&1 1>/dev/null &
	PID="$!"
	wait_or_kill $PID 10
	if (( $? != 0 )); then
		echo "Erreur lors de l'exécution de la commande hpacucli."
		exit $UNKNOWN
	fi
fi


#On lance la commande pour interroger la température
#en ne récupérant que les colonnes qui nous intéressent 
#et en calculant immédiatement les seuils WARNING et CRITICAL
${HPASMCLI_CMD} "show temp" | grep "^#" | awk '{print $1" "$2" "$3" "$4" "($4*'$TEMP_WARNING'/100)" "($4*'$TEMP_CRITICAL'/100)}' | sed "s/C\/[0-9]*F//g" | while read ligne
do
	module="`echo $ligne | awk '{print $2"'\('"$1"'\)'"}'`"  #nom composé de la sorte : Temp Nom_du_module (Numéro_de_la_sonde)
	curTemp=`echo $ligne | awk '{print $3}'`
	threshold=`echo $ligne | awk '{print $4}'`
	warn_threshold=`echo $ligne | awk '{print $5}'`
	crit_threshold=`echo $ligne | awk '{print $6}'`
	 
	if [[ $curTemp != "-" ]] ; then	# Cas où la sonde est positionné sur un matériel absent (ex: 2e CPU)
		if (( $curTemp >= $threshold )) ; then
			liste_crit="${liste_crit}Temp_${module}(>=${threshold}C),"
		elif (( $curTemp > $crit_threshold )) ; then
			liste_crit="${liste_crit}Temp_${module}(>${crit_threshold}C),"
		elif (( $curTemp > $warn_threshold )) ; then
			liste_warn="${liste_warn}Temp_${module}(>${warn_threshold}C),"
		fi
	fi
done

#On lance la commande pour interroger les ventilateurs
${HPASMCLI_CMD} "show fans" | grep "^#" | while read ligne
do
	num_fan="`echo $ligne | awk '{print $1}'`" 
	sit_fan="`echo $ligne | awk '{print $2}'`"
	pres_fan="`echo $ligne | awk '{print $3}'`"
	vit_fan="`echo $ligne | awk '{print $4}'`"
	pct_vit_fan="`echo $ligne | awk '{print $5}'`"

	if [[ $pres_fan != "Yes" ]] ; then
		if [[ $pres_fan != "No" ]] ; then
			liste_crit="${liste_crit}Fan_${sit_fan}($num_fan)_Status_${pres_fan},"
		fi
	elif [[ $vit_fan != "NORMAL" ]] ; then
		liste_warn="${liste_warn}Fan_${sit_fan}($num_fan)_Speed_${vit_fan}($pct_vit_fan),"
	fi
done

#On lance la commande pour interroger les alims (numéro présence condition)
echo $(${HPASMCLI_CMD} "show powersupply" | egrep "Power supply|Present|Condition"| sed "s/Condition:.*$/&@NEW_LINE@/g") | sed "s/@NEW_LINE@/\n/g" | awk '{print $3" "$6" "$8}' | grep "^#" | while read ligne
do

	num_pws="`echo $ligne | awk '{print $1}'`" 
	pres_pws="`echo $ligne | awk '{print $2}'`"
	cond_pws="`echo $ligne | awk '{print $3}'`"

	if [[ $pres_pws != "Yes" ]] ; then
		liste_crit="${liste_crit}PWS_${num_pws}_Status_${pres_pws},"
	elif [[ $cond_pws != "Ok" ]] ; then
		liste_crit="${liste_crit}PWS_${num_pws}_Condition_${cond_pws},"
	fi
done

#On lance la commande pour interroger les modules mémoire (Cartridge Module Present Status)
nb_dimm=0
nb_dimm_na=0
echo $(${HPASMCLI_CMD} "show dimm" | egrep "Cartridge|Processor|Module|Present|Status|^$" | sed "s/^$/@NEW_LINE@/g") | sed "s/@NEW_LINE@/\n/g" | awk '$1!="" {print $1" "$3" "$6" "$8" "$NF}' | while read ligne
do
	type_place_dimm="`echo $ligne | awk '{print $1}'`" 
	place_dimm="`echo $ligne | awk '{print $2}'`" 
	num_dimm="`echo $ligne | awk '{print $3}'`" 
	pres_dimm="`echo $ligne | awk '{print $4}'`"
	status_dimm="`echo $ligne | awk '{print $5}'`"

	if [[ $status_dimm != "Ok" ]] && [[ $status_dimm != "N/A" ]] ; then
		liste_crit="${liste_crit}DIMM_${num_dimm}(${type_place_dimm}_${place_dimm})_Status_${status_dimm}_Present_${pres_dimm},"
	elif [[ $status_dimm == "N/A" ]] ; then
			(( nb_dimm_na +=1 ))
	fi
	(( nb_dimm +=1 ))
done
#Cas où tous les modules mémoires sont en N/A => pb firmware
if (( $nb_dimm > 0 )) && (( $nb_dimm == $nb_dimm_na )) ; then
		liste_warn="${liste_warn}Status_of_all_${nb_dimm}_dimms_is_n/a_(please_upgrade_firmware),"
fi

#On lance la commande pour interroger l'état des processeurs (num_proc status)
echo $(${HPASMCLI_CMD} "show server" | egrep "Processor:|Status|^$" | sed "s/^$/@NEW_LINE@/g") | sed "s/@NEW_LINE@/\n/g" | awk '$1!="" {print $2" "$5}' | while read ligne
do

	num_proc="`echo $ligne | awk '{print $1}'`" 
	status_proc="`echo $ligne | awk '{print $2}'`"

	if [[ $status_proc != "Ok" ]] ; then
		liste_crit="${liste_crit}PROC_${num_proc}_${status_proc},"
	fi
done


#On lance la commande pour interroger les disques, si elle est présente
if [ -n "${HPACUCLI_CMD}" ] ; then
	retourDisk="`${HPACUCLI_CMD} ctrl all show config`"
	if [ $? -ne 0 ] ; then 
		echo "Impossible d'exécuter hpacucli : `${HPACUCLI_CMD} ctrl all show config 2>&1 | awk -F"." '{print $1}'`"
		exit $UNKNOWN
	fi
	echo "$retourDisk" | grep drive | sed "s/\:/_/g" | while read ligne
	do
		disk="`echo $ligne | awk '{print $1"_"$2}'`" 
		status_disk="`echo $ligne | awk -F"," '{print $NF}' | sed 's/\ /_/g' | sed 's/^_//g' | sed 's/)//g'`"

		if [[ $status_disk != "OK" ]] ; then
			liste_crit="${liste_crit}${disk}_${status_disk},"
		fi
	done
fi

RC=$OK
messerr=""
if [ -n "$liste_warn" ] ; then
	RC=$WARNING
	messerr="WARN=`echo $liste_warn|sed 's/,$//g'`"
fi
if [ -n "$liste_crit" ] ; then
	RC=$CRITICAL
	messerr="CRIT=`echo $liste_crit|sed 's/,$//g'`;$messerr"
fi

if [ -z "$messerr" ] ; then
	echo "Hardware OK|hostname=${HOSTNAME}"
else
	messerr="`echo $messerr |sed 's/;$//g'`"
	echo "$messerr|hostname=${HOSTNAME}"
fi

exit $RC
