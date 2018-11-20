#!/bin/bash
#
## Script to reboot ECI hosts
##   /opt/tss/bin/reboot_prod.sh
##
## Script will check for hardware errros, if found report them and exit out.
## Script will send out notification six hours before the change window starts.
## PSS can stop the reboot, by touching either /apps/stop.boot or /ion/stop.boot
##
## Script will check for the file and if found will exit out.
##

PATH=$PATH:/usr/bin:/usr/sbin:/bin:/sbin
LOCK="/apps/stop.boot /ion/stop.boot"
REBOOT=`which reboot`
RECIP="admin@example.com"
MINUTES="m"
Host=`uname -n`

outputs () {
        ##
        # collecting Needed outputs
        ##
        LOG_DIR=/var/tmp/outputs

        ### XXX DANGER: someone could point a symlink where you don't want it.
        ### FIXME: this should reside in /root/tmp or similar
        [ ! -d ${LOG_DIR} ] && mkdir -p ${LOG_DIR}
        cd ${LOG_DIR}
        df -h | wc -l > df.wc.b4
        netstat -rn | wc -l > netstat.wc.b4
}
#
#
check_locked () {
        ##
        # Check for existence of any lock files. Skip reboot if there are outstanding hardware issues.
        ##
        for LOCKFILE in ${LOCK} ; do
               if [ -f "${LOCKFILE}" ] ; then
                       echo "Lock file ${LOCKFILE} exists, the server `hostname` will not be rebooted this week" \
                       | mailx -s "`hostname` monthly reboot: SKIPPED" "${RECIP}"

                       clean_locked
                       /usr/bin/mysql --defaults-extra-file=/etc/db.conf -e "UPDATE sysboot  SET Status='Cancelled_lock' WHERE host like '$Host';"
                       exit 1
               fi
        done
        return 0
}
#
clean_locked () {
        ##
        # Check for existence of any lock files and clean up.
        ##
        for LOCKFILE in ${LOCK} ; do
               if [ -f "${LOCKFILE}" ] ; then
                        rm -rf $LOCKFILE
               fi
        done
}

#
hw_health () {
        ##
        # Check hardware health. Skip reboot if there are outstanding hardware issues.
        ##
        PATH=$PATH:/usr/sbin:/sbin:/bin:/usr/bin:/opt/dell/srvadmin/bin ; export PATH
        HEALTH_OUTPUT=$(mktemp)
        echo "Check immediately to see if this is a valid hardware issue:" > "${HEALTH_OUTPUT}"
        /opt/tss/bin/scbtools.py --show-hardware \
        | egrep "CPU|PS|Disk|eth" | egrep -v "Capacity|Processor|Connected|Disa" \
        | grep -v Ok >> "${HEALTH_OUTPUT}" \
        || omreport chassis memory | grep Status | egrep -v "Ok|Unknown" >> "${HEALTH_OUTPUT}"

        if [ $? -eq 0 ] ; then
               cat "${HEALTH_OUTPUT}" \
               | mailx -s "`hostname` monthly reboot: SKIPPED, possible hardware problem" "${RECIP}"

               # where does this output go? cron will spool to $MAILTO which is whom?
               #echo "The Server will not be rebooted today, looks like hardware problem"
               /usr/bin/mysql --defaults-extra-file=/etc/db.conf -e "UPDATE sysboot  SET Status='Cancelled_Hardware_issue' WHERE host like '$Host';"
               exit 1
        fi
}
#
#
Notification () {
        ##
        # Check if we're locked. Otherwise, delay 15 - 45 minutes, then sleep 5 hours
        ##

        check_locked

        # PSSBAU-1616: We want to reboot a maximum of 6 servers per rack at a time.
        # To do this we will randomly sleep over a 30 minute interval.

        POWER_SPREAD=$(expr $RANDOM / 1093)
        echo Power spread $POWER_SPREAD
        sleep ${POWER_SPREAD}${MINUTES}

        MINUTES_REMAIN=300

        echo "Host `hostname` will be rebooted at `date -d '+6 hour'` " \
        | mailx -s "`hostname` monthly reboot: SCHEDULED" "${RECIP}"

        sleep 60${MINUTES}
        while [ "${MINUTES_REMAIN}" -gt 40 ] ; do
               check_locked
               let MINUTES_REMAIN=MINUTES_REMAIN-60
               sleep 60${MINUTES}
        done
}

Restart () {

        check_locked

        echo "Host `hostname` is now rebooting." \
        | mailx -s "`hostname` monthly reboot: REBOOTING" "${RECIP}"
        DATE=`date +'%m/%d/%Y %H:%M:%S'`
        /usr/bin/mysql --defaults-extra-file=/etc/db.conf -e "UPDATE sysboot  SET bootstart='$DATE', Status='Rebooting' WHERE host like '$Host';"
        $REBOOT
}

enable_informer() {

        cnt=`cat /etc/redhat-release | grep -i Maipo |wc -l`

        if [ $cnt -eq 0 ]
        then
           ln -s /opt/tss/bin/validate_boot.sh /etc/rc3.d/S99informer.sh
        else
           chmod 755 /etc/rc.local
           systemctl start rc-local.service
           echo "/opt/tss/bin/validate_boot.sh" >>/etc/rc.local
        fi

}

hw_health
outputs
Notification
enable_informer
Restart

