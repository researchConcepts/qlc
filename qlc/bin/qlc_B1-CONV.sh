#!/bin/bash -e

# ============================================================================
# QLC B1-CONV: GRIB to NetCDF Conversion
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Converts retrieved GRIB data to NetCDF format using CDO (Climate Data 
#   Operators) with intelligent module loading and fallback support.
#
# Usage:
#   Called automatically by qlc_main.sh - Do not call directly
#   For help: qlc -h
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Convert retrieved GRIB data to NetCDF format"
 log  "----------------------------------------------------------------------------------------"

log "$0 MARS_RETRIEVAL_DIRECTORY = $MARS_RETRIEVAL_DIRECTORY"
pwd -P

# Intelligent module loading with fallback to venv/conda
log "Setting up required tools with intelligent module loading..."

# Setup CDO (Climate Data Operators)
if ! setup_cdo; then
  log "Error: Failed to setup CDO" >&2
  exit 1
fi

# Setup NCDUMP (NetCDF utilities)
if ! setup_ncdump; then
  log "Error: Failed to setup NCDUMP" >&2
  exit 1
fi

log "Success: All required tools configured"
log "CDO: $CDO_CMD"
log "NCDUMP: $NCDUMP_CMD"

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# ----------------------------------------------------------------------------------------
# Use common parsing function from qlc_common_functions.sh
# Sets: experiments (array), sDat, eDat, config_arg
parse_qlc_arguments "$@" || exit 1

# Early return if no experiments specified (obs-only mode)
# B1-CONV only processes experiment data, not observations
if [ ${#experiments[@]} -eq 0 ]; then
    log "No experiments specified - skipping GRIB to NetCDF conversion (obs-only mode)"
    log "End ${SCRIPT} at `date`"
    log "________________________________________________________________________________________"
    exit 0
fi

sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# Get list of expected variables from MARS_RETRIEVALS configuration
# Sets global array: expected_vars
get_expected_variables_from_mars_retrievals

for exp in "${experiments[@]}"; do
  log "Processing experiment: $exp"

  # Create output directory if not existent
  if [  ! -d "$ANALYSIS_DIRECTORY/$exp" ]; then
    mkdir -p "$ANALYSIS_DIRECTORY/$exp"
  fi

  cd "$MARS_RETRIEVAL_DIRECTORY/$exp"

  # List all GRIB files for this experiment and time period
  set +e
  grbfiles=($(ls ${exp}_${mDate}_*.grb 2>/dev/null))
  set -e

  log "Found ${#grbfiles[@]} GRIB file(s) matching pattern"

  # Filter files based on MARS_RETRIEVALS if defined
  if [ ${#expected_vars[@]} -gt 0 ]; then
    filtered_grbfiles=()
    for file in "${grbfiles[@]}"; do
      # Extract var_id from filename: {exp}_{dates}_{var_id}.grb
      basename_file=$(basename "$file" .grb)
      var_id="${basename_file#${exp}_${mDate}_}"
      
      # Check if this var_id is in expected_vars
      for expected_var in "${expected_vars[@]}"; do
        if [ "$var_id" == "$expected_var" ]; then
          filtered_grbfiles+=("$file")
          break
        fi
      done
    done
    
    grbfiles=("${filtered_grbfiles[@]}")
    log "After filtering by MARS_RETRIEVALS: ${#grbfiles[@]} file(s) to process"
  fi

  if [ ${#grbfiles[@]} -eq 0 ]; then
    log "No GRIB files found in $MARS_RETRIEVAL_DIRECTORY/$exp"
    log "Expected pattern: ${exp}_${mDate}_*.grb"
    log "This may indicate:"
    log "  - MARS retrieval not yet complete (check .download flags)"
    log "  - Date mismatch in file naming"
    log "  - No files match MARS_RETRIEVALS filter"
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
			"$CDO_CMD" -f nc copy  "$gribfile"  "$ncfile"
			ls -lh          "$ncfile"
			"$NCDUMP_CMD" -h       "$ncfile"
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

done # exps

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
