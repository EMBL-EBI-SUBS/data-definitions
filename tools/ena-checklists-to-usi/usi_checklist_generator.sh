#!/bin/bash
for i in {11..51}
do
    filename="ERC0000$i"
    command="perl convert_to_usi.pl $filename > sample_checklists/$filename.json"
    echo $command
    eval $command
   
    if [ $? -ne 0 ]; then
	echo -e "\033[31;1mEither $filename is not exists in ENA or there was an conversion error.\033[0m"
    else
        echo "$filename USI checklist generated."
    fi
done
