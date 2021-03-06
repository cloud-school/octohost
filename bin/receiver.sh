#!/bin/bash
if [ -d /home/git/src/$1 ]; then rm -rf /home/git/src/$1; fi
echo "Put repo in src format somewhere."
mkdir -p /home/git/src/$1 && cat | tar -x -C /home/git/src/$1
echo "Building Docker image."
BASE=`basename $1 .git`
echo "Base: $BASE"

# Get Public IP address.
PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com)
XIP_IO="$PUBLIC_IP.xip.io"

# Set the domain name here if desired. Comment out if not used.
DOMAIN_SUFFIX="$PUBLIC_IP.xip.io"

# Find out the old container ID.
OLD_ID=$(sudo docker ps | grep "$BASE:latest" | cut -d ' ' -f 1)

if [ -n "$OLD_ID" ]
then
  OLD_PORT=$(sudo docker inspect $OLD_ID | grep "HostPort" | cut -d ':' -f 2 | cut -d '"' -f 2)
else
  echo "Nothing running - no need to look for a port."
fi

if [ -e "/home/git/src/$1/Dockerfile" ]
then
  # Look for the exposed port.
  INTERNAL_PORT=$(grep -i "EXPOSE" /home/git/src/$1/Dockerfile | cut -d ' ' -f 2)
  # Build and get the ID.
  sudo docker build -t octohost/$BASE /home/git/src/$1
  
  if [ $? -ne 0 ]
  then
    echo "Failed build - exiting."
    exit
  fi
  
  ID=$(sudo docker run -P -d octohost/$BASE)
  # Get the $PORT from the container.
  PORT=$(sudo docker port $ID $INTERNAL_PORT | sed 's/0.0.0.0://')
else
  echo "There is no Dockerfile present."
  exit
fi

if [ -n "$XIP_IO" ]
then
  echo "Adding http://$BASE.$XIP_IO"
  # Zero out any existing items.
  /usr/bin/redis-cli ltrim frontend:$BASE.$XIP_IO 200 200 > /dev/null
  # Connect $BASE.$PUBLIC_IP.xip.io to the $PORT
  /usr/bin/redis-cli rpush frontend:$BASE.$XIP_IO $BASE > /dev/null
  /usr/bin/redis-cli rpush frontend:$BASE.$XIP_IO http://127.0.0.1:$PORT > /dev/null
fi

if [ -n "$DOMAIN_SUFFIX" ]
then
  echo "Adding http://$BASE.$DOMAIN_SUFFIX"
  # Zero out any existing items.
  /usr/bin/redis-cli ltrim frontend:$BASE.$DOMAIN_SUFFIX 200 200 > /dev/null
  # Connect $BASE.$PUBLIC_IP.xip.io to the $PORT
  /usr/bin/redis-cli rpush frontend:$BASE.$DOMAIN_SUFFIX $BASE > /dev/null
  /usr/bin/redis-cli rpush frontend:$BASE.$DOMAIN_SUFFIX http://127.0.0.1:$PORT > /dev/null
fi

# Support a CNAME file in repo src
CNAME=/home/git/src/$1/CNAME
if [ -f $CNAME ]
then
  # Add a new line at end if it does not exist to ensure the loop gets last line
  sed -i -e '$a\' $CNAME
  while read DOMAIN
  do
    echo "Adding http://$DOMAIN"
    /usr/bin/redis-cli ltrim frontend:$DOMAIN 200 200 > /dev/null
    /usr/bin/redis-cli rpush frontend:$DOMAIN $DOMAIN > /dev/null
    /usr/bin/redis-cli rpush frontend:$DOMAIN http://127.0.0.1:$PORT > /dev/null
  done < $CNAME
fi

# Kill the old container by ID.
if [ -n "$OLD_ID" ]
then
  echo "Killing $OLD_ID container."
  sudo docker kill $OLD_ID > /dev/null
else
  echo "Not killing any containers."
fi

if [ -n "$XIP_IO" ]; then echo "Your site is available at: http://$BASE.$XIP_IO";fi
if [ -n "$DOMAIN_SUFFIX" ]; then echo "Your site is available at: http://$BASE.$DOMAIN_SUFFIX";fi
