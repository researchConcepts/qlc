#!/bin/sh -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="python"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create Python plots for selected variables (to be defined in $CONFIG_FILE)              "
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
pwd -P

# module load for ATOS
myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`
#log   ${HOST} ${ARCH}
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
module load python3/3.10.10-01
fi

# Check if python exists
if ! command_exists python; then
  log  "Error: python command not found" >&2
  exit 1
else
  log  "Success: python command found"
  which python
fi

# Create output directory if not existent
if [    ! -d "$PLOTS_DIRECTORY" ]; then
    mkdir -p "$PLOTS_DIRECTORY"
fi

# get script name without path and extension
script_name="${SCRIPT##*/}"     # Remove directory path
script_name="${script_name%.*}" # Remove extension
QLTYPE="$script_name"

# Assign the command line input parameters to variables
exp1="$1"
exp2="$2"
sDat="$3"
eDat="$4"
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"
ext="${QLTYPE}.pdf"

exps="$exp1 $exp2"
for exp in $exps ; do
	log "Processing ${PLOTTYPE} plot for experiment: $exp"

	log "TEAM_PREFIX      : $TEAM_PREFIX"
	log "EVALUATION_PREFIX: $EVALUATION_PREFIX"
	log "MODEL_RESOLUTION : $MODEL_RESOLUTION"
	log "TIME_RESOLUTION  : $TIME_RESOLUTION"
	log "mDate            : $mDate"
	log "ext              : $ext"
	log "exp1             : $exp1"
	log "exp2             : $exp2"

	ipath="$ANALYSIS_DIRECTORY/$exp"
	tpath="$PLOTS_DIRECTORY/$exp"
    hpath="$PLOTS_DIRECTORY/${exp1}-${exp2}_${mDate}"

	# Create help directory if not existent
  	if [  ! -d "$hpath" ]; then
    	mkdir -p "$hpath"
	fi

	# Create output directory if not existent
  	if [  ! -d "$tpath" ]; then
    	mkdir -p "$tpath"
	fi

    for name in "${MARS_RETRIEVALS[@]}"; do

	  log "name             : $name"

	  # Define the corresponding arrays based on the name
	  param_var="param_${name}[@]"
	  ncvar_var="ncvar_${name}[@]"
	  myvar_var="myvar_${name}[@]"

	  # Use variable indirection to access the arrays
	  param=("${!param_var}")
	  ncvar=("${!ncvar_var}")
	  myvar=("${!myvar_var}")

	  cd $ipath

	  # Loop through the variables for this $name
	  for ((i = 0; i < ${#ncvar[@]}; i++)); do

		myvar_name="${myvar[i]}"
		log "myvar_name       : $myvar_name"

		tfile="${EVALUATION_PREFIX}_${exp1}-${exp2}_${myvar_name}_${mDate}_${name}_$ext"
		log "${PLOTTYPE} plot for: $myvar_name - $tpath/$tfile"
		log "work in progress, plot scripts to be implemented ..."

 		touch  $tpath/$tfile
 		ls -lh $tpath/$tfile

 	  done # ncvar
    done # name
done # exps

log "$ipath"
log "$tpath"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
