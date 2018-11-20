#!/bin/bash

#
# Manoj Kumar U 
# Script to add/remove /apps/stop.boot
# Usage:
#       To stop monthly reboot: schedule_reboot_ctrl.sh -n -s <site> -b <batch no>
#       To schedule monthly reboot: schedule_reboot.sh -y -s <site> -b <batch no>
#               - site should be one of PROD or DR
#               - batch no should be 1 or 2. For DR, only batch 1 exists
# prod batch 1 - all FX servers except LD5, PR and NY4 management servers
# prod batch 2 - all eRates servers and LD5 servers including LD5 management servers
# DR - All Watford servers

exit 0
SSH="ssh -n -q -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10"
CONFIG=/apps/pss/current/config/release.config
TEST_HOST=/tmp/test_host.$$
CREATE_LOCK=/tmp/create_lock.$$
REMOVE_LOCK=/tmp/remove_lock.$$
TEST_LOCK=/tmp/test_lock.$$
UPTIME_CHECK=/tmp/uptime_check.$$
MSGFILE=/tmp/msgfile.$$
> ${MSGFILE}

echo 'hostname > /dev/null 2>&1' > ${TEST_HOST}
echo 'touch /apps/stop.boot > /dev/null 2>&1 && echo "${HOSTNAME} - SKIPPED" || echo "${HOSTNAME} - FAILED"' > ${CREATE_LOCK}
echo 'rm /apps/stop.boot > /dev/null 2>&1' > ${REMOVE_LOCK}
echo 'ls /apps/stop.boot > /dev/null 2>&1 && echo "${HOSTNAME} - FAILED" || echo "${HOSTNAME} - SCHEDULED"' > ${TEST_LOCK}
cat > ${UPTIME_CHECK} <<EOF
printf "\${HOSTNAME} - \$(uptime | awk -F'( |,|:)+' '{print \$6,\$7",",\$8,"hours,",\$9,"minutes."}')\n"
EOF


# Define functions
usage()
{
        echo "ERROR: Incorrect usage"
        echo "Usage: $0 -s <site> <-y|-n> -b <batch no>"
        echo "  => -s <site> mandatory. site can be any one of PROD or DR"
        echo "  => -b <batch no> mandatory. batch no can be one of 1 or 2. For DR, only batch 1 exist"
        echo "  => Either -y or -n mandatory. Use -y for scheduling reboot (or) -n to stop scheduling monthly reboot"
        echo "  => -r for reporting. This flag is optional"
        exit 1
}

user_check()
{
  if [ "${USER}" != "lynxprod" ]
  then
    echo "ERROR: Script should be executed as lynxprod"
    exit 1
  fi
}

run()
{
  # 1 - site, 2 - side, 3 - appserver, 4 - asset, 5 - env, 6 - reb
  local site=$1
  [ "${site}" == "-" ] && site=
  local side=$2
  [ "${side}" == "-" ] && side=
  local appserver=$3
  [ "${appserver}" == "-" ] && appserver=
  local asset=$4
  [ "${asset}" == "-" ] && asset=
  local env=$5
  [ "${env}" == "-" ] && env=
  local reb=$6
  [ -z "${reb}" ] && reb=FALSE
  local server=$7
  [ ! -z ${server} ] && i=$server
  local CONFIG=/apps/pss/current/config/release.config

  check()
  {
        if [ "${reb}" == "FALSE" ]
        then
          ${SSH} ${i} 2> /dev/null $(<${TEST_HOST})
          if [ $? -ne 0 ]
          then
              echo "${i} - UNABLE TO SSH"
              continue 2> /dev/null
          fi
          ${SSH} ${i} 2> /dev/null $(<${CREATE_LOCK})
        else
          ${SSH} ${i} 2> /dev/null $(<${TEST_HOST})
          if [ $? -ne 0 ]
          then
              echo "${i} - UNABLE TO SSH"
              continue 2> /dev/null
          fi
          ${SSH} ${i} 2> /dev/null $(<${REMOVE_LOCK})
          ${SSH} ${i} 2> /dev/null $(<${TEST_LOCK})
        fi
  }

  rep()
  {
     ${SSH} ${i} 2> /dev/null "hostname > /dev/null 2>&1"
     if [ $? -ne 0 ]
     then
        echo "${i} - UNABLE TO SSH" >> ${MSGFILE}
        continue 2> /dev/null
     fi
     ${SSH} ${i} 2> /dev/null $(<${UPTIME_CHECK}) >> ${MSGFILE}
  }

  if [[ -z ${server} && "${REPORT}" == "FALSE" ]]; then
    grep "^host.*site=${site}.*side=${side}.*appserver=${appserver}.*asset=${asset}.*env=${env}" ${CONFIG} | awk '{print $1}' | cut -d= -f2| while read i
    do
      check
    done
  elif [[ -z ${server} && "${REPORT}" == "TRUE" ]]; then
    grep "^host.*site=${site}.*side=${side}.*appserver=${appserver}.*asset=${asset}.*env=${env}" ${CONFIG} | awk '{print $1}' | cut -d= -f2| while read i
    do
      rep
    done
  elif [ "${REPORT}" == "TRUE" ]; then
    rep
  else
    check
  fi
}

send_mail()
{
  sed -i -e 's#^#<p>#' -e 's#$#</p>#' ${MSGFILE}
  sed -i '1iTo: admin@example.com' ${MSGFILE}
  sed -i "2iSubject: Monthly Reboot - Uptime Status for ${site} batch ${batch} servers" ${MSGFILE}
  sed -i '3iMIME-Version: 1.0' ${MSGFILE}
  sed -i '4iContent-Type: text/html' ${MSGFILE}
  sed -i '5i<html>' ${MSGFILE}
  sed -i '$a</html>' ${MSGFILE}
  #sed -i '5iContent-Disposition: inline' ${MSGFILE}
  cat ${MSGFILE} | /usr/sbin/sendmail -f "monthly_reboots@sc.com" -t
}

# Check if lynxprod is running this
user_check

ON=FALSE
OFF=FALSE
REPORT=FALSE

while getopts ynrs:b: opt
do
        case $opt in
        s) site=$OPTARG ;;
        b) batch=$OPTARG ;;
        y) ON=TRUE;;
        n) OFF=TRUE;;
        r) REPORT=TRUE;;
        *) usage ;;
        esac
done

# Check for valid usage
[ -z "$site" ] && usage
[ -z "$batch" ] && usage
[ "${batch}" -eq 1 -o "${batch}" -eq 2 ] 2> /dev/null || usage
[ "${ON}" == "TRUE" -a "${OFF}" == "TRUE" ] && usage
[ "${ON}" == "FALSE" -a "${OFF}" == "FALSE" ] && usage

case $site in
PROD)
          if [[ ${batch} -eq 1 && "${REPORT}" == "FALSE" ]]
          then
              [ "${ON}" == "TRUE" ] && echo "Preparing ${site} batch ${batch} servers for scheduled reboot" || echo "Removing ${site} batch ${batch} servers from scheduled reboot"
              echo "Production Batch 1 -  all FX servers(except LD5), PR and NY4 management servers"
              run uk production efx lynx prod ${ON}
              run us production efx lynx prod ${ON}
              run - - - - - ${ON} uk51a
              run - - - - - ${ON} us50a
              run - - - - - ${ON} us51a
          elif [[ ${batch} -eq 1 && "${REPORT}" == "TRUE" ]]
          then
              echo "Generating Uptime Status for ${site} batch ${batch} servers"
              run uk production efx lynx prod ${ON}
              run us production efx lynx prod ${ON}
              run - - - - - ${ON} uk51a
              run - - - - - ${ON} us50a
              run - - - - - ${ON} us51a
              sleep 2
              cat ${MSGFILE}
          elif [[ ${batch} -eq 2 && "${REPORT}" == "TRUE" ]]
          then
              echo "Generating Uptime Status for ${site} batch ${batch} servers"
              run - production erates - - ${ON}
              run ld5 production efx - prod ${ON}
              run - - - - - ${ON} uk50c
              run - - - - - ${ON} uk51c
              run - - - - - ${ON} sg11a
              run - - - - - ${ON} sg12a
              run - - - - - ${ON} hk01
              run - - - - - ${ON} ae01
              sleep 2
              cat ${MSGFILE}
          else
              [ "${ON}" == "TRUE" ] && echo "Preparing ${site} batch ${batch} servers for scheduled reboot" || echo "Removing ${site} batch ${batch} servers from scheduled reboot"
              echo "Production Batch 2 - all eRates servers, all LD5 servers including LD5 management servers"
              run - production erates - - ${ON}
              run ld5 production efx - prod ${ON}
              run - - - - - ${ON} uk50c
              run - - - - - ${ON} uk51c
              run - - - - - ${ON} sg11a
              run - - - - - ${ON} sg12a
              run - - - - - ${ON} hk01
              run - - - - - ${ON} ae01
          fi
          ;;
DR)
     [ ${batch} -ne 1 ] && usage
     if [ "${REPORT}" == "FALSE" ]
     then
          [ "${ON}" == "TRUE" ] && echo "Preparing ${site} batch ${batch} servers for scheduled reboot" || echo "Removing ${site} batch ${batch} servers from scheduled reboot"
          echo "DR Batch 1 - Watford servers, Watford management servers"
          run uk dr - - prod ${ON}
          run - - - - - ${ON} uk51b
     else
          echo "Generating Uptime Status for ${site} batch ${batch} servers"
          run uk dr - - prod ${ON}
          run  - - - - - ${ON} uk51b
          sleep 2
          cat ${MSGFILE}
     fi
        ;;
*)
          usage
esac

# Trigger Email
[ "${REPORT}" == "TRUE" ] && send_mail

# Cleanup
rm -f ${TEST_HOST} 2> /dev/null
rm -f ${CREATE_LOCK} 2> /dev/null
rm -f ${REMOVE_LOCK} 2> /dev/null
rm -f ${TEST_LOCK} 2> /dev/null
rm -f ${UPTIME_CHECK} 2> /dev/null
rm -f ${MSGFILE} 2> /dev/null
