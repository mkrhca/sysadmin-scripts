#!/bin/bash
#
# Script to update create /opt/bmc/SCBmon & install SCBmon - stat gathering tool for Linux
# Usage:
#       To install: deploy_scbmon.sh -i -c <CR>
#       To rollback: deploy_scbmon.sh -r -c <CR>
#               - Mandatory: -c <CR>
#               - Mandatory: ONLY one of -r or -i to be supplied.
#

export PATH=$PATH:/sbin:/usr/sbin:/bin:/usr/bin

usage()
{
        echo "ERROR: Incorrect usage"
        echo "Usage: $0 [-i|-r] -c <CR>"
        echo "  => -c <CR> mandatory."
        echo "  => Either -i or -r mandatory. Use -i for installation (or) -r for rollback."
        exit 1
}

basic_check () {
if [ `uname -s` != Linux ]
then
eecho "[info]: Not a Linux server"
exit 1
fi
}

setup_fs()
{
# Check if user already exists and create it does not exist.
if ! egrep "^scbmonlc:" /etc/passwd > /dev/null ; then
    if grep ":x:18562201:" /etc/passwd > /dev/null ; then
       echo "[error]: UID 18562201 Already in USE, Please manually add SCBmon user and retry package install"
       exit 255
    else
       /usr/sbin/useradd -o -u 18562201 -g users -c "SCBmon TSS unix" -p 'NP' -m -d /opt/tss/SCBmon -s /bin/bash scbmonlc && echo "[info]: scbmonlc user created"
           passwd -x -1 scbmonlc >/dev/null 2>&1
    fi
fi

FSNAME="/opt/bmc/SCBmon"
LVNAME="/dev/mapper/rootvg-scbmonlv"
VGFREE=`vgs rootvg --options vg_free --noheading --unit G | cut -d. -f1`

if [ ! -b $LVNAME ]; then
   if [ $VGFREE -lt 1 ]; then
       echo "[error]: No free space in rootvg to create SCBmon volume. Proceeding with SCBmon install on /opt/bmc"
   else
        if [ "$(ls -A $FSNAME >/dev/null 2>&1)" ]; then
                 mv $FSNAME $FSNAME.$$
        fi
        mkdir -p $FSNAME
      echo "[info]: Creating $LVNAME"
      lvcreate rootvg -n scbmonlv -L1G

      echo "[info]: Formating $LVNAME"
      mke2fs -j $LVNAME -L $FSNAME >/dev/null 2>&1
      if [ $? -eq 0 ]
      then
                        echo "[info]: Updating fstab entries"
                        cp /etc/fstab /etc/fstab.pre${CR}
                        echo -e "$LVNAME\t$FSNAME\text3\tdefaults\t1 2\n" >> /etc/fstab

                        echo "[info]: Mounting $LVNAME"
                        mount $FSNAME
                        chown scbmonlc:users $FSNAME
                        chmod 0755 $FSNAME
                        echo "[info]: $FSNAME created.Proceeding with SCBmon install"
      else
                        if [ -b /dev/mapper/rootvg-scbmonlv ]
                        then
                lvremove -f /dev/mapper/rootvg-scbmonlv
                echo "[info]: $FSNAME not created"
                        fi
                fi
   fi
else
   echo "[info]: $LVNAME exist. Proceeding with SCBmon install"
fi
}


fs_size_check () {
        THRESHOLD=80
        DF="df -Pkl"
    for i in `$DF /opt/bmc/SCBmon|grep -v '^Filesystem'|awk '{if (NF == 5) {print $4 $5} else {print $5 $6}}'|grep -v "^$"`
    do
        PERCENT=`echo $i|cut -d% -f1`
        FILESYS=`echo $i|cut -d% -f2`
        if [ $PERCENT -gt $THRESHOLD ]
        then
            echo "[error]: $FILESYS is $PERCENT % full.. Please check before proceeding"
                        exit 4
        else
                        echo "[info]: $FILESYS usage is below threshold.Proceeding..."
        fi
    done
}

check_pkg () {

os_ver=`lsb_release -r |awk -F":" '{print $2}'|xargs|awk -F'.' '{print $1}'`
if [ $os_ver -eq 5 ]
then
export YUM0=5.10.0.4.el5
fi

ins_pkg=0
yum list available SCBmon  >/dev/null 2>&1
if [ $? -eq 0 ]
then
        echo "[info]: SCBmon pkg is avaialble in yum. Proceeding with installation"
                ins_pkg=1
else
        echo "[error]: Could not find SCBmon pkg in yum. Need Manual Intervention"
                exit 1
fi
}


install_pkg () {

CR=$1
basic_check
setup_fs
fs_size_check
check_pkg

if [ $ins_pkg -eq 1 ]
then
        os_ver=`lsb_release -r |awk -F":" '{print $2}'|xargs|awk -F'.' '{print $1}'`
        if [ $os_ver -eq 5 ]
        then
                export YUM0=5.10.0.4.el5
        fi
#install SCBmon
        yum -y install SCBmon >/dev/null 2>&1
        if [ $? -eq 0 ]
        then
                        count=`ps -ef | grep scbmonlc|grep -v grep| wc -l`
                        if [ $count -eq 6 ]
                        then
                        echo "[info]: SCBmon successfully installed and started"
                        else
                        echo "[warning]: SCBmon installed but not started fully"
                        fi
            else
                        echo "[error]: SCBmon not installed. Need manual intervention"
                fi
fi
}

rollback()
{

CR=$1
basic_check

if rpm -q SCBmon >/dev/null 2>&1
then
        service scbmon stop
        if [ -b /dev/mapper/rootvg-scbmonlv ]
        then
                umount /opt/bmc/SCBmon
                lvremove -f /dev/mapper/rootvg-scbmonlv
                sed -i '/\/dev\/mapper\/rootvg-scbmonlv/d' /etc/fstab
                echo "[info]: Removed /opt/bmc/SCBmon"
                rpm -e SCBmon >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                        echo "[info]: SCBmon successfully uninstalled"
                else
                        echo "[error]: SCBmon could not be uninstalled. Need manual intervention"
                fi
        else
                rpm -e SCBmon >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                        echo "[info]: SCBmon successfully uninstalled"
                else
                        echo "[error]: SCBmon could not be uninstalled. Need manual intervention"
                fi
        fi
else
        if [ -b /dev/mapper/rootvg-scbmonlv ]
        then
                umount /opt/bmc/SCBmon
                lvremove -f /dev/mapper/rootvg-scbmonlv
                sed -i '/\/dev\/mapper\/rootvg-scbmonlv/d' /etc/fstab
                echo "[info]: Removed /opt/bmc/SCBmon"
        fi
        echo "[info]: SCBmon is not installed"
        exit 0
fi
}

inst=FALSE
rollback=FALSE
CR=""
while getopts ic:r opt
do
        case $opt in
        c) CR=$OPTARG ;;
        i) inst=TRUE;;
        r) rollback=TRUE ;;
        *) usage ;;
        esac
done


[ -z "$CR" ] && usage
[ "$inst" == "TRUE" -a "$rollback" == "TRUE" ] && usage
[ "$inst" == "FALSE" -a "$rollback" == "FALSE" ] && usage

if [ "$inst" == "TRUE"  -a ! -z "$CR" ]
then
        [ "$rollback" == "FALSE" ] && install_pkg ${CR}
fi

if [ "$rollback" == "TRUE" -a ! -z "$CR" ]
then
        [ "$inst" == "FALSE" ] && rollback ${CR}
fi
