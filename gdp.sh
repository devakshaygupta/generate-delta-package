#!/bin/bash

################################################################################################################################################
#                                                        Generate Delta Package                                                                #
#                                                                                                                                              #
#                                                                                                                                              #
# Change History                                                                                                                               #
# Date                                                                                             Author Name                                 #
# 29/03/2023                                                                                       Akshay Gupta                                #
#                                                                                                                                              #
# This is a Bash script that generates a package.xml file based on the changes made to files in a Salesforce development environment.          #
# The script uses Git to obtain a list of changed files between two branches and copies the changed files to a working directory.              #
# It then reads through the list of changed files and generates a package.xml file based on the metadata type of the files. The script         #
# uses two JSON files to map Salesforce directory names to their corresponding metadata types and to determine whether a metadata file         #
# exists for a given directory. It also handles exceptions for certain metadata types that have non-standard naming conventions.               #
# The generated package.xml file is written to the working directory and can be used to deploy the changed files to another Salesforce org.    #
#                                                                                                                                              #
################################################################################################################################################
############################################################
# Help  Function to show usage of the script               #
############################################################
Help()
{
   # Display Help
   echo "This script generates a package.xml file based on the changes made to files in a Salesforce development environment."
   echo
   echo "Syntax: ./gdp.sh -s feature/something -t release/something -d /path/To/Repository"
   echo "options:"
   echo "s     Name of the source branch."
   echo "t     Name of the target branch."
   echo "d     Absolute Path to git repository."
   exit 1
}

while getopts "s:t:d:" option; do
  case "$option" in
    s) source=${OPTARG};;
    t) target=${OPTARG};;
    d) directory=${OPTARG};;
    *) Help;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "$source" ]] || [[ -z "$target" ]] || [[ -z "$directory" ]]
then
  Help
fi

set -euo pipefail

# Constants
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
readonly SCRIPT_PATH
WORKING_DIR=$(pwd)"/delta-changes"
readonly WORKING_DIR
declare -r OUTPUT_XML_FILE="$WORKING_DIR/package.xml"
declare -r CHANGED_SRC_LIST_FILE="$SCRIPT_PATH/ChangedFileNames.txt"
declare -r TEST_CLASS_LIST_FILE="$SCRIPT_PATH/TestClassList.txt"
declare -r DIR_XML_NAME_JSON_DATA="$SCRIPT_PATH/DirectoryXMLName_v56.json"
declare -r DIR_NAME_META_FILE_JSON_DATA="$SCRIPT_PATH/DirectoryNameMetafile_v56.json"
declare -r TEST_CLASS_MAPPING_JSON_DATA="$SCRIPT_PATH/TestClassMapping.json"
declare -r API_VERSION=51.0

declare -a changed_file_path_list
declare -a test_class_list
declare -a apex_classes_list=()
declare -a exceptional_metadata=("customMetadata" "quickActions" "approvalProcesses")

declare -A exceptional_metadata_suffix=(
  ["customMetadata"]=".md"
  ["quickActions"]=".quickAction"
  ["approvalProcesses"]=".approvalProcess"
)

# Parse the JSON text using jq and store the result in an associative array
declare -A dir_xml_name_array

eval "$(jq -r 'to_entries[] | @sh "dir_xml_name_array[\(.key|tostring)]=\(.value)"' < "$DIR_XML_NAME_JSON_DATA")"

declare -A dir_meta_file_exist_array

eval "$(jq -r 'to_entries[] | @sh "dir_meta_file_exist_array[\(.key|tostring)]=\(.value)"' < "$DIR_NAME_META_FILE_JSON_DATA")"

declare -A test_class_mapping_array

eval "$(jq -r 'to_entries[] | @sh "test_class_mapping_array[\(.key|tostring)]=\(.value)"' < "$TEST_CLASS_MAPPING_JSON_DATA")"


# Creating directory to store changed sources and package.xml
if [[ -d "$WORKING_DIR" ]]
then
  rm -Rf "$WORKING_DIR" || { echo "Error removing directory $WORKING_DIR"; exit 1; }
fi

mkdir -p "$WORKING_DIR" || { echo "Error creating directory $WORKING_DIR"; exit 1; }

if [[ -f "$CHANGED_SRC_LIST_FILE" ]]
then
  rm -f "$CHANGED_SRC_LIST_FILE" || { echo "Error removing file $CHANGED_SRC_LIST_FILE"; exit 1; }
fi

touch "$OUTPUT_XML_FILE" || { echo "Error creating file $OUTPUT_XML_FILE"; exit 1; }
touch "$CHANGED_SRC_LIST_FILE" || { echo "Error creating file $CHANGED_SRC_LIST_FILE"; exit 1; }

pushd "$directory" && git checkout "$target" && git pull && git checkout "$source" && git pull && git diff "$(git merge-base "$source" "$target")" "$source" --name-only --diff-filter=ACMRTUXB > "${CHANGED_SRC_LIST_FILE}" && popd || { echo "Error getting changed files list"; exit 1; }

if [[ ! -s "$CHANGED_SRC_LIST_FILE" ]]
then
  echo "There is no difference between the branches exiting..."; exit 0;
fi

while read -r line; do
  if [[ "$line" == *"src/"* ]] && [[ "$line" != *"src/package.xml"* ]]
  then
    directory_name=$(echo "${line}" | cut -d'/' -f2)
    meta_file_exist=$(echo "${dir_meta_file_exist_array[$directory_name]}")
    install -Dv "$directory""/${line}" "$WORKING_DIR"/"${line}" || { echo "Error copying file $line to $WORKING_DIR"; exit 1; }
    if [[ "${exceptional_metadata[*]}" =~ "$directory_name" ]]
    then
      temp_line=$(echo "${line}" | cut -d'/' -f3)
      file_name=$(echo "${temp_line//$(echo "${exceptional_metadata_suffix[$directory_name]}")}")
    else
      file_name=$(echo "${line}" | cut -d'/' -f3 | cut -d'.' -f1)
    fi
    if [[ "$meta_file_exist" == true ]] && [[ -f "$directory""/${line}-meta.xml" ]]; then
      install -Dv "$directory""/${line}-meta.xml" "$WORKING_DIR"/"${line}-meta.xml" || { echo "Error copying meta file $line-meta.xml to $WORKING_DIR"; exit 1; }
    fi
  fi
done < "${CHANGED_SRC_LIST_FILE}"

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" >> "${OUTPUT_XML_FILE}"
echo "<Package xmlns=\"http://soap.sforce.com/2006/04/metadata\">" >> "${OUTPUT_XML_FILE}"

# Reading the file as an array
readarray -t changed_file_path_list < "$CHANGED_SRC_LIST_FILE"

readarray -t test_class_list < "$TEST_CLASS_LIST_FILE"

iterator=1
previous_file=""

# Skipping NON-SFDC and package.xml changes and appending relevant changes to package.xml
for line in "${changed_file_path_list[@]}"; do
  echo "Processing file(s) $iterator out of ${#changed_file_path_list[@]}"
  if [[ "$line" == *"src/"* ]] && [[ "$line" != *"src/package.xml"* ]]
  then
    directory_name=$(echo "${line}" | cut -d'/' -f2)
    if [[ "${exceptional_metadata[*]}" =~ "$directory_name" ]]
    then
      temp_line=$(echo "${line}" | cut -d'/' -f3)
      file_name=$(echo "${temp_line//$(echo "${exceptional_metadata_suffix[$directory_name]}")}")
    else
      file_name=$(echo "${line}" | cut -d'/' -f3 | cut -d'.' -f1)
    fi
    metadata_name=$(echo "${dir_xml_name_array[$directory_name]}")
    if [[ "$directory_name" == "classes" ]]
    then
      apex_classes_list+=("$file_name")
    fi
    if [[ "$previous_file" != "$file_name" ]]
    then
      echo "  <types>" >> "${OUTPUT_XML_FILE}"
      echo "    <members>${file_name}</members>" >> "${OUTPUT_XML_FILE}"
      echo "    <name>${metadata_name}</name>" >> "${OUTPUT_XML_FILE}"
      echo "  </types>" >> "${OUTPUT_XML_FILE}"
    fi
  fi
  iterator=$((iterator+1))
  previous_file=$file_name
done

echo "  <version>${API_VERSION}</version>" >> "${OUTPUT_XML_FILE}"
echo "</Package>" >> "${OUTPUT_XML_FILE}"

rm "${CHANGED_SRC_LIST_FILE}" || { echo "Error: Failed to remove file $CHANGED_SRC_LIST_FILE"; exit 1; }
mv "${OUTPUT_XML_FILE}" "${WORKING_DIR}/src/package.xml" || { echo "Error: Failed to move package.xml file"; exit 1; }

testClassNameList=""

for class_name in "${!test_class_mapping_array[@]}"
do
  # Read test class for given apex class and appending to build.xml
  if [[ "${apex_classes_list[*]}" =~ "$class_name" ]]
  then
    test_class_name=$(echo "${test_class_mapping_array[$class_name]}")
    testClassNameList+="<runTest>${test_class_name}<\/runTest>\n\t\t"
  fi
done

for test_class_name in "${!test_class_list[@]}"
do
  # If the given class itself is test class
  if [[ -f "$WORKING_DIR/src/classes/$test_class_name.cls" ]]
  then
    testClassNameList+="<runTest>${test_class_name}<\/runTest>\n\t\t"
  fi
done

# If no test classes found when change is detected in apex classes, failing the build.
if [[ "$testClassNameList" == "" ]] && [[ -d "$WORKING_DIR/src/classes" ]]
then
    echo "No test classes found!!!"; exit 1;
fi

# Adding test classes to build.xml
if [[ "$testClassNameList" != "" ]]
then
  sed 's/<runTest><\/runTest>/'"${testClassNameList}"'/g' build_template.xml > build.xml || { echo "Error adding test classes to build.xml"; exit 1; }
fi

unset "${apex_classes_list[@]}"
echo "Processing Completed!!"
echo "Starting Validation...."

if [[ -d "$WORKING_DIR/src/classes" ]]
then
  ant validateWithTestClass
else
  cp build_template.xml build.xml
  ant validate
fi