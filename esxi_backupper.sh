#!/bin/sh

#############################################################################
#
# VMware Backup Script written by Matthias suhm (c) 2014.
# suuhm (c) 2014
#
# Set Cron for Auostart and alive Restart: (/etc/rc.local)
#
## MATTHIAS suhm - CRON SCRIPT RESTART ALIVE 3:00 AM
# /bin/kill $(cat /var/run/crond.pid)
# /bin/echo '0 3 * * * /suhm/bak.sh >> /var/spool/cron/crontabs/root
# /bin/crond
#
#
# You will need to change
# 1. The NFS definitions at the top of this script.
# 2. The "Cycle" definition underneath it if you don't want a rotating 0-4
#    backup daily structure.
# 3. The code labelled "README" around line 270, which chooses which
#    datastores to backup.
#
# For command-line usage, run the command with the "--help" option as the
# only argument on the command-line.
#
#############################################################################

#

# DEFINE - NFSv4 STORAGE CONTROL
# NAME UNTER ESXi SERVER: /vmfs/volumes/[NFSStoreName]
NFSStoreName=ServROOTNFS
# SERVER AN SICH - DNS-HOSTNAME: Serv-NAS
NFSServer=12.8.1.125
# SHARE AUF NFS SERVER
NFSShare=/volume1/Backup
# DEFINE TEH FILES WHICH ARE nes
FILES=datastore1/[!isotmpWindows*]*
LOG=/tmp/ServROOT_NAS.log
#############################################################################
# Change the next bit of code to produce a "Backup Name" or number
# We use a cycle of 0,1,2,3,4 moving to the next one each day
Cycle=`date +%d%m%y`
#Cycle=`expr $Cycle / 86400`
#Cycle=`expr $Cycle % 5`

#############################################################################

#PATH=/bin:/sbin
#export PATH
DATE=`date +%Y-%m-%d' '%H:%M`
sH=$(date +%H)
sM=$(date +%M)

#############################################################################
# FUNCTIONS 
#############################################################################

# Print the command-line syntax
Usage() {
  echo
  echo Usage: $0 '[ --dobackup ] [ --list ] [ --zip ] [ --all ]'
  echo
  echo '--dobackup = Backup VMs which are powered off/on (NOSNAPSHOT), and templates'
  echo '--list     = List ALL VM Ids'
  echo '--compress = Compress backed up disk files'
  echo '--all      = ALL VM Ids'
  echo
  echo 'Enabling compression will put more CPU load on your VMware host,'
  echo 'but will reduce the quantity of NFS traffic and save disk space'
  echo 'on your NFS backup datastore.'
  echo
}

# Process command-line arguments of --help --on and --off and --compress
# --help     ==> Print the command-line usage and exit
# --dobackup ==> Backup Powered On  VMs
# --list     ==> Backup Powered Off VMs
# --zip      ==> Gzip up the .vmdk files
# --all      ==> Alles!
CommandLine() {
  DoBackup=0
  ListVM=0
  Compress=0
  All=0
  if [ "$1" = "--help" -o "$2" = "--help" -o "$3" = "--help" -o "$#" = 0 ]; then
  #$? -> Return Code
    Usage
    exit 1
  fi
  if [ "$1" = "--dobackup" -o "$2" = "--dobackup" -o "$3" = "--dobackup" ]; then
    DoBackup=1
  fi
  if [ "$1" = "--list" -o "$2" = "--list" -o "$3" = "--list" ]; then
    ListVM=1
  fi
  if [ "$1" = "--zip" -o "$2" = "--zip" -o "$3" = "--zip" ]; then
    Compress=1
  fi
  if [ "$1" = "--all" -o "$2" = "--all" -o "$3" = "--all" ]; then
	 All=1
  fi
}

# Get a list of all the VMs and produce a list of
# <numeric id>\t<path of .vmx file>
# in /tmp/ServROOT-Backups-VMlist.txt.$$ <- $$ RETURNS PROCESSID 
ListVMIDs() {
  vim-cmd vmsvc/getallvms | \
  sed -e 's/[[:blank:]]\{3,\}/\t/g' | \
  cut -f 1,3 | \
  sed -e '1,1d' | \
  sed -e 's/\[/\/vmfs\/volumes\//' | \
  sed -e 's/\] /\//' > /tmp/ServROOT-Backups-VMlist.txt.$$
}

# Mount the NFS datastore to store all the backups in
MountNFS() {
  # First test if it is already mounted
  if ( vim-cmd hostsvc/summary/fsvolume | \
       awk '{ print $1 }' | \
       fgrep -q $NFSStoreName ); then
    echo NFS Backup store already mounted
    NFSMOUNTED=1
  else
    echo NFS mounting ${NFSServer}:$NFSShare on /vmfs/volumes/$NFSStoreName
    # 0 on the end means read/write, 1 = read-only
    vim-cmd hostsvc/datastore/nas_create $NFSStoreName $NFSServer $NFSShare 0
    if [ ! $? -eq 0 ]; then
      echo NFS mount failed, terminating.
      exit 1
    fi
    # Now test that we can actually write to the new NFS store
    #DEACTIVATE mkdir /vmfs/volumes/$NFSStoreName/$Cycle
    NFSMOUNTED=1
  fi
}

# If VM is ONline than exit or Take Snapshot ;)
PoweredOn() {
	if ( vim-cmd vmsvc/power.getstate $VM | fgrep -q 'Powered on' ); then
   # It is powered on. Do we need to back it up?
   echo VM ist noch an Bitte vorhher ausschalten. Da es sonst zu Problemen kommen kann | tee -a $LOG
   echo 
   continue
   fi
}

# Backup the VM or template.
# We copy all the VMXFILEs and the log files and then copy/compress everything
# in ServROOT-Backups.filelist.$$ which is the list of files in this dir that
# need backing up.
BackupDir() {
  # Now back up all the files in the current directory whose names are in
  # /tmp/ServROOT-Backups.filelist.$$
  echo About to backup these files: | tee -a $LOG
  TO=/vmfs/volumes/${NFSStoreName}/${Cycle}/
  mkdir -p "$TO"
  # TRANSFER DATA - #cp *.log "$TO" 
  if [ $VM = "all" ]; then
  cut -f5 -d "/" /tmp/ServROOT-Backups-VMlist.txt.$$ | \
  while read a
  do
   VM=`grep "$a" /tmp/ServROOT-Backups-VMlist.txt.$$ | awk '{print $1}'` 
   echo Copying $a to $TO | tee -a $LOG
   PoweredOn 
	cp -r "$a" "$TO"
  done
  else 
    PoweredOn
    VM=`grep -w $VM /tmp/ServROOT-Backups-VMlist.txt.$$ | cut -f5 -d "/"`
    echo Copying $VM to $TO | tee -a $LOG 
	 cp -r "$VM" "$TO"
  fi 
}

# COMPRESS FUNCTION !beta!
ZipIt() {
  echo About to backup and Compress these files: | tee -a $LOG
  TO=/vmfs/volumes/${NFSStoreName}/${Cycle}/
  mkdir -p "$TO"
  # TRANSFER - #cp *.log "$TO"
  if [ $VM = "all" ]; then
  cut -f5 -d "/" /tmp/ServROOT-Backups-VMlist.txt.$$ | \
  while read a
  do
    VM=`grep "$a" /tmp/ServROOT-Backups-VMlist.txt.$$ | awk '{print $1}'` 
    echo Compressing $a to $TO | tee -a $LOG
    PoweredOn
    gzip -c "$a" > ${TO}${a}.gz
  done
  else 
    PoweredOn
    VM=`grep -w $VM /tmp/ServROOT-Backups-VMlist.txt.$$ | cut -f5 -d "/"`
    echo Compressing $VM to $TO | tee -a $LOG 
    gzip -c "$a" > ${TO}${VM}.gz	 
  fi
}

# Umount the NFS datastore we stored all the backups in, if we mounted it
DismountNFS() {
  # Now unmount the NFS store if we mounted it
  if [ $NFSMOUNTED -eq 1 ]; then
    echo Dismounting NFS backup store /vmfs/volumes/$NFSStoreName | tee -a $LOG
    vim-cmd hostsvc/datastore/destroy $NFSStoreName
  fi
}

##############################################################################
# Main code starts here
##############################################################################

echo '=========================================================================='
echo '           S u U H M - E S Xi VM <-> M A C H I N E (C) 2014'
echo '=========================================================================='
echo '' | tee -a $LOG
echo '==========================================================================' >> $LOG
echo Datum der Durchfuehrung: $DATE | tee -a $LOG
echo '==========================================================================' >> $LOG
echo ''

# Process command-line arguments --help, --dobackup, --list and --zip
CommandLine $1 $2 $3

# Just List the VMs of ESXi Server
if [ $ListVM -eq 1 ]; then 
  ListVMIDs 
  cat /tmp/ServROOT-Backups-VMlist.txt.$$
  exit 0;
fi

###############################################################################
# Mount the NFS datastore we are backing up to 
MountNFS
cd /vmfs/volumes/datastore1 
# NOT NES > SnapshotVM

# Backup All machines
if [ $All -eq 1 ]; then 
  echo ''
  echo 'Alle Maschinen Werden durch Cron gebackupped:' | tee -a $LOG
  ListVMIDs
  VM="all"
  BackupDir
fi

# ZIP FILES
if [ $Compress -eq 1 ]; then 
  echo ''
  echo 'Bitte VM-Nr waehlen, die gebackupped werden soll (Oder alle):'
  ListVMIDs
  cat /tmp/ServROOT-Backups-VMlist.txt.$$
  echo all - ALle VMs auswaehlen!
  read VM 
  ZipIt  
fi

# Backup the VM or template, we have a list of most of the files already
if [ $DoBackup -eq 1 ]; then
  echo ''
  echo 'Bitte VM-Nr waehlen, die gebackupped werden soll (Oder alle):'
  ListVMIDs
  cat /tmp/ServROOT-Backups-VMlist.txt.$$
  echo all - ALle VMs auswaehlen!
  read VM 
  BackupDir
  #DeleteSnapshot
fi

# Clean up temporary file
rm -f /tmp/ServROOT-Backups.filelist.$$

###############################################################################

echo
date
echo Finished backup of $NFSServer 
echo ==========================================================================

# Now unmount the NFS store if we mounted it
DismountNFS

echo
echo Backup job finished at $(date +%Y-%m-%d' '%H:%M) | tee -a $LOG
echo '...'
sleep 1
echo Vorgang hat $(let eH=$(date +%H)-$sH;let eM=$(date +%M)-$sM;echo $eH:$eM) Minuten gedauert! | tee -a $LOG
# SENDING MAIL - EXPERIMENTAL
#cat $LOG | mail -s 'DCron ESXi' suhm@suuhm.info
#/usr/bin/SimpleMail/smail –a mysmpt.bar.com –s "Hello" –m "Hello world" suhm@suuhm.info

