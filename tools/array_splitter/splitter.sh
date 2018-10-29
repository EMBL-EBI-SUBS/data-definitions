#!/usr/bin/env bash
FILE=checklists.json
LEN=`jq '. | length' < $FILE`
MAX_INDEX="$(($LEN-1))"

for i in `seq 0 $MAX_INDEX`;
do
	ID=`jq ".[$i]._id" < $FILE | sed 's/"//g'`
	OUTFILE="$ID.json"
	jq ".[$i]" < $FILE > $OUTFILE
done