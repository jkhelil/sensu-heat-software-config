#!/bin/bash
# Surveillance de l'état des cartes fusionIO
# 2013/07/04 (SBO) : Création. Inspiré du check fourni par NVI
#


if [ -r /proc/mdstat ] ; then
	if [[ ! `grep "\[UU\]" /proc/mdstat` ]] 
	then
		if [[ `grep recovery /proc/mdstat` ]]
		then
			echo "WARN=Resynchro"
			exit 1
		fi
		echo "PROBLEME=RAID" 
		exit 2
	fi

	[[ `grep "(F)" /proc/mdstat` ]] && echo "KO=RAID_FAILED" && exit 2;

	echo "OK"
else
	echo "N/A"
fi

exit 0