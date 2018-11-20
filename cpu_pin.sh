#!/bin/bash
## Script to pin all overhead agents to one core

PATH=$PATH:/usr/bin:/usr/sbin:/bin:/sbin
update_conf()
{
##Update cgconfig.conf
cp -pr /etc/cgconfig.conf /etc/cgconfig.conf.$cr
echo "group mon {" >>/etc/cgconfig.conf
echo "     cpuset {" >>/etc/cgconfig.conf
echo "         cpuset.mems = 0;" >>/etc/cgconfig.conf
echo "         cpuset.cpus = 2,4;" >>/etc/cgconfig.conf
echo "         cpuset.cpu_exclusive = 1;" >>/etc/cgconfig.conf
echo "     }" >>/etc/cgconfig.conf
echo "}" >>/etc/cgconfig.conf

##Update cgrules.conf

cp -pr /etc/cgrules.conf /etc/cgrules.conf.$cr

echo "ganglia    cpuset       mon/" >>/etc/cgrules.conf
echo "splunk     cpuset       mon/" >>/etc/cgrules.conf
echo "patrol     cpuset       mon/" >>/etc/cgrules.conf
echo "itrs       cpuset       mon/" >>/etc/cgrules.conf

count=`cat /etc/*release | grep -i Maipo |wc -l `

if [ $count -gt 0 ]
then
   systemctl enable   cgconfig.service
   systemctl enable   cgred.service
   systemctl restart  cgconfig.service
   systemctl restart  cgred.service
else
   service cgconfig start
   service cgred start
   chkconfig cgconfig on
   chkconfig cgred on
fi

echo "Monitoring has been pinned"

}

usage()
{
        echo "Usage : $0 -c <CR> "
        echo "Rollback : $0 -c <CR> -r"
}




while getopts c:r opt
do
  case $opt in
   c)cr=$OPTARG ;;
   r)if [[ ! "$cr" ]]
     then
          echo "USAGE: $0 -c <CR> -r "
          exit 1
     else
           if [ -f /etc/cgconfig.conf.$cr ] || [ -f /etc/cgrules.conf.$cr ]
           then
              cp -p /etc/cgconfig.conf.$cr /etc/cgconfig.conf
              cp -p /etc/cgrules.conf.$cr /etc/cgrules.conf
              count=`cat /etc/*release | grep -i Maipo |wc -l `

             if [ $count -gt 0 ]
             then
                systemctl disable   cgconfig.service
                systemctl disable   cgred.service
                systemctl stop  cgconfig.service
                systemctl stop  cgred.service
             else
                service cgconfig stop
                service cgred stop
                chkconfig cgconfig off
                chkconfig cgred off
             fi

              echo "Rollback : OK"
              exit
           else
              echo "Restore not required"
              exit
           fi
     fi ;;

   *) usage ;;
      esac
done


if [ -z $cr ]
then
  usage
else
  flag=`grep -qw mon /etc/cgconfig.conf`
  if [ $? -eq 0 ]
  then
     echo "Error: Configuration already exists, please check manually"
     exit 1
  else
     update_conf
  fi
fi
