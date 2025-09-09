#!/bin/bash -e
umask 0022

# --- Start: Environment Setup ---
# Find the Python executable that runs this tool.
# This ensures that any executables installed in the same environment (like pyferret) are found.
# Fallback to 'python3' if 'qlc' is not in the path (e.g., during development).
PYTHON_CMD=$(which python3)
if command -v qlc >/dev/null 2>&1; then
    QLC_PATH=$(which qlc)
    PYTHON_CMD=$(head -n 1 "$QLC_PATH" | sed 's/^#!//')
fi

# Get the directory of the Python executable.
PYTHON_BIN_DIR=$(dirname "$PYTHON_CMD")

# Prepend this directory to the PATH for this script and all subscripts.
export PATH="$PYTHON_BIN_DIR:$PATH"
# --- End: Environment Setup ---

ARCH="`uname -m`"
myOS="`uname -s`"
HOST="`hostname -s`"
CUSR="`echo $USER`"
# user specific configuration file
QLC_DIR="$HOME/qlc"
CONFIG_DIR="$QLC_DIR/config"
CONFIG_FILE="$CONFIG_DIR/qlc.conf"

# Source the configuration file and automatically export all defined variables
# to make them available to any subscripts that are called.
set -a
. "$CONFIG_FILE"
set +a

export CONFIG_DIR
export CONFIG_FILE

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
log  "           see $QLC_DIR/doc/README.md for details                                       "
log  "Don^t expect too much, as we follow the KISS principle >Keep it simple, stupid!< ;-) ..."
log  "________________________________________________________________________________________"
log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
log  "----------------------------------------------------------------------------------------"

# Check if the required parameters are provided
if [ $# -eq 0 ]; then
  log  "No parameters provided. Please provide your parameters in the following syntax:"
  log  "qlc exp1 exp2  startDate   endDate [mars]"
  log  "type, e.g.:"
  log  "qlc b2ro b2rn 2018-12-01 2018-12-21"
  log  "qlc b2ro b2rn 2018-12-01 2018-12-21 mars"
  log  " "
  log  "Use option 'mars' to retrieve files and then submit a dependency job once all data have been retrieved."
  log  "Or, option 'mars' can be skipped, if all data are already present in $MARS_RETRIEVAL_DIRECTORY"
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
	# ----------------------------------------------------------------------------------------
	# Log the active configuration settings, excluding comments and empty lines
	log "Active configuration settings from: ${CONFIG_FILE}"
	grep -v '^\s*#\|^\s*$' "$CONFIG_FILE" | while IFS= read -r line; do
		log "  ${line}"
	done
	log "----------------------------------------------------------------------------------------"

	# Source the configuration file and automatically export all defined variables
	# to make them available to any subscripts that are called.
	set -a
	. "$CONFIG_FILE"
	set +a

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
       log  "----------------------------------------------------------------------------------------"
       log  "End ${SCRIPT} at `date`"
       log  "________________________________________________________________________________________"
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

