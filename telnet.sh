#!/bin/bash

SERVER_LIST=$1


# Create temporary status file
tmpfile="`echo /tmp/$[ $RANDOM * $RANDOM ]`"
#while test -e $tmpfile
#do
#   tmpfile="`echo /tmp/$[ $RANDOM * $RANDOM ]`"
#done
export tmpfile
PORT=7037

# Iterate through the exchange server list defined earlier.
for server in `cat $SERVER_LIST`
do
   {
   (sleep 10 ; echo "quit" ) | telnet $server ${PORT} | grep 'Connected to' > /dev/null 2>&1
   [ $? -eq 0 ] && touch $tmpfile
   } &> /dev/null &
   pid=$!
   sleep 10
   wait $pid && kill -9 $pid > /dev/null 2>&1
   if [ -f $tmpfile ]
   then
        echo  "${server}:${PORT} - PASS"
   else
        echo  "${server}:${PORT} - FAIL"
   fi
   rm -rf $tmpfile 2> /dev/null
done
unset tmpfile
