#!/bin/bash
#
# Manoj Kumar U 
# Script to update ntp.conf for NY4, PR, WF and LD5
# Usage:
#       To migrate: ntp_migrate.sh -s <site> -m
#       To rollback: ntp_migrate.sh -s <site> -r
#               - site should be one of NY4, PR, WF, LD5
#               - ONLY one of -r or -m to be supplied

# Define variables
## PR NTPs
PR_1=10.193.93.246
PR_2=10.193.93.250
PR_3=10.193.95.4
PR_4=10.193.95.5
PR_5=10.221.20.21
PR_6=10.221.20.22
## NY4 NTPs
NY4_1=10.177.149.51
NY4_2=10.177.149.52
NY4_3=10.177.144.4
NY4_4=10.177.144.4
## LD5 NTPs
LD5_1=10.221.20.21
LD5_2=10.221.20.22
LD5_3=10.193.59.10
LD5_4=10.193.59.11
LD5_5=${PR_1}
LD5_6=${PR_2}
## Watford NTPs
WF_1=10.221.20.21
WF_2=10.221.20.22
WF_3=10.193.59.10
WF_4=10.193.59.11
WF_5=${PR_1}
WF_6=${PR_2}

# Define functions
usage()
{
        echo "ERROR: Incorrect usage"
        echo "Usage: $0 -s <site> [-m|-r]"
        echo "  => site can be any one of PR, WF, LD5 or NY4"
        echo "  => Either -m or -r mandatory. Use -m for migration (or) -r for rollback"
        exit 1
}

check_update()
{
        if grep -q 'release.*5\.' /etc/redhat-release > /dev/null 2>&1
        then
                for i in 1 2 3 4
                do
                        if ! grep -q "^server.*${site}_${i}[[:space:]].*" /etc/ntp.conf
                        then
                                return 1
                                break
                        fi
                done
        else
                for i in 1 2 3 4
                do
                        if ! grep -q "^server.*${site}_${i}[[:space:]].*iburst.*" /etc/ntp.conf
                        then
                                return 1
                                break
                        fi
                done
        fi
}


mig()
{
        site=$1
        if ! check_update
        then
                # Backup config
                echo "[INFO]: Backing up ntp.conf"
                cp -p /etc/ntp.conf /etc/ntp.conf.$(date +%s)

                # Stop ntp
                echo "[INFO]: Stopping ntp"
                PID=($/sbin/pidof ntpd)
                if /etc/init.d/ntpd stop > /dev/null 2>&1
                then
                        if ! ps -ef | grep "^ntp.*${PID}.*/var/run/ntpd.pid.*" > /dev/null 2>&1
                        then
                                echo "[INFO]: NTP stopped"
                        else
                                echo "[ERROR]: NTP not terminated successfully. Manual intervention required."
                                exit 1
                        fi

                        # Verify that ntp.conf has only 2 server entries
                        if ! grep -c ^server /etc/ntp.conf | grep 2 > /dev/null
                        then
                                echo "ERROR: ntp.conf does not have exactly 2 server entries. Manual intervention required"
                                exit 1
                        fi

                        # Update ntp.conf
                        echo "[INFO]: Updating ntp.conf"
                        if grep -q 'release.*5\.' /etc/redhat-release > /dev/null 2>&1
                        then
                                sed -i -e "s/^server.*${site}_3/server ${Site}_2 # ${site} Secondary NTP\n&/" -e "s/^server.*${site}_3/server ${site}_1 # ${site} Primary NTP\n&/" /etc/ntp.conf
                                touch /tmp/.mig_ntp_ok
                        else
                                sed -i -e "s/^server.*${site}_3/server ${Site}_2 iburst # ${Site} Secondary NTP\n&/" -e "s/^server.*${site}_3/server ${site}_1 iburst # ${site} Primary NTP\n&/" /etc/ntp.conf
                                touch /tmp/.mig_ntp_ok
                        fi
                else
                        echo "[ERROR]: NTP not terminated successfully. Manual intervention required."
                        exit 1
                fi
        else
                echo "INFO: NTP already updated"
                exit 1
        fi
}

rbk()
{
        site=$1
        FILE=$(ls -ltr /etc/ntp.conf* | grep -v conf$ | tail -1 | awk '{print $NF}')
        if ls touch /tmp/.mig_ntp_ok > /dev/null 2>&1
        then
                cp -p ${FILE} /etc/ntp.conf
        fi
}


migrate=FALSE
rollback=FALSE
while getopts ms:r opt
do
        case $opt in
        s) site=$OPTARG ;;
        m) migrate=TRUE;;
        r) rollback=TRUE ;;
        *) echo "ERROR: Unknown option"; exit 1 ;;
        esac
done

[ -z "$site" ] && usage
[ "$migrate" == "TRUE" -a "$rollback" == "TRUE" ] && usage
[ "$migrate" == "FALSE" -a "$rollback" == "FALSE" ] && usage

case $site in
NY4)
        if ! echo ${HOSTNAME} | grep -q ^us > /dev/null 2>&1
        then
                echo "ERROR: Incorrect site"
                usage
        fi
        ;;
PR)
        if ! echo ${HOSTNAME} | grep -q '^uk.*a$' > /dev/null 2>&1
        then
                echo "ERROR: Incorrect site"
                usage
        fi
        ;;

WF)
        if ! echo ${HOSTNAME} | grep -q '^uk.*b$' > /dev/null 2>&1
        then
                echo "ERROR: Incorrect site"
                usage
        fi
        ;;
LD5)
        if ! echo ${HOSTNAME} | grep -q '^uk.*c$' > /dev/null 2>&1
        then
                echo "ERROR: Incorrect site"
                usage
        fi
        ;;
*)
        echo "ERROR: Incorrect site"
        usage
        ;;
esac


if [ "$migrate" == "TRUE" -a ! -z "$site" ]
then
        [ "$rollback" == "FALSE" ] && mig $site
fi

if [ "$rollback" == "TRUE" -a ! -z "$site" ]
then
        [ "$migrate" == "FALSE" ] && rbk $site
fi
