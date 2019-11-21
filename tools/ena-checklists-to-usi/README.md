ENA checklist to USI checklist converter

ENA uses checklists to represent data standards for samples.

We have 2 scripts in this folder.

* convert_to_usi.pl

 The script in the directory converts an ENA checklist into a USI checklist. This JSON object also contains keys-values for the UI spreadsheet template.

 e.g. ./convert_to_usi.pl ERC000030 > ERC000030.usi.json

 It will work for most cases, but does not handle every feature. It's your responsibility to make sure it works correctly.

* convert_ena_cl_to_usi_schema.pl

 The script in the directory converts an ENA checklist into a USI validation schema. This object only contains the JSON equivalent of an ENA checklist in XML format.

 e.g. ./convert_ena_cl_to_usi_schema.pl ERC000030 > ERC000030.usi.json

 It will work for most cases, but does not handle every feature. It's your responsibility to make sure it works correctly.

You can find ENA checklists and their accessions here:

https://www.ebi.ac.uk/ena/submit/checklists
