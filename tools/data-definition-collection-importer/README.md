Data definition importer tool

This tool imports all the JSON document files from the given folder to the given database to the given collection.

You have to overwrite the default configuration in the script:

HOST=host
USERNAME=username
PASSWORD=password
DATABASE_NAME=database_name

with the correct configuration settings.

Parameters:

1. The name of the collection to import the JSON documents
2. The folder path where the JSON documents can be found

Example usage:

./collection-importer.sh submissionPlan ../../submission-plans/
