#!/bin/bash

PASS_FILE=$1
SCP="scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SSH="ssh -q -n -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Extract credentials
while read host pass
do
  export SSHPASS=$(echo $pass)
  echo "Copying app and script to ${host}"
  ./sshpass -p ${SSHPASS} ${SCP} /apps/splunk-forwarder/scripts/scb-apps-scb-singed-cert-sha2.tar ${host}:/tmp > /dev/null 2>&1
  exit_code=$?
  if [ $exit_code -eq 0 ]
  then
      ./sshpass -p ${SSHPASS} ${SCP} /apps/splunk-forwarder/scripts/push_app.sh ${host}:/tmp > /dev/null 2>&1
      exit_code=$?
      if [ $exit_code -eq 0 ]
      then
          echo "Deploying app"
          ./sshpass -p ${SSHPASS} ${SSH} ${host} "chmod 755 /tmp/push_app.sh; /tmp/push_app.sh" > /dev/null 2>&1
          exit_code=$?
          if [ $exit_code -eq 0 ]
          then
              echo "Deployment Completed"
          elif [ $exit_code -eq 1 ]
          then
              echo "Connection timed out. Skipping ${host}"; continue
          elif [ $exit_code -eq 5 ]
          then
              echo "Incorrect credentials. Skipping ${host}"; continue
          fi
      elif [ $exit_code -eq 1 ]
      then
          echo "Connection timed out. Skipping ${host}"; continue
      elif [ $exit_code -eq 5 ]
      then
          echo "Incorrect credentials. Skipping ${host}"; continue
      fi
  elif [ $exit_code -eq 1 ]
  then
      echo "Connection timed out. Skipping ${host}"; continue
  elif [ $exit_code -eq 5 ]
  then
      echo "Incorrect credentials. Skipping ${host}"; continue
  fi
done < ${PASS_FILE}
