#!/usr/bin/env python
"""
  Description: Run remote command using credentials passed from a file
  Usage: ./rrc.py <passwd file>
  passwd file format: server hostname/ip, username, password
  Example: hostname, username, password
"""
import sys
import paramiko

def copy_files(hostname, username, password, src1, dst1, src2, dst2):
  ssh_client = paramiko.SSHClient()
  ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
  ssh_client.connect(hostname=hostname,username=username,password=password)
  ftp_client=ssh_client.open_sftp()
  print "Copying file: %s to %s:%s" %(src1, hostname, dst1)
  ftp_client.put(src1, dst1)
  print "Copying file: %s to %s:%s" %(src2, hostname, dst2)
  ftp_client.put(src2, dst2)
  print "Pushing new app..."
  ssh_client.exec_command("chmod 755 /tmp/push_app.sh")
  stdin, stdout, stderr = ssh_client.exec_command("/tmp/push_app.sh")
  for line in stdout:
    print '... ' + line.strip('\n')
  print "Executing remote commands completed"
  ssh_client.close()

pwd_file = sys.argv[1]

src1 = '/apps/splunk-forwarder/scripts/scb-apps-scb-singed-cert-sha2.tar'
dst1 = '/tmp/scb-apps-scb-singed-cert-sha2.tar'
src2 = '/apps/splunk-forwarder/scripts/push_app.sh'
dst2 = '/tmp/push_app.sh'

f = open(pwd_file)
credentials = f.readlines()

for i in credentials:
  data = i.split(',')
  hostname = data[0].strip()
  username = data[1].strip()
  password = data[2].strip()
  try:
    copy_files(hostname, username, password, src1, dst1, src2, dst2)
  except paramiko.AuthenticationException:
    print hostname + ': ' + "Skipping due to authentication failure"
  except paramiko.SSHException:
    print hostname + ': ' + "Skipping due to incompatible ssh ciphers"
