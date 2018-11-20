#!/bin/bash

export PATH=/usr/bin:/bin:/usr/sbin/:/sbin:/opt/tss/bin:/opt/tss/itrs:/opt/tss/post.d:/opt/VRTSvcs/bin:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin

Env=`echo ${HOSTNAME:5:1}`
case $Env in
  p) RepoH=linuxks
      MirrH=dbvdev4124
      STOREAGEREPO=prod-storage.repo
      ;;
  *) RepoH=dbvdev4124
      MirrH=linuxks
      STOREAGEREPO=dev-storage.repo
      ;;
esac

VCSNODE=0
RACNODE=0
Prog=OSupgrade
fail_tag="\e[31m"
end_tag="\e[0m"
task_tag="\e[32m"
warn_tag="\e[33m"
OSMAJOR="$(lsb_release -rs|cut -f1 -d.)"
ARCH="$(uname -i)"
SUPPVCSVER="5.0.30.00 5.1.134.000 6.2.0.000 5.1.120.000 6.0.000.000 6.0.100.000 6.2.1.000"
Model="`dmidecode -s system-product-name | cut -f2 -d' '`"

TIMEOUT=/usr/bin/timeout
if [ ! -f $TIMEOUT ]; then
  TIMEOUT_SCRIPT=$(rpm -ql bash | grep scripts/timeout | head -1)
  if [ -f $TIMEOUT_SCRIPT ]; then
    TIMEOUT="/bin/bash $TIMEOUT_SCRIPT"
  else
    echo "No timeout command"
    exit 1
  fi
fi

Info () {
  echo -e "[Info]: $*" | tee -a $CHKSTATF
  rc=0
}

Warn () {
  echo -e "${warn_tag}[Warn]: $*${end_tag}" | tee -a $CHKSTATF
  rc=2
}

Task () {
  echo -e "${task_tag}[Task]: $* ${end_tag}"  | tee -a $CHKSTATF
  rc=0
}

Fail () {
  echo -e "${fail_tag}[Fail]: $*$end_tag" | tee -a $CHKSTATF
  rc=1
}

check_task_status () {
  if grep -q Fail $CHKSTATF ; then
      exit 1
  fi
  rm -f $CHKSTATF
}

status_file () {
  case "$1" in
    "create") touch $2 ;;
    "delete") rm -f $2 ;;
    "check" ) if [ -f "$2" ] ; then
                printf "[Skip]: $( echo $2 | cut -f2- -d-) already done.\n" | tee -a $CHKSTATF ; return 0
              else
                return 1
              fi
              ;;
    * ) echo unknown ;;
  esac
}



Usage () {
  echo "Usage : $0 [ -c <CR ref no> | -i <Repo ID> | -n|-u|-r|-v|-d ] [-x|-o]"
  echo -e "-n : Dry run/Test/check \n-u : OS upgrade\n-i : Repo ID\n-r : Rollback\n-v : Verify update\n-d : Delete snapshots\n"
  echo -e "Optional :\n-x : noreboot\n-o : ignore snapshot\n-j : Download packages in dry-run(ignore in upgrade)"
  echo -e "\nRHEL5 RepoIDs: 5.10.0.4-1.el5 / 5.10.6.17 / 5.10.7.17 / 5.10.9.17 / 5.10.10.17 / 5.10.02.18"
  echo -e "RHEL6 RepoIDs: 6.8.0.5-1.el6 / 6.8.7.17 / 6.8.9.17 / 6.9.10.17 / 6.9.01.18"
  echo -e "RHEL7 RepoIDs: 7.2.0.9-1.el7 / 7.2.7.17 / 7.4.9.17 / 7.4.10.17 / 7.4.01.18"
  exit 1
}

verchk () {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

check_kernel () {
  case $UpgRel in
    "5.10.6.17" ) LatestKrn=2.6.18-416.el5 ;;
    "5.10.0.4-1.el5" ) LatestKrn=2.6.18-418.el5 ;;
    "5.10.7.17" ) LatestKrn=2.6.18-420.el5;;
    "5.10.9.17"|"5.10.10.17" ) LatestKrn=2.6.18-423.el5;;
    "5.10.02.18" ) LatestKrn=2.6.18-426.el5;;
    "6.8.0.5-1.el6") LatestKrn=2.6.32-642.15.1.el6.x86_64 ;;
    "6.8.7.17" ) LatestKrn=2.6.32-696.6.3.el6.x86_64 ;;
    "6.8.9.17" ) LatestKrn=2.6.32-696.10.3.el6.x86_64 ;;
    "6.9.10.17" ) LatestKrn=2.6.32-696.13.2.el6.x86_64 ;;
    "6.9.12.17" ) LatestKrn=2.6.32-696.16.1.el6.x86_64 ;;
    "6.9.01.18" ) LatestKrn=2.6.32-696.18.7.el6.x86_64 ;;
    "7.2.0.9-1.el7") LatestKrn=3.10.0-514.10.2.el7.x86_64 ;;
    "7.2.7.17" ) LatestKrn=3.10.0-514.26.1.el7.x86_64 ;;
    "7.4.9.17" ) LatestKrn=3.10.0-693.2.2.el7.x86_64 ;;
    "7.4.10.17" ) LatestKrn=3.10.0-693.5.2.el7.x86_64 ;;
    "7.4.12.17" ) LatestKrn=3.10.0-693.11.1.el7.x86_64 ;;
    "7.4.01.18" ) LatestKrn=3.10.0-693.11.6.el7.x86_64 ;;
    "" ) Fail "repo id missing"; Usage ;;
    * ) Fail "No such repo id" ; Usage ;;
  esac

  if [ "$OSMAJOR" != "`echo ${UpgRel:0:1}`" ] ; then
    Fail "You are on $(lsb_release -sr) and provided wrong repoid" ; exit 1
  fi

  # Setup temp repo to check whether update require
  rm -f /tmp/temp-yum.conf
  wget -q http://10.193.30.196/${OSMAJOR}Server/repository/setup/temp-yum.conf -O /tmp/temp-yum.conf
  sed -i -e "s/RELEASE/$UpgRel/" -e "s/REPOSERVER/$RepoH/" /tmp/temp-yum.conf
  yum -c /tmp/temp-yum.conf check-update --disablerepo=* --enablerepo=*temp -x $EXCPKGS,java-\* -q >/dev/null 2>/dev/null
  if [ $? -eq 0 ] ; then
    Fail "Server already updated."
  else
    Info "OS update require"
  fi
  rm -f /tmp/temp-yum.conf
}

check_ntp () {
  Task "Syncing time. Wait for 5sec"
  service ntpd stop >/dev/null 2>&1
  ntpdate 10.193.59.10 >/dev/null 2>&1
  ntpdate 10.193.59.10 >/dev/null 2>&1
  service ntpd start >/dev/null 2>&1
  chkconfig ntpd on 2>/dev/null
  hwclock --systohc
  sleep 5

  if ! pidof ntpd > /dev/null ; then
    Fail "NTPD is not running"
  else
    Task "Time sync done"
  fi

}

check_prereq () {
  # check if /mnt is mounted. filesystem updat fails if /mnt mounted.
  if mountpoint -q /mnt ; then
    if [ $UPDATE -eq 0 ] ; then
      Warn "Un-mount /mnt filesystem. Will try unmount in upgrade phase"
    else
      if umount /mnt ; then
        Task "Un-mounted /mnt"
      else
        Fail "Failed to un-mount /mnt" ; exit 1
      fi
    fi
  fi

  # check for package-cleanup
  if ! rpm -q yum --changelog | grep -q 'Move --downloadonly' ; then
    if [ $OSMAJOR -eq 5 ] ; then
      YUMDOWNPKG=yum-downloadonly
    elif [ $OSMAJOR -eq 6 ] ; then
      YUMDOWNPKG=yum-plugin-downloadonly
    else
      YUMDOWNPKG=""
    fi
  fi

  REQRPM="yum-utils telnet $YUMDOWNPKG"
  for prerpm in $REQRPM ; do
    if ! rpm -q $prerpm >/dev/null 2>/dev/null ; then
      yum install $prerpm -q -y -e 0 --nogpgcheck 2>/dev/null
      if rpm -q $prerpm >/dev/null 2>/dev/null ; then
        Task "Installed pre-requisite pacakge - $prerpm"
      else
        Warn "Unable to install pre-requisite pacakge - $prerpm"
      fi
    fi
  done

  # Check if able to reach yum repository
  if [ -x /usr/bin/telnet ] ; then
    for rs in $RepoH ; do
      $TIMEOUT 10 telnet $rs  80 | grep -q 'Escape character is' >/dev/null 2>/dev/null
      if [ "$?" -eq 0 ] ; then
        Task "Repo server $rs connection good"
      else
        Fail "Unable to connect $rs"
      fi
    done
  else
    Warn "Unable to test repo connection"
  fi

}

check_rpmdb () {
  if rpm --verifydb >/dev/null 2>/dev/null ; then
    Info "RPM DB verified OK"
  else
    Fail "RPM DB verification failed"
  fi

  if [ -x /usr/bin/package-cleanup ] ; then
    DUPRPM=$(package-cleanup --dupes -q 2>/dev/null |wc -l)
    if [ "${DUPRPM:=0}" -gt 0 ] ; then
      Warn "Duplicate RPM found. Will Run \"package-cleanup --cleandupes\" during upgrade."
    else
      Info "No duplicate RPM found."
    fi
  else
    Fail "Missing yum-utils package"
  fi

  if [ $PKGDL -eq 1 ] && [ $DRYRUN -eq 1 ] ; then
  # Download RPM packages in advance
    cp -rp /etc/yum.repos.d $TMPdir/
    create_repofiles
    Info "Downloading require RPM files"
    rm -f $TMPdir/yum-download-sucess
    yum update --disablerepo=* --enablerepo=base,dell,errata -x $EXCPKGS,java-\* --downloadonly -y > $TMPdir/yum-download.log 2>&1
    if grep -q 'exiting because --downloadonly specified' $TMPdir/yum-download.log ; then
      Task "Downloaded required packages"
      touch $TMPdir/yum-download-sucess
    else
      Warn "yum downloadonly task failed. Verify $TMPdir/yum-download.log"
    fi

    rm -rf /etc/yum.repos.d
    mkdir /etc/yum.repos.d
    cp -rp $TMPdir/yum.repos.d/* /etc/yum.repos.d/
    rm -rf $TMPdir/yum.repos.d/
    rm -f $TMPdir/$Prog-create_repofiles
  fi
}

check_df () {
  if df -h > /dev/null 2>/dev/null ; then
    Info "df output clean"
  else
    Fail "There may be some hung Filesystem"
  fi
}

check_uptime () {
  Sec="$(cat /proc/uptime | grep -o '^[0-9]\+')"
  Min="$(($Sec / 60 ))"
  Hrs="$(($Min / 60 ))"

  if [ $Hrs -gt 4800 ] ; then
    Fail "Server uptime is more than 200 days"
  else
    Info "Server uptime is less than 200 days"
  fi
}

check_osupdate () {
  if yum --disablerepo=* --enablerepo=base,errata check-update -x ${EXCPKGS},java-\* -q > /dev/null 2>&1 ; then
    Info "Server is up-to-date. No further update require" ; exit 1
  else
    Info "Server update require"
  fi
}

check_freespace () {
  mp=$1
  sz=$2
  if mountpoint -q $mp ; then
    df -kP $mp | grep -v ^Filesystem |  awk 'BEGIN { out=0 }
    $4 < '"$sz"' {print "[Info]: Less than '"$sz"'KB space in "$6; out=1} END {exit out}'
  fi
}

check_rootspace () {
  #If not enough space in /, exit the job and notify
  let sp=0
  check_freespace /    1024000 || sp=1
  check_freespace /opt 1024000 || sp=1
  check_freespace /tmp 512000  || sp=1
  #check_freespace /opt/bmc 300000  || sp=1

  if [ -f $TMPdir/yum-download-sucess ] ; then
    check_freespace /var 512000 || sp=1
  else
    check_freespace /var 1024000 || sp=1
  fi

  if [ $sp -eq 1 ] ; then
    Fail "Need more free space ( 1GB in / /opt /var and 512MB in /tmp)"
  else
    Info "1GB Free space available in / /opt /var and 512MB in /tmp"
  fi
}

check_bootspace () {
  #If  not enough space in /boot , remove older kernel
  df -kP /boot | \
  awk 'BEGIN { out=0 } $6 ~/boot/ && $4 < 51200 {print "[Info]: Less than 50MB in "$6; out=1} END {exit out}'

  if [ $? -eq 1 ] ; then
    if [ $DRYRUN -eq 0 ] ; then
      Info "Checking and removing old kernels to clean up /boot"
      package-cleanup --oldkernels --count=1 -q -y > /dev/null 2>/dev/null
      df -kP /boot | \
      awk 'BEGIN { out=0 } $6 ~/boot/ && $4 < 51200 {print "[Info]: Couldnt free up space in "$6; out=1} END {exit out}'
      if [ $? -eq 1 ] ; then Fail "Not enough space in /boot for OS update" ; fi
    else
      Warn "Not enough space in /boot for OS update. Will try package-cleanup during upgrade"
    fi
  else
    Info "/boot got more than 50MB free"
  fi
}

check_mounts () {
  # check if all filesystems are mounted
  Info "Mount check exclude list - $EXCLUDEMP"
  stat=""
  #for part in `awk '$1 !~ /^#/ && $2 !~ /'"$EXCLUDEMP"'/ && $3 ~ /ext|nfs/ && $4 !~ /noauto/ {print $2 }' /etc/fstab`; do
  for part in `awk '$1 !~ /^#/ && $3 ~ /ext|nfs/ && $4 !~ /noauto/ {print $2 }' /etc/fstab | egrep -v "$EXCLUDEMP"`; do
    if ! mountpoint -q $part ; then
      stat="$stat $part"
    fi
  done

  if [ -n "$stat" ] ; then
    Fail "Missing mount $stat"
  else
    Info "All /etc/fstab fileSystems are mounted"
  fi
}

check_emc () {
  # check for EMC
  EMCUPDATE=0
  EXSAN=""
  EXCLUDEMP="/sysadmin|SECUPD"

  if rpm -q EMCpower.LINUX >/dev/null ; then
    wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/${STOREAGEREPO} -O /etc/yum.repos.d/storage.repo
    yum clean metadata >/dev/null 2>/dev/null
    export YUM0=${UpgRel}
    if [ $(yum repolist storage 2>/dev/null | awk '/^repolist/ {print $2}') -gt 0 ] ; then
      if yum -q list updates EMCpower.LINUX >/dev/null 2>&1 ; then
        Info "EMC package $(rpm -q EMCpower.LINUX) installed. Need update"
        EMCUPDATE=1
        EMCvgs=$(pvs -o pv_name,vg_name --noheadings | awk '/emcpower/ {print $2}')
        for vg in $EMCvgs ; do
          EXSAN="$(echo $EXSAN $(grep -v ^# /etc/fstab | grep $vg  | awk '{print $2}'|tr ' ' '\n')|tr ' ' '|')"
          OpenLV=$(lvs -o lv_attr,lv_path --noheadings $vg | grep 'wi-ao' |wc -l)
          if [ $OpenLV -gt 0 ] ; then
            Warn "Found open LV in $vg. It'll be un-mounted in upgrade phase"
          else
            Info "No open LV for EMC $vg"
          fi
        done

        EXCLUDEMP="${EXSAN}|${EXCLUDEMP}"
      else
        Info "EMC PowerPath updated"
        EMCUPDATE=0
      fi
    else
      Fail "Unable to see storage repo"
      EMCUPDATE=2
    fi
    rm -f /etc/yum.repos.d/storage.repo
  else
    Info "No EMC PowerPath installed."
  fi
}

check_coresize () {
  if mountpoint -q /var/crash ; then
    eval $(df -kP 2>/dev/null | awk '/\/var\/crash/ {print "CORESIZE="$2" COREFREE="$4 }')
    TOTALFREE=$(echo $COREFREE + $VGfree|bc)
    if [ "${TOTALFREE:=0}" -gt 10485760 ] && [ "${CORESIZE:=0}" -gt 3145728 ] ; then
      Warn "/var/crash can be reduced for snapshot"
      SNAPFREESP=2
    else
      Fail "Not enough space for snapshot"
      SNAPFREESP=1
    fi
  else
    Info "No separate /var/crash filesystem."
    Fail "Not enough space for snapshot"
  fi
}

reduce_corevol () {
  if status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" ; then
    Fail "Need more space in rootvg for snapshot"
    exit 1
  fi

  if [ ${SNAPFREESP:=3} -eq 1 ] ; then
    Fail "Not enough space to reduce /var/crash"
    exit 1
  fi

  if mountpoint -q /var/crash ; then
    COREVOL=$(df -hP /var/crash | awk '/^\/dev/ {print $1}')
    CORESIZE=$(lvdisplay $COREVOL -C --noheadings -o lv_size --units m 2>/dev/null  |cut -f1 -d.)

    if [ "$CORESIZE" -gt 2048 ] ; then
      creduce=0
      if umount /var/crash ; then
        if [ $OSMAJOR -lt 7 ] ; then
          e2fsck -fy $COREVOL 1>$TMPdir/core-resize.log 2>&1 || creduce=1
          resize2fs $COREVOL 2G >>$TMPdir/core-resize.log 2>&1 || creduce=1
          lvreduce -f -y -L 2G $COREVOL >>$TMPdir/core-resize.log 2>&1 || creduce=1
        else
          lvreduce -f -y -L 2G $COREVOL >>$TMPdir/core-resize.log 2>&1 || creduce=1
          mkfs.xfs -f $COREVOL >>$TMPdir/core-resize.log 2>&1 || creduce=1
        fi

        if [ $creduce -eq 0 ] ; then
          Task "Reduced /var/crash to 2GB"
          status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
          cp -p $TMPdir/$Prog-${FUNCNAME[ 0 ]} $BACKUPDIR/
        else
          Fail "Unable to reduce /var/crash to 2GB"
        fi
        mount /var/crash
        if [ $? -ne 0 ] ; then
          Fail "Failed to mount /var/crash"
        fi
      else
        Fail "Failed to umount /var/crash"
      fi
    else
      Info "/var/crash already at min size"
    fi
  else
    Info "No /var/crash filesystem"
    Fail "Need more space in rootvg for snapshot"
  fi
}

check_snapfreesp () {

  #Check free space for snapshot. No. of local mount x 2GB
  if [ $SNAPSHOT -eq 1 ] ; then
    Info "You chose to ignore OS filesystem snapshot"
    return 0
  fi

  if status_file check "$TMPdir/$Prog-create_snapshot" ; then
    Info "Skipped free space check for snapshot."
    return 0
  else
    #Check if older snaps still exits
    if lvs -a | grep -q ossnap ; then
      Fail "Older snaps still exits"
    else
      Info "No older snaps available"
    fi
  fi

  RootLV=$(df -P / | grep -v ^Filesystem | awk '{print $1}')
  RootVG=$(lvdisplay --noheadings -C -o vg_name $RootLV 2>/dev/null)
  VGfree=$(vgdisplay -C --noheadings -o vg_free $RootVG --units k 2>/dev/null |sed -e 's/\.[^.]*$//' -e 's/[kK]//')

  if [ "${VGfree:=0}" -lt 10485760 ] ; then
    check_coresize
  else
    Info "Free space available for snapshot"
    SNAPFREESP=0
  fi
}

check_path () {
  # check HDLM path
  if rpm -q HDLM >/dev/null ; then
    if /opt/DynamicLinkManager/bin/dlnkmgr view -path | grep sddlm | grep -qi offline ; then
      Fail "Some path Offline"
    else
      Info "All HDLM patch Online"
    fi
  fi

  # Check PowerPath
}

check_vcs () {
  if rpm -q VRTSvcs 1>/dev/null 2>&1 ; then
    VCSVER=$(rpm -q --qf "%{VERSION}\n" VRTSvcs 2>/dev/null)
    if echo $SUPPVCSVER | grep -q $VCSVER ; then
      Info "Supported VCS  installed"
      VCSNODE=1
    else
      Fail "Non-supported VCS installed. Do manual upgrade"
    fi
  fi

  #if rpm -qa | grep -q VRTSvxvm 1>/dev/null 2>&1 ; then
  #  Fail "OS upgrade not tested with VRTSvxvm"
  #fi
}

create_hostentry () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  LONG=`/bin/hostname -f`
  SHORT=`/bin/hostname -s`
  IP=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' |head -1`
  grep -q $IP /etc/hosts
  if [ $? -eq 1 ] ; then
    echo -e "${IP}\t${LONG} ${SHORT}" >> /etc/hosts
    Task "Added IP/Host in /etc/hosts"
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  fi
}

remove_omsa () {
  # Remove OMSA
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if rpm -q srvadmin-omilcore srvadmin-omacore >/dev/null ; then
    OMSAVER=$(omreport about|awk '/^Version/{print $3}')
    export YUM0=$UpgRel
    # Remove dependent packages
    rpm -q SCBmonitorSentry >/dev/null && \
      rpm -e SCBmonitorSentry >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    yum erase SCBbuild\* SCBtoolset\* -y > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1

    # Remove OMSA.
    /opt/dell/srvadmin/sbin/srvadmin-uninstall.sh -f >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    if [ $? -eq 0 ] ; then
      Task "Removed old OMSA packages"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Fail "Unable to remove old OMSA pacakages. Please remove manually"
    fi
  fi
}

create_etcbkp () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0
  # Backup /etc config files
  if [ -d $BACKUPDIR ] ; then
    if mv $BACKUPDIR $BACKUPDIR.$$ ; then
      Task "Old backup available. Renamed it to $BACKUPDIR.$$"
    else
      Fail "Failed to rename old backup.....Exiting" ; exit 1
    fi
  fi

  mkdir $BACKUPDIR && Task "Created backup directory $BACKUPDIR"
  if tar czf $BACKUPDIR/etc.tar.gz /etc 2>/dev/null ; then
    Task "Backup /etc files at $BACKUPDIR"
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  else
    Fail "/etc Backup fail. Fix it and then proceed"
  fi

  # md5sum status
  for File in $(find /etc -type f) ; do
    MD5VAL=$(grep -v ^# $File | md5sum | cut -f1 -d-)
    echo "${MD5VAL}${File}"
  done > $BACKUPDIR/etc-md5sum-nocomment && \
  Task "md5sum status of /etc files taken at $BACKUPDIR/etc-md5sum-nocomment"

  # rpm package list
  rpm -qa | sort > $BACKUPDIR/rpm-qa-list-before && \
  Task "rpm package list stored at $BACKUPDIR/rpm-qa-list-before"
  # mounted filesystem status
  mount | egrep ^/ > $BACKUPDIR/mount-status-before && \
  Task "mounted filesystem status stored at $BACKUPDIR/mount-status-before"
  # ip addr status
  ip addr | grep 'inet 10' > $BACKUPDIR/ip-addr-status-before && \
  Task "ip addr status stored at $BACKUPDIR/ip-addr-status-before"
  # store df output
  df -hP > $BACKUPDIR/df-hp-status-before
  # store status if corevol reduced
  [ -f $TMPdir/OSupgrade-reduce_corevol ] && cp -p $TMPdir/OSupgrade-reduce_corevol $BACKUPDIR/
  # Capture java version
  if [ -x /usr/bin/java ] ; then
    java -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;' > $BACKUPDIR/java-version-before
  fi
  # Capture TZ
  date +%Z > $BACKUPDIR/tz-before
}

save_biossetup () {
  # store biossetup
  output=$1
  if [ -x /opt/dell/srvadmin/bin/omreport ] ; then
    Info "Restarting OMSA with 120s timeout"
    $TIMEOUT 120 /opt/dell/srvadmin/sbin/srvadmin-services.sh restart > $TMPdir/omsa-restart-${output}.log 2>&1

    /opt/dell/srvadmin/bin/omreport chassis biossetup > $BACKUPDIR/biossetup-${output}
    if grep -q 'Serial Communication' $BACKUPDIR/biossetup-${output} ; then
      Task "Stored chassis biossetup settings"
    else
      Warn "Can't collect biossetup settings"
    fi
  fi
}

create_bootbkp () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if tar czf $BACKUPDIR/boot.tar.gz /boot 2>/dev/null ; then
    Task "Backup /boot files at $BACKUPDIR"
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  else
    Fail "/boot backup fail. Fix it and then proceed"; exit 1
  fi
}

create_patrolconfbkup () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if rpm -q SCBmonitorPatrol > /dev/null ; then

    if ! pidof PatrolAgent > /dev/null ; then
      if [ -f /etc/init.d/PatrolAgent ] ; then
        /etc/init.d/PatrolAgent start  > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      else
        /etc/init.d/patrolagent start  > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      fi
    fi

    if [ -f $TMPdir/`uname -n`_3181.cfg ] ; then rm -f $TMPdir/`uname -n`_3181.cfg ; fi

    if su - patrol -c "cd Patrol3 && . ./patrolrc.sh && pconfig -host `uname -n` -port 3181 +get +Defaults -save $TMPdir/`uname -n`_3181.cfg" ; then
      Task "Patrol configuration backup taken at $TMPdir/`uname -n`_3181.cfg"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Warn "Patrol configuration backup failed"
    fi
  else
   Info "No Patrol monitoring packages. skipping patrol backup"
  fi

  # Disable and delete agent history
  if [ -x /usr/adm/best1_default/bgs/bin/remoteHistoryConfig ] ; then
    /usr/adm/best1_default/bgs/bin/remoteHistoryConfig -n $(hostname -f) -D
  fi
}

stop_services ()
{
  # Stop patrol services
  if rpm -q SCBmonitorPatrol > /dev/null ; then
    if [ -f /etc/init.d/PatrolAgent ] ; then
      /etc/init.d/PatrolAgent stop  >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    else
      /etc/init.d/patrolagent stop  >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    fi

    if pidof PatrolAgent > /dev/null ; then
      Warn "Unable to stop PatrolAgent"
    else
      Task "Stopped PatrolAgent service"
    fi
  else
   Info "No Patrol monitoring packages. skipping patrol service stop"
  fi

  # stop Perform agent
  if rpm -q SCBmonitorPerform > /dev/null ; then
    if [ -f /etc/init.d/PerformAgent ] ; then
      /etc/init.d/PerformAgent stop >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    else
      /etc/init.d/PerformAgent stop >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    fi

    if pidof bgscollect > /dev/null ; then
      Warn "Unable to stop PerformAgent"
    else
      Task "Stopped PerformAgent service"
    fi
  else
    Info "SCBmonitorPerform is not installed"
  fi

  # stop OMSA
  if [ -x /opt/dell/srvadmin/sbin/srvadmin-services.sh ] ; then
    Info "Stopping OMSA services with 120s timeout"
    $TIMEOUT 120 /opt/dell/srvadmin/sbin/srvadmin-services.sh stop >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    if /opt/dell/srvadmin/sbin/srvadmin-services.sh status | grep dsm_ | grep -qi running ; then
      Warn "Unable to stop OMSA. Please check and kill"
    else
      Task "Stopped OMSA services"
    fi
  fi
}

create_sshkeybkup () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if [ ! -d $BACKUPDIR ] ; then
    Fail "No backup directory found" ; exit 1
  fi

  # Backup ssh host keys
  if rpm -q SCBopenssh >/dev/null 2>/dev/null ; then
    SSHKEYPATH=/usr/local/openssh/etc
  else
    SSHKEYPATH=/etc/ssh
  fi

  cd $SSHKEYPATH && md5sum *key* > $BACKUPDIR/sshkey_list
  if [ ! -d $BACKUPDIR/sshkeys ] ; then mkdir $BACKUPDIR/sshkeys ; fi
  cp -p $SSHKEYPATH/*key* $BACKUPDIR/sshkeys/
  if [ $? -eq 0 ] ; then
    Task "Backup ssh host keys done"
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  else
    Fail "Failed to backup ssh host keys.....Exiting" ; exit 1
  fi
}

remove_cfengine () {
#Stop cfengine if running and remove the package
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if rpm -q SCBcfeng >/dev/null ; then
    if yum erase SCBcfeng -q -y >$TMPdir/remove_cfengine.log 2>&1 ; then
      Task "Removed CFengine and dependent packages"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Fail "Unable to remove CFengine and dependent packages"
    fi
  else
    Info "CFengine is not installed"
  fi
}

create_repofiles () {
  # Point local repository to ${UpgRel}

  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  cd /etc/yum.repos.d/
  rename '.repo' '.preosupgraderepo' *.repo 2>/dev/null
  rename '.mirror' '.preosupgrademirror' *.mirror 2>/dev/null

  stat=0
  case $OSMAJOR in
    5)
      if grep -q YUM0 /etc/yum.conf ; then
        perl -i.bak -pe "s/YUM0=.*$/YUM0=${UpgRel}/g" /etc/yum.conf
      else
        sed -i.bak "/^plugins=/a\YUM0=${UpgRel}" /etc/yum.conf
      fi
      wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/base.repo || stat=1
      export YUM0=${UpgRel}
      ;;
    6|7)
      echo ${UpgRel} > /etc/yum/vars/release
      wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/base.repo || stat=1
      wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/optional.mirror || stat=1
      ;;
    *) Fail "Unknown version to download repo" ; exit 1
      ;;
  esac

  cd /etc/yum.repos.d/
  wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/base.mirror || stat=1
  wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/errata.mirror || stat=1
  wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/dell.mirror || stat=1
  wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/scbutils.mirror || stat=1

  if rpm -q EMCpower.LINUX >/dev/null ; then
    wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/${STOREAGEREPO} -O /etc/yum.repos.d/storage.repo || stat=1
  fi

  if [ $stat -eq 1 ] ; then Fail "Failed to download repository" ; exit 1;  fi

  # Remove mirror repo
  sed -i "s|^http://${MirrH}.*||g" /etc/yum.repos.d/*.mirror

  yum clean expire-cache metadata headers dbcache -q -e 0
  Task "Downloaded repository files"
  status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
}

create_gpgkeyfile () {
  # Download and Import GPG Keys

  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  UNIXENGKEY="http://${RepoH}/${RepoSt}/RPM-GPG-KEY-SCB-unixeng-release"
  DELLKEY="http://${RepoH}/${RepoSt}/DELL-RPM-GPG-KEY"
  CFYKEY="http://${RepoH}/${RepoSt}/RPM-GPG-KEY-centrify"

  if wget -q -T 30 --tries 2 ${UNIXENGKEY} -O /etc/pki/rpm-gpg/RPM-GPG-KEY-SCB-unixeng-release ; then
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-SCB-unixeng-release
    Task "Imported SCB Unixeng key"
  else
    Fail "Failed to import Unixeng GPG key.....Exiting" ; exit 1
  fi

  if wget -q -T 30 --tries 2 ${CFYKEY} -O /etc/pki/rpm-gpg/RPM-GPG-KEY-centrify ; then
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-centrify
    Task "Imported Centrify key"
  else
    Fail "Failed to import Centrify GPG key.....Exiting" ; exit 1
  fi

  if wget -q -T 30 --tries 2 ${DELLKEY} -O /etc/pki/rpm-gpg/DELL-RPM-GPG-KEY ; then
    rpm --import /etc/pki/rpm-gpg/DELL-RPM-GPG-KEY
    Task "Imported DELL GPG key"
  else
    Fail "Failed to import DELL GPG key.....Exiting" ; exit 1
  fi

  status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
}

umount_EMCfs () {
  if rpm -q EMCpower.LINUX >/dev/null ; then
    if [ $EMCUPDATE -eq 1 ] ; then
      Info "Un-mounting EMC filesystem for upgrade"
      EMCvgs=$(pvs -o pv_name,vg_name --noheadings | awk '/emcpower/ {print $2}')
      for vg in $EMCvgs ; do
        retcn=$(lvs -o lv_attr,lv_path --noheadings $vg | grep 'wi-ao' |wc -l)
        umtc=$retcn
        if [ $retcn -gt 0 ] ; then
          while [ $retcn -ne 0 ] ; do
            SanM=$(lvs -o lv_name --noheadings $vg)
            for mt in $SanM; do
              if mount | grep -qw /dev/mapper/${vg}-${mt}; then
                SanFS=$(mount | grep -w /dev/mapper/${vg}-${mt} | awk '{print $3}')
                if umount $SanFS 2>/dev/null ; then
                  Task "Un-mounted $SanFS"
                  let umtc=umtc-1
                else
                   Warn "Unable to un-mount $SanFS. Will retry $retcn more time"
                 fi
               fi
             done
             let retcn=retcn-1
           done
         fi
       done

       if [ $umtc -eq 0 ] ; then
         Task "Un-mounted EMC SAN filesystem"
       else
         Fail "Failed to un-mount EMC SAN filesystem"
         exit 1
       fi
     else
       Info "EMC PowerPath updated"
     fi
  fi
}

create_snapshot () {
  #Take local filesystem snapshot. If failed, exit the job.
  if [ $SNAPSHOT -eq 1 ] ; then
    Info "You chose to ignore snapshot"
    touch $BACKUPDIR/snapshot-omitted
    return 0
  fi

  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  case $SNAPFREESP in
    1) Fail "Not enough space for snapshot" ; exit 1;;
    2) reduce_corevol ;;
    0) Info "Creating snapshots" ;;
    *) Fail "Unable to check free space for snapshot" ; exit 1;;
  esac

  if [ "$OSMAJOR" -eq 5 ] ; then
    # update lvm packages
    yum clean expire-cache metadata headers dbcache -q -e 0
    export YUM0=$UpgRel

    if yum update lvm2 -y > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
      Task "LVM packages updated"
    else
      Fail "LVM package update failed" ; exit 1
    fi
  fi

  DIRS="/ /var /opt"

  let fscount=0
  FSMOUNT=""
  FSPATH=""
  for mnt in $DIRS; do
    if mountpoint -q  $mnt ; then
      FSPATH=$(df -P $mnt | awk '$1 !~ /Filesystem/ {print $1}')
      FSMOUNT="$FSMOUNT $FSPATH"
      let fscount=fscount+1
    fi
  done

  let snaps=0

  for Line in $FSMOUNT; do
    LVname=$(lvdisplay --noheadings -C -o lv_name $Line 2>/dev/null)
    LVpath=$(lvdisplay --noheadings -C -o path $Line 2>/dev/null)
    lvcreate -L 2500M -s -n ${LVname}ossnap $LVpath >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && let snaps=snaps+1
  done

  if [ "$snaps" -lt "$fscount" ] ; then
    Fail "Unable to create snapshot" ; exit 1
  else
    Task "snapshot created"
    sed -i 's/\ssnapshot_autoextend_threshold = .*/ snapshot_autoextend_threshold = 80/' /etc/lvm/lvm.conf
    if [ $? -eq 0 ] && service lvm2-monitor restart >/dev/null ; then
      Task "Updated lvm.conf for snapshot and Restarted lvm2-monitor service"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Fail "Failed to update lvm.conf or restart lvm2-monitor" ; exit 1
    fi
  fi
}

verify_SCBopenssh () {
  if rpm -q SCBopenssh-server >/dev/null 2>&1 ; then
    Warn "Legacy SCBopenssh packages installed. These packages will be removed and will be installed openssh."
    if [ "`tty`" != "/dev/tty1" ] ; then
      if [ -z "$STY" ] ; then
        Fail "Please run $0 either on console or inside screen" ; exit 1
      else
        Info "You are inside screen"
      fi
    else
      Info "You are on console."
    fi
  fi
}

remove_SCBopenssh () {
  # Remove legacy SCBopenssh packages and install openssh
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0
  if rpm -q SCBopenssh >/dev/null 2>&1 ; then
    Info "Removing SCBopenssh\* packages. SSH Session will be lost. Relogin in 1min"
    yum erase SCBopenssh\* -q -y >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 || rpm -e SCBopenssh-server --noscripts
    if [ $? -ne 0 ] ; then
      Fail "Unable to remove SCBopenssh pacakges. Please remove and install openssh manually"
      exit 1
    fi

    if yum install openssh\* -q -y >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
      service sshd start > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      Task "Removed SCBopenssh* and installed openssh* packages"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Fail "Unable to install openssh packages"
    fi
  else
    Info "No SCBopenssh* packages installed"
  fi
}

fix_duppkgs () {

  # Remove known duplicate pkgs
  DUPRPMNAME="rhnsd"
  for dpkg in $DUPRPMNAME ; do
    if [ `rpm -q $dpkg|wc -l` -gt 1 ];then
      rpm -e `rpm -q $dpkg |head -1` --noscripts && Task "Removed duplicate $dpkg"
    fi
  done

  # Remove other duplicate pkgs
  DUPRPM=0
  if [ -x /usr/bin/package-cleanup ] ; then
    DUPRPM=$(package-cleanup --dupes -q 2>/dev/null |wc -l)
    if [ "${DUPRPM}" -gt 0 ] ; then
      if [ "${DUPRPM}" -lt 11 ] ; then
        package-cleanup --cleandupes -y > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
        DUPRPM=$(package-cleanup --dupes -q 2>/dev/null |wc -l)
        if [ "${DUPRPM}" -gt 0 ] ; then
          Fail "Unable to remove duplicate RPM. Run \"package-cleanup --cleandupes\" with caution"
          exit 1
        else
          Task "Removed duplicate RPM packages"
        fi
      else
        Fail "More than 5 duplicate pacakges found. Run \"package-cleanup --cleandupes\" with caution"
        exit 1
      fi
    else
        Info "No duplicate RPM found."
    fi
  else
    Fail "Missing yum-utils package"
  fi
}

fix_SCBsudo () {
  # Check and remove SCBsudo package and install sudo
  if rpm -q SCBsudocfg >/dev/null ; then

    if cp -p /etc/sudoers /etc/sudoers.preupgrade && cp -rp /etc/sudo.d /etc/sudo.d.preupgrade ; then

      if [ $(rpm -qa |grep -c SCBsudo-) -gt 1 ] ; then
        if [ "$ARCH" == "i386" ] ; then
          rpm -e SCBsudo.x86_64 --noscripts
        else
          rpm -e SCBsudo.i386 --noscripts
        fi
      fi

      if yum erase SCBsudo SCBsudocfg -y >$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
        Task "Removed legacy SCBsudo* packages"
      else
        Fail "Unable to remove SCBsudo* packages"
        exit 1
      fi

      yum install sudo -y >>$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && Task "Installed sudo package"

      if rpm -q sudo >/dev/null ; then
        cp -pf /etc/sudoers.preupgrade /etc/sudoers
        cp -pf /etc/sudo.d.preupgrade/* /etc/sudo.d/
        chmod 0440 /etc/sudoers /etc/sudo.d/*
        Task "Removed SCBsudo* and installed sudo."
      else
        Fail "Missing sudo package"
        exit 1
      fi
    else
      Fail "Failed to copy sudo config files. Manually remove SCBsudo and install sudo"
      exit 1
    fi
  fi
}

fix_SCBrscd () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if [ $OSMAJOR -lt 7 ] ; then
    if rpm -q BladeLogic_RSCD_Agent >/dev/null 2>&1 && ! rpm -q SCBrscd-lin-pre-1.1.1-1.2.noarch 1>/dev/null 2>&1  ; then
      rpm -q SCBrscd-lin-pre-1.1.1-1.1.noarch >/dev/null 2>&1 && rpm -e SCBrscd-lin-pre-1.1.1-1.1.noarch --noscripts > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      rpm -Uvh --noscripts http://${RepoH}/${OSMAJOR}Server/repository/scbutils/SCBrscd-lin-pre-1.1.1-1.2.noarch.rpm >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      if [ $? -eq 0 ] ; then
        Task "SCBrscd dependency issue fixed"
        status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
      else
        Fail "SCBrscd dependency issue couldn't fix" ; exit 1
      fi
    else
      Info "No RSCD pacakge dependency issue"
    fi
  else
    Info "No RSCD fix for RHEL${OSMAJOR}"
  fi
}

fix_kernelboot () {
  isPAE=0
  uname -r | grep -q PAE && isPAE=1

  if [ $isPAE -eq 1 ] ; then
    if ! grep -q "^DEFAULTKERNEL=kernel-PAE$" /etc/sysconfig/kernel ; then
      sed -i 's/^DEFAULTKERNEL=.*/DEFAULTKERNEL=kernel-PAE/' /etc/sysconfig/kernel && \
        Task "Set DEFAULTKERNEL=kernel-PAE in /etc/sysconfig/kernel"
    fi
  else
    if ! grep -q "^DEFAULTKERNEL=kernel$" /etc/sysconfig/kernel ; then
      sed -i 's/^DEFAULTKERNEL=.*/DEFAULTKERNEL=kernel/' /etc/sysconfig/kernel && \
        Task "Set DEFAULTKERNEL=kernel in /etc/sysconfig/kernel"
    fi
  fi

  grep -q "^UPDATEDEFAULT=yes$" /etc/sysconfig/kernel || \
    sed -i 's/^UPDATEDEFAULT=.*/UPDATEDEFAULT=yes/' /etc/sysconfig/kernel && \
      Task "Set UPDATEDEFAULT=yes in /etc/sysconfig/kernel"
}

stop_vcs () {
  export PATH=$PATH:/opt/VRTSvcs/bin
  #If VCS node, evacute resources and stop
  if [ $VCSNODE -eq 1 ] ; then
    status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

    Info "VCS is installed on the node. Storing status at $BACKUPDIR/vcsinfo"
    mkdir -p $BACKUPDIR/vcsinfo
    hagrp -state > $BACKUPDIR/vcsinfo/hagrp-state
    hares -state > $BACKUPDIR/vcsinfo/hares-state
    gabconfig -a > $BACKUPDIR/vcsinfo/gabconfig-a
    lltstat -nvv > $BACKUPDIR/vcsinfo/lltstat-nvv
    cp -p /etc/lvm/lvm.conf $BACKUPDIR/vcsinfo/
    hastop -local -evacuate && Task "Stopped local VCS and evacuated resources"
    sleep 10
    killall CmdServer
    /etc/init.d/gab stop >/dev/null 2>/dev/null && Task "Stopped GAB"
    /etc/init.d/llt stop >/dev/null 2>/dev/null && Task "Stopped LLT"
    sed -i 's/^tags.*/#tags { hosttags = 1 }/' /etc/lvm/lvm.conf

    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}

  else
    Info "It's not a VCS node"
  fi
}

run_osupdate () {

  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  Info "Running OS update.....please wait"
  Info "Excluded pkgs from upgrade - ${EXCPKGS},java-\* and all SCB*"
  Info  "( You may check $TMPdir/${FUNCNAME[ 0 ]}.log for progress )"

  upstat=1
  yum clean expire-cache metadata headers dbcache -q -e 0

  # Remove srvadmin-jre
  if rpm -q srvadmin-jre > /dev/null 2>&1 ; then
    if yum erase srvadmin-jre -y -q >$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
      Task "Removed srvadmin-jre"
    else
      Warn "Unable to remove srvadmin-jre"
    fi
  fi

  case $OSMAJOR in
    5)
      export YUM0=$UpgRel
      # Remove legacy SCBopenssh and install openssh
      remove_SCBopenssh
      yum update --disablerepo=* --enablerepo=base,dell,errata -x ${EXCPKGS},java-\* -y >>$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
      ;;
    6|7)
      yum update --disablerepo=* --enablerepo=base,dell,errata,optional -x ${EXCPKGS},java-\* -y >>$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
      ;;
    *) Fail "Unknown version for OS upgrade" ; exit 1
      ;;
  esac

  if [ $upstat -eq 0 ] ; then
    Task "OS update completed"
    rm -f $TMPdir/yum-download-sucess
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  else
    Fail "OS update failed" ; exit 1
  fi

}

run_scbupdate () {

  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  Info "Running SCBbuild package update.....please wait"
  Info  "( You may check $TMPdir/${FUNCNAME[ 0 ]}.log for progress )"


  upstat=1
  yum clean expire-cache metadata headers dbcache -q -e 0

  if [ $OSMAJOR -eq 5 ] ; then export YUM0=$UpgRel ; fi

  if [ -f /opt/tss/post.d/SOURCE/md5sum_verify ] ; then
    SCBBuildPKG=$(rpm -qf /opt/tss/post.d/SOURCE/md5sum_verify --qf '%{NAME}')
  else
    SCBBuildPKG=""
  fi

  Loc=${HOSTNAME:0:2}
  case $Loc in
    pg|dg|hk) ATOS="-AO" ;;
    *) ATOS="" ;;
  esac

  if [ "$SCBBuildPKG"x == "x" ]; then
    if echo $Model | grep -q Virtual ; then
     yum --disablerepo=* --enablerepo=base,errata,scbutils install SCBbuild-OneE${ATOS} -y >$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
    else
     yum --disablerepo=* --enablerepo=base,errata,scbutils,dell install SCBbuild${ATOS} -y  > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
    fi
  else
    yum --disablerepo=* --enablerepo=base,errata,scbutils update $SCBBuildPKG -y >$TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
  fi

  if ! echo $Model | grep -q Virtual ; then
    # Install OMSA if removed earlier
    if ! rpm -q srvadmin-omcommon >/dev/null ; then
      yum --disablerepo=* --enablerepo=base,errata,scbutils,dell install srvadmin-omcommon srvadmin-racadm\* srvadmin-idracadm\* libsysfs -y >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    fi
  fi

  # Running scbbuild for selected modules
  SCBBUILDEXE=$(ls /opt/tss/post.d/scbbuild* |head -1)
  $SCBBUILDEXE -a setupSSH >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
  $SCBBUILDEXE -a setupYUM >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1

  # OFF SCBfirstboot if available
  if chkconfig --list SCBfirstboot > /dev/null 2>&1 ; then
    chkconfig SCBfirstboot off && \
    Task "Disable the SCBfirstboot service. Please enable and run if no deviation from standard"
  fi

  # Remove duplicate TMOUT entry
  if grep -q '^readonly TMOUT=900'  /etc/profile.d/SCBbuild-profile.sh 2>/dev/null ; then
    if egrep -q '^TMOUT=900' /etc/profile ; then
      sed -i.postupdate 's/^TMOUT=900.*//' /etc/profile
      Task "Removed duplicate TMOUT entry from /etc/profile"
    fi
  fi

  # Update repo ID
  if grep -q '^export YUM0=' /etc/profile.d/SCBbuild-profile.sh 2>/dev/null ; then
    sed -i "s/export YUM0=.*/export YUM0=${UpgRel}/" /etc/profile.d/SCBbuild-profile.sh
  fi

  if [ $upstat -eq 0 ] ; then
    Task "SCB package update completed"
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  else
    Fail "SCB package update failed" ; exit 1
  fi

}

run_rhrelupdate () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if [ -f /etc/yum/vars/release ] ; then
    echo $UpgRel > /etc/yum/vars/release
  else
    export YUM0=$UpgRel
  fi

  yum clean metadata -q 1>/dev/null 2>&1
  if yum -q -y update redhat-release\* > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
    Task "Updated redhat-release package"
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  else
    Warn "Unable to update redhat-release package"
  fi
}

run_scbrelesaeupdate () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if [ -f /etc/yum/vars/release ] ; then
    echo $UpgRel > /etc/yum/vars/release
  else
    export YUM0=$UpgRel
  fi

  yum clean metadata -q 1>/dev/null 2>&1

  upstat=1
    if rpm -q SCBrelease 1>/dev/null 2>&1 ; then
      yum --disablerepo=* --enablerepo=scbutils -q -y update SCBrelease > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
    else
      yum --disablerepo=* --enablerepo=scbutils -q -y install SCBrelease > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && upstat=0
    fi

    if [ $upstat -eq 0 ] ; then
      Task "Installed/Updated SCBrelease package"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Warn "SCBrelease package install/update failed"
    fi

}

run_emcupdate () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if [ $EMCUPDATE -eq 1 ] ; then
    if yum update EMCpower.LINUX -q --nogpgcheck -y > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
      /etc/init.d/PowerPath start
      Task "EMC PowerPath updated"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Warn "EMC PowerPath update failed"
    fi
  fi
}

check_fwupdate () {

  if echo $Model | grep -q Virtual ; then return ; fi

  BIOSUPDATE=0
  DRACUPDATE=0
  BIOSVER=$(dmidecode -s bios-version)
  DRACVER=$(racadm getversion |awk -F"=" '/DRAC/{print $2}')

  case $Model in
    R[67]10) BIOSFIX=""
              BIOSFL=""
              DRACFIX=""
              DRACFL=""
              ;;
    R[67]20) BIOSFIX=""
              BIOSFL=""
              DRACFIX=""
              DRACFL=""
              ;;
    R[67]30) BIOSFIX=2.7.1
              BIOSFL=BIOS_NMF8F_LN_2.7.1.BIN
              DRACFIX=2.50.50.50
              DRACFL=iDRAC-with-Lifecycle-Controller_Firmware_278FC_LN_2.50.50.50_A00.BIN
              ;;
    R[67]40) BIOSFIX=1.3.7
              BIOSFL=BIOS_MGGKF_LN_1.3.7.BIN
              DRACFIX=3.15.15.15
              DRACFL=iDRAC-with-Lifecycle-Controller_Firmware_VP4C2_LN_3.15.15.15_A00.BIN
              ;;
    * ) BIOSFIX="" ; BIOSFL="" ; DRACFIX="" ; DRACFL="";;
  esac

  if [ "$BIOSFIX"x == x ] ; then
    Warn "No BIOS fix available yet"
    return
  fi

  if [ $(verchk $DRACVER) -ge $(verchk $DRACFIX) ] ; then
    Info "DRAC is already updated"
  else
    DRACUPDATE=1
    Warn "DRAC update require"
  fi

  if [ $(verchk $BIOSVER) -ge $(verchk $BIOSFIX) ] ; then
    Info "BIOS fix already applied"
  else
    BIOSUPDATE=1
    Warn "BIOS fix require"
  fi
}

run_fwupdate () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  if echo $Model | grep -q Virtual ; then
    Info "Virtual server. Skipped BIOS update"
    return
  fi

  if [ $BIOSUPDATE -eq 0 ] ; then
    Info "BIOS update skipped"
    return
  fi

  rm -f /tmp/${DRACFL}
  wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/DELLBIOS/${DRACFL} -O /tmp/${DRACFL}
  chmod +x /tmp/${DRACFL}

  if [ -x /tmp/${DRACFL} ] ; then
    Info "Running DRAC update"
    /tmp/${DRACFL} -q > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1

    case $? in
      0) Task "DRAC update completed" ;;
      3) Warn "DRAC update may not require" ;;
      *) Warn "DRAC update failed." ;;
    esac
  else
    Warn "Missing DRAC BIN file"
  fi
    Info "Check DRAC update log at $TMPdir/${FUNCNAME[ 0 ]}.log"

  rm -f /tmp/${BIOSFL}
  wget -q -T 30 --tries 2 -c http://${RepoH}/${RepoSt}/DELLBIOS/${BIOSFL} -O /tmp/${BIOSFL}
  chmod +x /tmp/${BIOSFL}

  if [ -x /tmp/${BIOSFL} ] ; then
    Info "Running BIOS update"
    /tmp/${BIOSFL} -q >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1

    DSUret=$?

    case $DSUret in
      0) Task "BIOS update operation successful" ;;
      2) Task "Reboot require for successful BIOS update."
         status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]} ;;
      3) Warn "BIOS update may not require."
         status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]} ;;
      *) Warn "BIOS update failed."
    esac

    Info "Check BIOS update log at $TMPdir/${FUNCNAME[ 0 ]}.log"

  else
     Warn "Unable to download BIOS firmware"
  fi

}

vcs_patches () {
  if [ $VCSNODE -eq 1 ] ; then
    status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

    VCSVER=$(rpm -q --qf "%{VERSION}\n" VRTSvcs 2>/dev/null)
    #if [ "$VCSVER" == "6.2.0.000" ] ; then
    if [ $(verchk $VCSVER) -ge $(verchk "6.2.0.000") ] ; then
      # Restore lvm.conf for VCS
      if [ -f $BACKUPDIR/vcsinfo/lvm.conf  ] ; then
        rm -f /etc/lvm/lvm.conf
        cp -p $BACKUPDIR/vcsinfo/lvm.conf /etc/lvm/lvm.conf
      fi

      # Install VCS point paches
      Info "Doing VCS point patching"
      #VMNT=/tmp/vcspatch.$$
      VMNT=/mnt
      if mountpoint -q $VMNT ; then umount $VMNT ; fi
      #if [ ! -d $VMNT ] ; then mkdir $VMNT ; fi
      if mount 10.193.29.142:/jumpstart/Software $VMNT >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
        #cd $VMNT/Symantec/VRTS621 && ./installer  patches >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
        #cd $VMNT/Symantec/LinuxSource/VRTS621.P300 && \
        #sed "s/HostName/$HOSTNAME/" scb-vcs621.P300-upgrade > /tmp/scb-vcs621.P300-upgrade && \
        #./installSFHA621P3 -responsefile /tmp/scb-vcs621.P300-upgrade >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
        cd $VMNT/Symantec/LinuxSource/SFHA621/rhel6_x86_64
        sed "s/HostName/$HOSTNAME/" scb-vcs62to621p3.response > /tmp/scb-vcs62to621p3.response
        ./installmr -responsefile /tmp/scb-vcs62to621p3.response >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
        if [ $? -eq 0 ] ; then
          Task "VCS point paching completed. Verify $TMPdir/${FUNCNAME[ 0 ]}.log"
          status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
        else
          Warn "VCS point patching failed. Verify $TMPdir/${FUNCNAME[ 0 ]}.log"
        fi
      else
        Fail "Failed to install VCS point patches"; exit 1
      fi
    else
      Warn "Please use vcs_upgrade.sh script to update vcs"
    fi
  fi
}

restore_patrolconfbkup () {
  if [ -f $TMPdir/`uname -n`_3181.cfg ] ; then
    status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

    if ! pidof PatrolAgent > /dev/null ; then
      if [ -f /etc/init.d/PatrolAgent ] ; then
        /etc/init.d/PatrolAgent start  >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      else
        /etc/init.d/patrolagent start  >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      fi
    fi

    if su - patrol -c "cd Patrol3 && . ./patrolrc.sh && pconfig -host `uname -n` -port 3181 +Reload $TMPdir/`uname -n`_3181.cfg"; then
      Task "Patrol configuration restored back from $TMPdir/`uname -n`_3181.cfg"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Warn "Patrol configuration restore failed" ;
    fi
  else
    Info "No patrol configuration backup found."
  fi
}

restore_sshkey () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0
  if [ -d $BACKUPDIR ] ; then
    if [ "`ls -1 $BACKUPDIR/sshkeys|grep -c key`" -eq 6 ] ; then
      rm -f /etc/ssh/*key*
      cp -p $BACKUPDIR/sshkeys/*key* /etc/ssh
      cd /etc/ssh && md5sum *key* | diff - $BACKUPDIR/sshkey_list
      if [ $? -eq 0 ] ; then
        Task  "Restored ssh key successfully"
        status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
      else
        Warn  "Failed to restore ssh key. Restore from Tape backup"
      fi
    else
      Warn  "Backup ssh keys missing at $BACKUPDIR/sshkeys"
    fi
  else
    Warn "No pre-update backup found"
  fi
}

disable_ipv6 () {
  if [ $OSMAJOR -eq 5 ] ; then
  chkconfig ip6tables off
  sed -i.bak '/^alias ipv6 off/{h;s/alias ipv6 off/options ipv6 disable=1/};${x;/^$/{s//options ipv6 disable=1/;H};x}' /etc/modprobe.conf && Task "Updated /etc/modprobe.conf to disable ipv6"
  fi
}

restore_mpservice () {
  if rpm -q HDLM >/dev/null ; then
    status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

    /opt/DynamicLinkManager/bin/dlmupdatesysinit >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
    if [ $? -eq 0 ] ; then
      Task "HDLM sysinit restore successful"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Warn "HDLM sysinit restore failed"
    fi
  fi

  if rpm -q EMCpower.LINUX >/dev/null ; then
    if ! egrep -q '/etc/init.d/PowerPath start' /etc/rc.d/rc.sysinit ; then
      /etc/init.d/PowerPath start >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1
      if [ $? -eq 0 ] ; then
        Task "EMC PP sysinit restore successful"
      else
        Warn "EMC PP start up failed"
      fi
    fi
  fi

  # Enable netfs if _netdev mounts in fstab
  grep -v ^# /etc/fstab | grep -q _netdev && /sbin/chkconfig netfs on
}

reconfig_vmtools () {
if dmidecode -s system-product-name | grep -q VMware ; then
  if [ -x /usr/bin/vmware-toolbox-cmd ] && \
  /usr/bin/vmware-toolbox-cmd --version | grep -q 10.1.0.57774 ; then
    Info "VMware tool $(vmware-toolbox-cmd --version) installed"
    if ! pidof vmtoolsd >/dev/null ; then
      Task "Reconfiguring vmtool"
      if vmware-config-tools.pl -d >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
        Task "VMware tools reconfigured."
      else
        Warn "Failed to reconfigured vmware-tools. Try manually."
      fi
    else
      Info "VMtool up and running"
    fi
  else
    Info "Installing VMtools. Please wait"
    if wget -q -T 30 --tries 2 -O $TMPdir/VMwareTools-latest.tar.gz http://10.193.30.196/VMTOOLS/VMwareTools-latest.tar.gz ; then
      cd $TMPdir && tar -xzf $TMPdir/VMwareTools-latest.tar.gz
      cd vmware-tools-distrib/
      if ./vmware-install.pl -d -f >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 ; then
        Task "vmware-tools configured."
      else
        Warn "Failed to configured vmware-tools. Try manually."
      fi
    else
      Info "Unable to download vmware-tools. Try manually."
    fi
  fi
fi
}

install_vmtools () {
if dmidecode -s system-product-name | grep -q VMware ; then
  if [ -x /usr/bin/vmware-uninstall-tools.pl ] ; then
    Info "Removing older vmtools. please wait"
    /usr/bin/vmware-uninstall-tools.pl > $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && \
    Task "Removed older vmtools"
  fi

  if [ $OSMAJOR -gt 6 ] ; then
    if rpm -q open-vm-tools >/dev/null 2>&1 ; then
      yum update open-vm-tools -q -y >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && \
      Task "Updated open-vm-tools" || Warn "open-vm-tools update failed"
    else
      yum install open-vm-tools -q -y >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && \
      Task "Installed open-vm-tools" || Warn "open-vm-tools install failed"
    fi
    /bin/systemctl start vmtoolsd.service >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1

  else
    wget -q -T 30 --tries 2 -c http://dbvdev4124.uk.standardchartered.com/${OSMAJOR}Server/repository/vmtools/vmtools.repo -O /etc/yum.repos.d/vmtools.repo

    if rpm -q vmware-tools-esx-nox 1>/dev/null 2>&1 ; then
      yum update vmware-tools-esx-nox --enablerepo=vmtools -y -q >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && Task "Updated vmware-tools" || Warn "vmware-tools update failed"
    else
      yum install vmware-tools-esx-nox  --enablerepo=vmtools -y -q >> $TMPdir/${FUNCNAME[ 0 ]}.log 2>&1 && Task "Installed vmware-tools" || Warn "vmware-tools installation failed"
    fi
  fi

  if pgrep vmtoolsd >/dev/null ; then
    Task "VMware tools services running"
  else
    Warn "VMware tools services down"
  fi
fi
}

check_vmtools () {
if dmidecode -s system-product-name | grep -q VMware ; then
  if pgrep vmtoolsd >/dev/null ; then
    Task "VMware tools services running"
  else
    Warn "VMware tools services down"
  fi
fi
}

status_cleanup () {
  Task "Moving all status files"
  if [ ! -d $TMPdir/oldosupdate-$(date +%Y%m%d) ] ; then
    mkdir $TMPdir/oldosupdate-$(date +%Y%m%d)
  fi

  mv $TMPdir/OSupgrade-OSPatch-Status $TMPdir/$Prog-* $TMPdir/*.log $TMPdir/oldosupdate-$(date +%Y%m%d) 2>/dev/null
  cd $TMPdir/oldosupdate-$(date +%Y%m%d) && rename "OSupgrade" "$$_OSupgrade" OSupgrade* 2>/dev/null

  if [ "$ROLL" -eq 1 ] ; then
    rm -f $TMPdir/os-update-complete
  fi
}

do_reboot () {
  touch /var/log/schedule_reboot
  if [ $REBOOT -eq 0 ] ; then
    Task "Rebooting the server now"
    if [ $UPDATE -eq 1 ] ; then
      touch $TMPdir/os-update-complete
      Info "Please run \"$0 -c $CRref -v\" once server is up"
      Info "Please run \"$0 -c $CRref -r\" if you like to rollback"
    fi
    init 6
  else
    if [ $UPDATE -eq 1 ] ; then
      touch $TMPdir/os-update-complete
      Info "You opted for manual reboot. Please reboot and run \"$0 -c $CRref -v\" once server is up"
      Info "Please run \"$0 -c $CRref -r\" if you like to rollback"
    fi
  fi

}

fix_gangliaID () {
  #
  if rpm -q SCBganglia >/dev/null 2>&1 && ! id ganglia >/dev/null 2>&1 ; then
    eval $(awk -F: '$1 == "ganglia" {print "GaUID="$3 " GaGID="$4}' ${BACKUPDIR}/etc/passwd)
    groupadd -g ${GaGID:=389} ganglia 2>/dev/null && \
    useradd -u ${GaUID:=389} -g ${GaGID:=389} -c "Ganglia Monitoring System" -s /sbin/nologin -r -d  /home/ganglia ganglia 2>/dev/null
    if ! id ganglia >/dev/null 2>&1 ; then
      Fail "Failed to add ganglia id"
    else
      Task "Added back ganglia id"
    fi
  fi
}

switch_vcs () {
  if rpm -q VRTSvcs 1>/dev/null 2>&1 ; then

    status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

    if [ $(ps -aef|egrep -w 'had|hashadow' | grep -v grep|wc -l) -eq 2 ] ; then
      if [ -f $BACKUPDIR/vcsinfo/hagrp-state ] ; then
        ONSGS=`grep $HOSTNAME $BACKUPDIR/vcsinfo/hagrp-state | awk '$1 !~ /baseline|VCSNotifier/ && $4 ~ /ONLINE/ {print $1}'`
        for sg in $ONSGS ; do
          hagrp -switch $sg -to $HOSTNAME && Task "VCS resource switch back to $HOSTNAME"
        done

        status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}

      else
        Fail "Missing VCS status information"
      fi
    fi
  else
    Info "It's not a VCS node."
  fi
}

compare_outputs () {
  # Compare mount output before/after patching
  EXCLUDEMP="sysadmin|SECUPD"
  if sdiff -s <(sort $BACKUPDIR/mount-status-before) <(mount |awk '$1 ~ /^\// && $3 !~ /'"$EXCLUDEMP"'/ {print}' |sort) ; then
    Task "Mounted filesystems status before and after patching same"
  else
    Fail "Some missing mount/filesystem. Please verify"
  fi

  # Compare java version
  if [ -f $BACKUPDIR/java-version-before ] ; then
    java -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;' > $BACKUPDIR/java-version-after
    if [ `cat $BACKUPDIR/java-version-before` -eq `cat $BACKUPDIR/java-version-after` ] ; then
      Task "Java version matches major version"
    else
      Warn "Java version mismatch"
    fi
  fi

  # Compare ip output
  if sdiff -s <(sort $BACKUPDIR/ip-addr-status-before) <(ip addr | grep 'inet 10') ; then
    Task "All ip/s is/are available"
  else
    Fail "There is missing ip address. Please verify"
  fi

  # Compare TZ
  date +%Z > $BACKUPDIR/tz-after
  if sdiff -s $BACKUPDIR/tz-before $BACKUPDIR/tz-after ; then
    Task "Timezone matches"
  else
    Warn "Timezone doesn't matches"
  fi

  # Compare md5sum
  Info "Verifing md5sum status after OS upgrade"
  #cd $BACKUPDIR && tar xf etc.tar.gz
  MD5files="/etc/security/limits.conf /etc/sysctl.conf /etc/passwd /etc/group /etc/shadow /etc/resolv.conf /etc/ntp.conf /etc/ssh/sshd_config /etc/sysconfig/clock /etc/sudoers /etc/cron.allow /etc/security/access.conf /etc/pam.d/system-auth"
  EXCLUDECK="patrol|wireshark|operator|avahi|rpcuser|nfsnobody|ganglia"
  Info "(Plese note Ignore list $EXCLUDECK)"
  for File in $MD5files; do
    if [ -f ${BACKUPDIR}${File} ] ; then
      OLDMD5=$(egrep -v "$EXCLUDECK|^#" ${BACKUPDIR}${File} |md5sum | awk '{print $1}')
      NEWMD5=$(egrep -v "$EXCLUDECK|^#" ${File}|md5sum | awk '{print $1}')
      if [ "$OLDMD5" != "$NEWMD5" ] ; then
        Warn "$File md5sum differ"
        sdiff -s <(grep -vE "^\s*(#|$|$EXCLUDECK)" ${BACKUPDIR}${File}) <(grep -vE "^\s*(#|$|$EXCLUDECK)" ${File})
        echo
      else
        Task "$File md5sum match"
      fi
    fi
  done

  # Compare biossetup
  if [ -x /opt/dell/srvadmin/bin/omreport ] ; then
    if [ -f $BACKUPDIR/biossetup-beforepatch ] && [ -f $BACKUPDIR/biossetup-afterpatch ] ; then
      if sdiff -s $BACKUPDIR/biossetup-beforepatch $BACKUPDIR/biossetup-afterpatch ; then
        Task "Pre/Post OS patch BIOS settings same."
      else
        Warn "Pre/Post OS patch BIOS settings different"
      fi
    else
      Warn "Unable to check BIOS settings. Please verify manually"
    fi
  fi

  # compare cron entry
  if [ $OSMAJOR -lt 7 ] ; then
    for cru in $(egrep -v ^# /etc/cron.allow) ; do
      egrep -v ^# /etc/security/access.conf | grep -qw $cru
      if [ $? -ne 0 ] ; then
        Warn "Missing $cru from /etc/security/access.conf"
      fi
    done
  fi
}

# Rollback
check_rollback () {
  if [ "$(lvs -o lv_attr,lv_path --noheadings rootvg| awk '$1 ~ /swi-a-/ {print $2}' |wc -l)" -eq 0 ] ; then
    if [ -f $BACKUPDIR/snapshot-omitted ] ; then
      Info "snapshot omitted while OS update"
    fi
    Fail "No snapshot available for rollback" ; exit 1
  else
    Info "snapshots available for rollback"
  fi

  if [ ! -f $BACKUPDIR/boot.tar.gz ] ; then
    Fail "No /boot backup available."; exit 1
  else
    Info "/boot backup available"
  fi

}

vcs_rollback () {
  if rpm -q VRTSvcs 1>/dev/null 2>&1 ; then
    if [ $(ps -aef|egrep -w 'had|hashadow' | grep -v grep|wc -l) -eq 2 ] ; then
      Info "VCS is running on the node. Storing status at $ROLLBKDIR/vcsinfo"
      VCSNODE=1
      export PATH=$PATH:/opt/VRTSvcs/bin
      mkdir -p $ROLLBKDIR/vcsinfo || Fail "Fail to create VCS status backup dir"
      hagrp -state > $ROLLBKDIR/vcsinfo/hagrp-state
      hares -state > $ROLLBKDIR/vcsinfo/hares-state
      gabconfig -a > $ROLLBKDIR/vcsinfo/gabconfig-a
      lltstat -nvv > $ROLLBKDIR/vcsinfo/lltstat-nvv
      hastop -local -evacuate && Task "Stopped local VCS and evacuated resources"
      sleep 10
      killall CmdServer
      /etc/init.d/gab stop >/dev/null 2>/dev/null && Task "Stopped GAB"
      /etc/init.d/llt stop >/dev/null 2>/dev/null && Task "Stopped LLT"
    else
      Info "VCS is installed but not running. No status info stored"
    fi
  else
    Info "It's not a VCS node."
  fi
}

restore_boot () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0
  #Backup new /boot and restore old /boot
  if tar czf ${BACKUPDIR}/boot.new.tar.gz /boot >$TMPdir/os-rollback.log 2>$TMPdir/os-rollback.log ; then
    Info "Backup newer /boot at ${BACKUPDIR}/boot.new.tar.gz"
    rm -rf /boot/*
    if  cd /  &&  tar xzf $BACKUPDIR/boot.tar.gz  ; then
      Task "Restored old /boot files"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    else
      Fail "Rollback /boot failed. Restore from tape or new backup ${BACKUPDIR}/boot.new.tar.gz" ; exit 1
    fi
  else
    Fail "Failed to take backup of new /boot"; exit 1
  fi
}

restore_grub () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  stat=0
  case $OSMAJOR in
    5|6) GRBNAME=grub
      mv /boot/$GRBNAME/device.map /boot/$GRBNAME/device.map.bk || stat=1
    grub --device-map=/boot/$GRBNAME/device.map <<EOF >>$TMPdir/os-rollback.log 2>>$TMPdir/os-rollback.log || stat=1
root (hd0,0)
setup (hd0)
quit
EOF
      ${GRBNAME}-install /dev/sda >/dev/null 2>/dev/null || stat=1
      ;;
    7) GRBNAME=grub2
      ${GRBNAME}-install /dev/sda >/dev/null 2>/dev/null || stat=1
      grub2-mkconfig -o /boot/grub2/grub.cfg >>$TMPdir/os-rollback.log 2>>$TMPdir/os-rollback.log || stat=1
      ;;
    *) Fail "Unknown OS Version" ; exit 1 ;;
  esac

    if [ "$stat" -eq 1 ] ; then
      Fail "/boot ${GRBNAME}-install failed" ; exit 1
    else
      Task "/boot ${GRBNAME}-install done"
      status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
    fi

}

restore_snapshot () {
  status_file check "$TMPdir/$Prog-${FUNCNAME[ 0 ]}" && return 0

  # If /boot successful, mearge snapshots
  stat=0
  for Vol in $(lvs -o lv_attr,lv_path --noheadings rootvg| awk '$1 ~ /swi-a-/ && $2 ~ /ossnap/ {print $2}'); do
    lvconvert --merge $Vol >>$TMPdir/os-rollback.log 2>>$TMPdir/os-rollback.log || let stat=stat+1
  done

  if [ "$stat" -ne 0 ] ; then
    Fail "Failed to mearge all volumes" ; exit 1
  else
    Task "Merged all volumes"
    rm -f $TMPdir/os-update-complete
    status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
  fi
}

check_postosupdate () {
  if yum --disablerepo=* --enablerepo=base,errata check-update -x ${EXCPKGS},java-\* -q > /dev/null 2>&1 ; then
    Info "No pending update as per current repo"
  else
    Warn "Server update require"
  fi

  # Revert back old non-standard repo
  cd /etc/yum.repos.d
  rename '.preosupgraderepo'  '.repo' *.preosupgraderepo 2>/dev/null
  rename '.preosupgrademirror' '.mirror' *.preosupgrademirror 2>/dev/null
}


delete_snapshot () {
  # Delete snapshot
  SNAPS=$(lvs -o lv_attr,lv_path --noheadings rootvg| awk '$1 ~ /swi-a-/ && $2 ~ /ossnap/ {print $2}')
  if [ -n "$SNAPS" ] ; then
    for ss in $SNAPS ; do
      lvremove -f $ss >/dev/null 2>&1 && Task "Removed $ss" || Fail "Failed to remove $ss"
    done
  else
    Info "No snapshot available"
  fi
}

resize_corevol () {
  if [ -f $BACKUPDIR/OSupgrade-reduce_corevol ] ; then
    if [ -f $BACKUPDIR/df-hp-status-before ] ; then
      eval $( awk '/\/var\/crash/ {print "COREVOL="$1 " SIZE="$2 " FS="$6}' $BACKUPDIR/df-hp-status-before)
      crezie=0
      if umount /var/crash ; then
        if [ $OSMAJOR -lt 7 ] ; then
          e2fsck -fy $COREVOL 1>$TMPdir/post-core-resize.log 2>&1 || crezie=1
        else
          xfs_repair $COREVOL 1>$TMPdir/post-core-resize.log 2>&1 || crezie=1
        fi
        lvresize -f -r -L $SIZE $COREVOL >>$TMPdir/post-core-resize.log 2>&1 || crezie=1
        mount /var/crash || crezie=1

        if [ $crezie -eq 0 ] ; then
          Task "Resize /var/crash to $SIZE"
          status_file create $TMPdir/$Prog-${FUNCNAME[ 0 ]}
        else
          Fail "Unable to resize /var/crash to $SIZE"
        fi
      else
        Warn "Unable to resize /var/crash"
      fi
    else
      Watn "df output missing. Unable to compare /var/crash"
    fi
  else
    Info "/var/crash wasn't reduced. No resizing /var/crash"
  fi
}

# Main
UPDATE=0
ROLL=0
VERIFY=0
CLEANUP=0
DRYRUN=0
REBOOT=0
SNAPSHOT=0
UpgRel=""
PKGDL=0

if [ "$(mount | awk '$3 == "/tmp" {print $5}')" == "tmpfs" ] ; then
  TMPdir=/var/tmp
else
  TMPdir=/tmp
fi

case $OSMAJOR in
  5) EXCPKGS="jdk,OpenIPMI-2.0.16-99.dell,redhat-release-5Server,syslog-ng" ;;
  6|7) EXCPKGS="jdk,syslog-ng,redhat-release-server,srvadmin-jre" ;;
  * ) Fail "Unknown OS version" ; exit 1 ;;
esac

CHKSTATF=$TMPdir/$Prog-OSPatch-Status
rm -f $CHKSTATF

while getopts "c:i:urvdnxoj" opt;do
  case $opt in
    c) CRref=$OPTARG ; BACKUPDIR=$TMPdir/preupgrade.${CRref};;
    i) UpgRel=$OPTARG ;;
    u) UPDATE=1 ;;
    r) ROLL=1 ; ROLLBKDIR=$TMPdir/prerollback.${CRref} ;;
    v) VERIFY=1 ;;
    d) CLEANUP=1; BACKUPDIR=$TMPdir/preupgrade.${CRref};;
    n) DRYRUN=1; BACKUPDIR=$TMPdir/preupgrade.${CRref};;
    x) REBOOT=1 ;;
    o) SNAPSHOT=1 ;;
    j) PKGDL=1 ;;
    *) Usage ;;
  esac
done

RepoDir=${OSMAJOR}Server/${UpgRel}/$ARCH
RepoSt=$RepoDir/setup


if [[ "$CRref" && "$UPDATE" -eq 0 && "$ROLL" -eq 0 && "$VERIFY" -eq 0 && "$CLEANUP" -eq 0 && "$DRYRUN" -eq 1 ]] ; then
  Info "Doing pre-OSUpgrade check only"
  check_kernel
  verify_SCBopenssh
  check_prereq
  check_uptime
  check_rpmdb
  check_path
  check_vcs
  check_rootspace
  check_bootspace
  check_emc
  check_mounts
  check_snapfreesp
  check_fwupdate
  check_task_status
  #
elif [[ "$CRref" && "$UpgRel" && "$UPDATE" -eq 1 && "$ROLL" -eq 0 && "$VERIFY" -eq 0 && "$CLEANUP" -eq 0 && "$DRYRUN" -eq 0 ]] ; then
  if [ -f $TMPdir/os-update-complete ] ; then
    Info "OS update already completed"
    exit 1
  fi

  [ -f $TMPdir/run_osupdate.log ] && mv $TMPdir/run_osupdate.log $TMPdir/run_osupdate.log.$$
  Info "OS will be upgraded to $UpgRel"
  check_kernel
  verify_SCBopenssh
  check_ntp
  check_prereq
  check_uptime
  check_rpmdb
  check_path
  check_vcs
  check_rootspace
  check_bootspace
  check_emc
  check_mounts
  check_snapfreesp
  check_fwupdate
  check_task_status
  #
  umount_EMCfs
  create_etcbkp
  save_biossetup beforepatch
  create_bootbkp
  create_patrolconfbkup
  stop_services
  create_sshkeybkup
  remove_cfengine
  create_gpgkeyfile
  create_hostentry
  if [ $OSMAJOR -eq 5 ] ; then remove_omsa ; fi
  create_repofiles
  create_snapshot
  #
  fix_duppkgs
  fix_SCBsudo
  fix_SCBrscd
  fix_kernelboot
  stop_vcs
  run_osupdate
  run_scbrelesaeupdate
  run_rhrelupdate
  if [ "$ARCH" == "x86_64" ] ; then run_scbupdate ; fi
  run_emcupdate
  #run_fwupdate
  vcs_patches
  #
  restore_mpservice
  restore_patrolconfbkup
  restore_sshkey
  disable_ipv6
  install_vmtools
  do_reboot
elif [[ "$CRref" && "$UPDATE" -eq 0 && "$ROLL" -eq 1 && "$VERIFY" -eq 0 ]] ; then
  # Rollback
  if [ ! -d $BACKUPDIR ] ; then Fail "No OS upgrade backup found"; exit 1; fi
  check_rollback
  vcs_rollback

  case $OSMAJOR in
    6|7)
      restore_boot
      restore_grub
      restore_snapshot
      status_cleanup
      do_reboot
      ;;
    *)
      Info "RHEL5 rollback is manual."
      status_cleanup
      ;;
  esac

elif [[ "$CRref" && "$VERIFY" -eq 1 && "$ROLL" -eq 0 && "$UPDATE" -eq 0 ]] ; then
  # Verify
  if [ ! -f $TMPdir/os-update-complete ] ; then
    Fail "OS update haven't completed"
    exit 1
  fi

  if [ ! -d $BACKUPDIR ] ; then Fail "No OS upgrade done yet."; exit 1; fi

  if [ ! -f $BACKUPDIR/etc.tar.gz ] ; then Fail "No pre /etc backup found." ; exit 1 ; fi

  cd $BACKUPDIR
  if ! tar xf etc.tar.gz ; then Fail "Unable to extract /etc backup for verification" ; exit 1 ;fi

  check_ntp
  save_biossetup afterpatch
  fix_gangliaID
  switch_vcs
  compare_outputs
  check_mounts
  #reconfig_vmtools
  check_vmtools
  check_postosupdate
  check_fwupdate
  status_cleanup
elif [[ "$CRref" && "$VERIFY" -eq 0 && "$ROLL" -eq 0 && "$UPDATE" -eq 0 && "$CLEANUP" -eq 1 && "$DRYRUN" -eq 0 ]] ; then
  if [ -d $BACKUPDIR ] ; then
    delete_snapshot
    resize_corevol
  else
    Fail "No OS backup dir found"
  fi
else
  Usage
fi
