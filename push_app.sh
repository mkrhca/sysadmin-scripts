#!/bin/sh
# Script to push app

# Define variables
app_path=/opt/splunkforwarder/etc/apps
app_path_2=/opt/splunk/etc/apps
app_file=scb-apps-scb-singed-cert-sha2.tar
app_temp_path=/tmp
splunk_bin=/opt/splunkforwarder/bin/splunk
splunk_bin_2=/opt/splunk/bin/splunk
old_app=scb-apps-scb-singed-cert-sha2
bad_app=_scb-apps-scb-singed-cert-sha2.BAD


if [ -d ${app_path} ]
then
  if [ -f ${app_temp_path}/${app_file} ]
  then
     echo "Copying app to ${app_path}"
     cp ${app_temp_path}/${app_file} ${app_path}
     if [ -d ${app_path}/${old_app} ]
     then
       echo "Removing old app directory: ${app_path}/${old_app}"
       rm -rf ${app_path}/${old_app}
       echo "Removing bad app directory: ${app_path}/${bad_app}"
       rm -rf ${app_path}/${bad_app}
       echo "Deploying new app in ${app_path}"
       cd ${app_path}
       tar -xvf ${app_file}
       echo "Removing tar file.."
       rm  ${app_path}/${app_file}
       echo "Restarting splunk"
       ${splunk_bin} restart
     else
       echo "Old app directory: ${app_path}/${old_app} does not exist"
       echo "Removing bad app directory: ${app_path}/${bad_app}"
       rm -rf ${app_path}/${bad_app}
       echo "Deploying new app in ${app_path}"
       cd ${app_path}
       tar -xvf ${app_file}
       echo "Removing tar file.."
       rm  ${app_path}/${app_file}
       echo "Restarting splunk"
       ${splunk_bin} restart
     fi
  fi
elif [ -d ${app_path_2} ]
then
  if [ -f ${app_temp_path}/${app_file} ]
  then
     echo "Copying app to ${app_path}"
     cp ${app_temp_path}/${app_file} ${app_path_2}
     if [ -d ${app_path_2}/${old_app} ]
     then
       echo "Removing old app directory: ${app_path_2}/${old_app}"
       rm -rf ${app_path_2}/${old_app}
       echo "Removing bad app directory: ${app_path_2}/${bad_app}"
       rm -rf ${app_path_2}/${bad_app}
       echo "Deploying new app in ${app_path_2}"
       cd ${app_path_2}
       tar -xvf ${app_file}
       echo "Removing tar file.."
       rm  ${app_path_2}/${app_file}
       echo "Restarting splunk"
       ${splunk_bin} restart
     else
       echo "Old app directory: ${app_path}/${old_app} does not exist"
       echo "Removing bad app directory: ${app_path_2}/${bad_app}"
       rm -rf ${app_path_2}/${bad_app}
       echo "Deploying new app in ${app_path_2}"
       cd ${app_path_2}
       tar -xvf ${app_file}
       echo "Removing tar file.."
       rm  ${app_path_2}/${app_file}
       echo "Restarting splunk"
       ${splunk_bin} restart
     fi
  fi
else
  echo "Required apps path missing. Exiting..."
  exit 2
fi
