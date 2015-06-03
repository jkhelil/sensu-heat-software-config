##
## Variables
##

# Script locations
SCRIPT=$(readlink -f $0)
SCRIPTDIR=$(dirname $SCRIPT)

# Script names
COUNTLUNINSG="$SCRIPTDIR/vnx-countluninsg.pl"
FINDHLU="$SCRIPTDIR/vnx-findhlu.pl"
NEXTEXPNUM="$SCRIPTDIR/vnx-getnextexpnum.pl"
CLAIMSH="$SCRIPTDIR/vplex-claim.sh"
RENAMESH="$SCRIPTDIR/vplex-rename.sh"
LISTEXTSH="$SCRIPTDIR/vplex-listextents.sh"
LISTVOLSH="$SCRIPTDIR/vplex-listvol.sh"
MKEXTSH="$SCRIPTDIR/vplex-mkextent.sh"
MKVOLSH="$SCRIPTDIR/vplex-mkvol.sh"
MKDEVSH="$SCRIPTDIR/vplex-mkdevice.sh"
XTVOLSH="$SCRIPTDIR/vplex-xtvol.sh"

NAVISECCLI="/opt/Navisphere/bin/naviseccli"
NAVISECDIR="$HOME/.naviseccli"

# General variables
VERBOSE=0
LOGUSER=0
QUIET=""

# Script-specific variables
ARRAY=""
ARRAYIP=""
ARRAYNAME=""
CLUSTER=""
VPLEX=""
ITEMPATH=""
ITEMNAME=""
ITEMTYPE=""
LOGPREFIX=""

##
## General functions
##

# log STRING
log() {
  [ -z "$QUIET" ] && echo $LOGPREFIX "$1"
}

# verb STRING
verb() {
  [ "$VERBOSE" -ge 1 ] && {
      echo $LOGPREFIX "   $1"
  }
}

# vverb STRING
vverb() {
  [ "$VERBOSE" -ge 2 ] && {
      echo $LOGPREFIX "       $1"
  }
}

##
## Script-specific functions
##

# pickarray 
pickarray() {
  vverb "Generating array-specific variables ..."
  LCVPLEX=$(echo $VPLEX | tr "A-Z" "a-z")
  if [ "$LCVPLEX" = "vscvplex1" ]
  then
    ARRAY="EMC-CLARiiON-CKM00122402026"
    ARRAYNAME="VSCVNX1"
    ARRAYIP="10.101.108.56"
    CLUSTER="cluster-1"
    ITEMPATH="/clusters/cluster-1"
  elif [ "$LCVPLEX" = "vscvplex2" ]
  then
    ARRAY="EMC-CLARiiON-CKM00122401999"
    ARRAYNAME="VSCVNX2"
    ARRAYIP="10.101.108.60"
    CLUSTER="cluster-2"
    ITEMPATH="/clusters/cluster-2"
  else
    echo "Unknown VPLEX : $VPLEX"
    exit 1
  fi
}

# buildpath
buildpath() {
  vverb "Generating item path ..."
  if [ "$ITEMTYPE" = "storagevolume" ]
  then
    ITEMPATH="$ITEMPATH/storage-elements/storage-volumes/$ITEMNAME"
  elif [ "$ITEMTYPE" = "extent" ]
  then
    ITEMPATH="$ITEMPATH/storage-elements/extents/$ITEMNAME"
  elif [ "$ITEMTYPE" = "device" ]
  then
    ITEMPATH="$ITEMPATH/devices/$ITEMNAME"
  elif [ "$ITEMTYPE" = "virtualvolume" ]
  then
    ITEMPATH="$ITEMPATH/virtual-volumes/$ITEMNAME"
  elif [ "$ITEMTYPE" = "array" ]
  then
    ITEMPATH="$ITEMPATH/storage-elements/storage-arrays/$ARRAY/logical-units"
  elif [ "$ITEMTYPE" = "storageview" ]
  then
    ITEMPATH="$ITEMPATH/exports/storage-views/$ITEMNAME"
  else
    echo "Unknown item type : $ITEMTYPE"
    exit 1
  fi
}

