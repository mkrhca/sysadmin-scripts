#!/bin/bash
####Checkout host post scheduled reboot and Update central host #####
##Collect system status
PATH=$PATH:/usr/bin:/usr/sbin:/bin:/sbin

/opt/tss/bin/scbtools.py -c >/tmp/.xxstate
sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" /tmp/.xxstate >/tmp/.state
UPTIME=`uptime | cut -d',' -f 1 | cut -d 'p' -f 2-`

date=`date +'%d/%m/%Y %H:%M:%S'`
Host=`uname -n`
LOG=/var/log/s2bxboot.log
DELLRESTART=/opt/dell/srvadmin/sbin/srvadmin-services.sh
DellChk=/opt/dell/srvadmin/bin/omreport

dellcheck()
{
        sleep 180
        dellproccount=`ps -ef | grep dell |wc -l`
        if [ $dellproccount -gt 5 ]
        then
                echo "[OK] Dell Services" >>$LOG
        else
                $DELLRESTART restart
                sleep 10
        fi
}

checks()
{
        mkdir /tmp/validate
        for i in `ls -1 /root/sysstate/pre`
        do
                if [ $i == 'mount.b4' ]
                then
                        cat /root/sysstate/pre/$i | grep -v autofs | sort >/tmp/validate/$i
                else
                        cat /root/sysstate/pre/$i | sort >/tmp/validate/$i
        fi
        done
        for i in `ls -1 /root/sysstate/post`
        do
                if [ $i == 'mount.current' ]
                then
                        cat /root/sysstate/post/$i | grep -v autofs | sort >/tmp/validate/$i
        else
                        cat /root/sysstate/post/$i | sort >/tmp/validate/$i
        fi
        done



        cpucnt=`diff /tmp/validate/cpu.b4 /tmp/validate/cpu.current |wc -l`
        cpuout=`diff /tmp/validate/cpu.b4 /tmp/validate/cpu.current`
        memcnt=`diff /tmp/validate/memory.b4 /tmp/validate/memory.current |wc -l`
        memout=`diff /tmp/validate/cpu.b4 /tmp/validate/cpu.current`
        kernelbootcnt=`diff /tmp/validate/kernelboot.b4 /tmp/validate/kernelboot.current |wc -l`
        kernelbootout=`diff /tmp/validate/kernelboot.b4 /tmp/validate/kernelboot.current`
        pcicnt=`diff /tmp/validate/pci.b4 /tmp/validate/pci.current |wc -l`
        pciout=`diff /tmp/validate/pci.b4 /tmp/validate/pci.current`
        swapcnt=`diff /tmp/validate/swap.b4 /tmp/validate/swap.current |wc -l`
        swapout=`diff /tmp/validate/swap.b4 /tmp/validate/swap.current`
        #niccnt=`diff /tmp/validate/nic.b4 /tmp/validate/nic.current |wc -l`
        #nicout=`diff /tmp/validate/nic.b4 /tmp/validate/nic.current`
        diskcnt=`diff /tmp/validate/disk.b4 /tmp/validate/disk.current |wc -l`
        diskout=`diff /tmp/validate/disk.b4 /tmp/validate/disk.current`
        netstatcnt=`diff /tmp/validate/netstat.b4 /tmp/validate/netstat.current |wc -l`
        netstatout=`diff /tmp/validate/netstat.b4 /tmp/validate/netstat.current`
        kernelcnt=`diff /tmp/validate/kernel.b4 /tmp/validate/kernel.current |wc -l`
        kernelout=`diff /tmp/validate/kernel.b4 /tmp/validate/kernel.current`
        mountcnt=`diff /tmp/validate/mount.b4 /tmp/validate/mount.current  |wc -l`
        mountout=`diff /tmp/validate/mount.b4 /tmp/validate/mount.current`

        NICFail=`$DellChk chassis nics|egrep "Name|Status" | grep Disconnected`
        if [ "$NICFail" != "" ]; then
                nic=Fail
                nicout=$NICFail
        else
                nic=Pass
                nicout="No issues"
        fi

        HalfDuplex=`/opt/tss/bin/scbtools.py --show-nic-status | grep eth | awk '{print $5}' | grep -v Full | grep Half`
        if [ "$HalfDuplex" != "" ]; then
                line=`/opt/tss/bin/scbtools.py --show-nic-status | grep -i half`
                nicduplex=Fail
                nicduplexout=$HalfDuplex

        else
                nicduplex=Pass
                nicduplexout="No issues"
        fi

        if [ -f /proc/net/bonding/bond0 ]; then
                SLAVES=`cat /proc/net/bonding/bond0 | grep "Slave Interface" | wc -l`
                if [ "$SLAVES" -lt 2 ]; then
                        nicbond=Fail
                        nicbondout="Bond has only one interface"
                else
                        nicbond=Pass
                        nicbondout="No issues"
                fi
        fi

        if [ -f /proc/net/bonding/bond0 ]; then
                UP_SLAVES=`cat /proc/net/bonding/bond0 | grep "MII Status: up" | wc -l`
                if [ "$UP_SLAVES" -lt 3 ]; then
                        nicbonddown=Fail
                        nicbonddownout="one of the interface in bond is down"
                else
                        nicbonddown=Pass
                        nicbonddownout="No issues"
                fi
        fi

        if [ $cpucnt -gt 0 ]
        then
                cpu=Fail
        else
                cpu=Pass
                cpuout="No issues"
        fi

        if [ $memcnt -gt 0 ]
        then
                mem=Fail
        else
                mem=Pass
                memout="No issues"
        fi

        if [ $kernelbootcnt -gt 0 ]
        then
                kernelboot=Fail
        else
                kernelboot=Pass
                kernelbootout="No issues"
        fi

        if [ $pcicnt -gt 0 ]
        then
                pci=Fail
        else
                pci=Pass
                pciout="No Issues"
        fi

        if [ $swapcnt -gt 0 ]
        then
                swap=Fail
        else
                swap=Pass
                swapout="No issues"
        fi


        if [ $diskcnt -gt 0 ]
        then
                disk=Fail
        else
                disk=Pass
                diskout="No issues"
        fi

        if [ $netstatcnt -gt 0 ]
        then
                netstat=Fail
        else
                netstat=Pass
                netstatout="No issues"
        fi

        if [ $kernelcnt -gt 0 ]
        then
                kernel=Fail
        else
                kernel=Pass
                kernelout="No issues"
        fi


        if [ $mountcnt -gt 0 ]
        then
                mount=Fail
        else
                mount=Pass
                mountout="No issues"
        fi

        sleep 240

        ntpoffsetout=`/usr/sbin/ntpq -pn | /usr/bin/awk 'BEGIN { offset=900 } $1 ~ /^\*/ { offset=$9 } END { print offset }'`
        ntppeerout=`/usr/sbin/ntpq -pn | egrep -c '^\*|^\+'`

        if [ $(echo "$ntpoffsetout > 900" | bc) -ne 0 ] || [ $(echo "$ntpoffsetout < -900" | bc) -ne 0 ]
        then
                 ntpoffset=Fail
        else
                ntpoffset=Pass
        fi


        if [ $ntppeerout -lt 3 ]
        then
                sleep 120
                ntppeerout=`/usr/sbin/ntpq -pn | egrep -c '^\*|^\+'`
                if [  $ntppeerout -lt 3 ]
                then
                        ntppeer=Fail
                fi
                else
                        ntppeer=Pass
                fi

        flg=`cat /etc/redhat-release | egrep -i "Maipo|Santiago" |wc -l`

        if [ $flg -eq 0 ]
        then
                cstat=`cat /proc/acpi/processor/*/info | grep "power management" | grep -i yes | wc -l`
                powerout=`cat /proc/acpi/processor/*/info | grep "power management" | grep -i yes | awk '{print $NF}' | head -1`
                if [ $cstat -gt 0 ]
                then
                        power=Fail
                else
                        power=Pass
                fi
        else
                cstat=`cat /sys/module/intel_idle/parameters/max_cstate`
                powerout=`cat /sys/module/intel_idle/parameters/max_cstate`

                if [ $cstat -eq 0 ]
                then
                        power=Pass
                else
                        Power=Fail
                fi

        fi

        HTen=`/opt/tss/bin/cpu-core-count.ksh | grep CPU | egrep -i "yes|no" | awk '{print $NF}' | grep -i yes |wc -l`
        HTenabledout=`/opt/tss/bin/cpu-core-count.ksh | grep CPU | egrep -i "yes|no" | awk '{print $NF}'  | head -1`
        if [ $HTen -gt 0 ]
        then
                HTenabled=Fail
        else
                HTenabled=Pass
        fi

        $DellChk chassis biossetup >/tmp/.bios
        bcountm=`grep "C States" /tmp/.bios | wc -l`
        if [ $bcountm -eq 0 ]
        then
                 bcountm1=`grep -i "C1-E" /tmp/.bios | egrep -i "disabled|enabled" | wc -l`
                 if [ $bcountm1 -eq 0 ]
                 then
                        bcounto=`grep -A1 "C1-E" /tmp/.bios | grep -iv "disabled" | wc -l`
                        biosstates=`grep -A1 "C1-E" /tmp/.bios | tail -1 `
                 else
                        bcount=`egrep -i "C1-E|Processor C State Control" /tmp/.bios | grep -vi disabled | wc -l`
                        biosstates=`grep -i "C1-E" /tmp/.bios`
     fi
     else
                bcount=`grep "C States" /tmp/.bios  | grep -vi disabled |wc -l `
                biosstates=`grep "C States" /tmp/.bios`
     fi

    if [[ $bcount -gt 0 || $bcounto -gt 1 ]]
    then
       bios="Fail"
       biosout="C States Enabled"
   else
       bios=Pass
       biosout="No issues"
   fi




        rm -rf /tmp/validate

        /usr/bin/mysql --defaults-extra-file=/etc/db.conf -e "UPDATE sysboot  SET cpu  = '$cpu',Status = '$date', kernelboot= '$kernelboot', mem='$mem', pci='$pci', swap='$swap', nic='$nic', disk='$disk', netstat='$netstat', kernel='$kernel', mount='$mount', ntpoffset='$ntpoffset', ntppeer='$ntppeer', power='$power', HT='$HTenabled', bios='$bios', nicbonddown='$nicbonddown', nicbond='$nicbond', nicduplex='$nicduplex', uptime='$UPTIME', Status='Rebooted',cpuout='$cpuout', kernelbootout='$kernelbootout', memout='$memout', pciout='$pciout', swapout='$swapout', nicout='$nicout', nicbonddownout='$nicbonddownout', nicbondout='$nicbondout', nicduplexout='$nicduplexout', biosout='$biosout', diskout='$diskout', netstatout='$netstatout', kernelout='$kernelout', mountout='$mountout', ntpoffsetout='$ntpoffsetout', ntppeerout='$ntppeerout', powerout='$powerout',HTout='$HTenabledout'  WHERE host like '$Host';"

        cnt=`cat /etc/redhat-release | grep -i Maipo |wc -l`

        if [ $cnt -eq 0 ]
        then
                rm -rf /etc/rc3.d/S99informer.sh
        else
                cat /etc/rc.local | grep -v validate_boot >/tmp/rc.loc
                cp /tmp/rc.loc /etc/rc.local
        fi
}


dellcheck
checks
