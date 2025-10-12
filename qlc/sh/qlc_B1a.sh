#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Process and convert retrieved grib data (MARS_RETRIEVALS as specified in $CONFIG_FILE)  "
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

log "$0 MARS_RETRIEVAL_DIRECTORY = $MARS_RETRIEVAL_DIRECTORY"
pwd -P

# module load for ATOS
myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`
#log   ${HOST} ${ARCH}
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
module load cdo
fi

# Check if cdo exists
if ! command_exists cdo; then
  log  "Error: cdo command not found" >&2
  exit 1
else
  log  "Success: cdo command found"
  which cdo
fi

# Check if ncdump exists
if ! command_exists ncdump; then
  log  "Error: ncdump command not found" >&2
  exit 1
else
  log  "Success: ncdump command found"
  which ncdump
fi

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# ----------------------------------------------------------------------------------------
# Use common parsing function from qlc_common_functions.sh
# Sets: experiments (array), sDat, eDat, config_arg
parse_qlc_arguments "$@" || exit 1

sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

for exp in "${experiments[@]}"; do
  log "Processing experiment: $exp"

  # Create output directory if not existent
  if [  ! -d "$ANALYSIS_DIRECTORY/$exp" ]; then
    mkdir -p "$ANALYSIS_DIRECTORY/$exp"
  fi

  cd "$MARS_RETRIEVAL_DIRECTORY/$exp"

  for name in "${MARS_RETRIEVALS[@]}"; do

	  # List available GRIB files for selected exp and time period
#	  grbfiles=($(ls *${mDate}*_${name}_*.grb))
	  grbfiles=($(ls *${mDate}*_${name}*.grb 2>/dev/null))
	  set -e

      log "Processing grbfiles: $grbfiles"

	  if [ ${#grbfiles[@]} -eq 0 ]; then
		log "No GRIB files found in $MARS_RETRIEVAL_DIRECTORY/$exp"
	  else
		log "Files to convert: ${grbfiles[@]}"
		log  "----------------------------------------------------------------------------------------"
		for file in "${grbfiles[@]}"; do
		  # convert grib files to netcdf
		  log      "$file"
		  gribfile="$file"
		  ncfile="${gribfile%.grb}.nc"
		  if [ ! -f "$ncfile" ]; then
			log  "Converting $gribfile to $ncfile"
			cdo -f nc copy  "$gribfile"  "$ncfile"
			ls -lh          "$ncfile"
			ncdump -h       "$ncfile"
		    pwd -P
		  else
			log "Nothing to do! NC-file already exists: $ncfile"
			ls -lh           $ncfile
	#       ncdump -h        $ncfile
		    pwd -P
		  fi
		done # file
		log  "----------------------------------------------------------------------------------------"
	  fi

  done # name
done # exps

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
