#!/bin/sh -e
umask 0022

ARCH="`uname -m`"
myOS="`uname -s`"
HOST="`hostname -s`"
CUSR="`echo $USER`"
# user specific configuration file
QLC_DIR="$HOME/qlc"
CONFIG_DIR="$QLC_DIR/config"
CONFIG_FILE="$CONFIG_DIR/qlc.conf"
CONFIG_TEX="$CONFIG_DIR/qlc_tex.conf"

# Source the configuration file to load the settings
. "$CONFIG_FILE"
export CONFIG_DIR
export CONFIG_FILE
. "$CONFIG_TEX"
export CONFIG_TEX

# Include common functions
FUNCTIONS="$SCRIPTS_PATH/qlc_common_functions.sh"
source $FUNCTIONS
export  FUNCTIONS

SCRIPT="$0"
log  "________________________________________________________________________________________"
log  "Start ${SCRIPT} at `date`"
log  "----------------------------------------------------------------------------------------"
log  "Purpose of QLC = Quick Look CAMS/IFS results -- ${HOST} on ${myOS} / ${ARCH} - ${CUSR}  "
log  "           QLC uses subscripts defined in $CONFIG_FILE                                  "
log  "           see $QLC_DIR/doc/README.md for details                                        "
log  "Don^t expect too much, as we follow the KISS principle >Keep it simple, stupid!< ;-) ..."
log  "________________________________________________________________________________________"
log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
log  "----------------------------------------------------------------------------------------"

# Check if the required parameters are provided
if [ $# -eq 0 ]; then
  log  "Error: No parameters provided. Please provide your parameters in the following syntax:"
  log  "$0 exp1 exp2  startDate   endDate, e.g.:"
  log  "$0 b2ro iqi9 2018-12-15 2018-12-31 mars"
  log  "$0 b2ro iqi9 2019-01-01 2019-01-31"
  log  "________________________________________________________________________________________"
  log  "End   ${SCRIPT} at `date`"
  log  "________________________________________________________________________________________"
  exit 1
fi

# Loop through the provided parameters
for param in "$@"; do
  log  "Command line input: $param"
done

# Check if the configuration file exists
if [ -f "$CONFIG_FILE" ]; then
	# Read and export the variables from the configuration file
	while IFS= read -r line; do
		var_name=$(echo "$line" | cut -d= -f1)
		var_value=$(echo "$line" | cut -d= -f2-)

		# Check if the variable is an array
		if [[ "$var_value" =~ "^[[:space:]]*\(.*\)[[:space:]]*$" ]]; then
			eval "array=($var_value)"
			for element in "${array[@]}"; do
				log "Configuration file: $var_name=$element"
#			    export "$var_name"
			done
		else
			log "Configuration file: $var_name=$var_value"
#		    export "$var_name"
		fi
	done < "$CONFIG_FILE"
else
  log  "Error: Config file '$CONFIG_FILE' not found."
  exit 1
fi

# Check if the SUBSCRIPT_NAMES array is defined
if [ -z "${SUBSCRIPT_NAMES[*]}" ]; then
  log "Error: SUBSCRIPT_NAMES is not defined in the configuration file."
  exit 1
fi

# Create working directory if not existent
if [ ! -d "$WORKING_DIRECTORY" ]; then
    mkdir -p $WORKING_DIRECTORY
fi

# Create a temporary directory and store its path in a variable
#TEMP_DIR=$(mktemp -d)
TEMP_DIR=$WORKING_DIRECTORY
export TEMP_DIR

# Change to the temporary directory
cd "$TEMP_DIR"
PWD="`pwd -P`"
log "changed to directory: $PWD" 

# Loop through and call the specified subscripts individually
for name in "${SUBSCRIPT_NAMES[@]}"; do
  script_name="qlc_${name}.sh"
  log  "processing subscript:  $script_name"

  if [ -f "$SCRIPTS_PATH/$script_name" ]; then
    # Call the subscript
    log   "$SCRIPTS_PATH/$script_name" "$@"
          "$SCRIPTS_PATH/$script_name" "$@"

    if [ "$5" == "mars" ]; then
       log "Only calling the mars retrieval script, the other processes can be called in the second qlc submission step (without option: mars)"
       exit 1
    fi
          
  else
    log  "Error: $script_name not found in $SCRIPTS_PATH."
  fi
done

pwd -P
log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0

