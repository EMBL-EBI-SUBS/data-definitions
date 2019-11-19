#!/bin/bash

CHECKLISTS_FOLDER=$1

if test -z "$CHECKLISTS_FOLDER" 
then
    echo "The script first parameter should be the folder where it is going to generate the checklists"
fi

for i in {11..51}
do
    filename="ERC0000$i"
    command="perl convert_ena_cl_to_usi_schema.pl $filename > $CHECKLISTS_FOLDER/$filename.json"
    echo $command
    eval $command
   
    if [ $? -ne 0 ]; then
	    echo -e "\033[31;1mEither $filename is not exists in ENA or there was an conversion error.\033[0m"
        rm $CHECKLISTS_FOLDER/$filename.json
    else
        echo "$filename USI checklist generated."
    fi
done
