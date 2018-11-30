#!/bin/bash
COLLECTION=$1
FOLDER=$2

HOST=host
USERNAME=username
PASSWORD=password
DATABASE_NAME=database_name

cd $FOLDER
for filename in *
do
  mongoimport --host $HOST --username $USERNAME --password $PASSWORD --collection $COLLECTION --db $DATABASE_NAME --authenticationDatabase admin --file $filename
  echo $filename
done
exit 0
