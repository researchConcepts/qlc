#!/bin/bash -e

# ============================================================================
# QLC B2-PREP: NetCDF Data Processing and Preparation
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Processes NetCDF files (converted from GRIB) including variable renaming,
#   time averaging, and data preparation for analysis as specified in the
#   workflow configuration.
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
 log  "Process NC-files (converted grib files of MARS_RETRIEVALS as specified in $CONFIG_FILE) "
 log  "----------------------------------------------------------------------------------------"

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
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
# B2-PREP only processes experiment data, not observations
if [ ${#experiments[@]} -eq 0 ]; then
    log "No experiments specified - skipping NetCDF preparation (obs-only mode)"
    log "End ${SCRIPT} at `date`"
    log "________________________________________________________________________________________"
    exit 0
fi

# Load variable registry for metadata access
load_variable_registry

sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# Get list of expected variables from MARS_RETRIEVALS configuration
# Sets global array: expected_vars
get_expected_variables_from_mars_retrievals

for exp in "${experiments[@]}"; do
  log "Processing experiment: $exp"

  ipath="$MARS_RETRIEVAL_DIRECTORY/$exp"
  tpath="$ANALYSIS_DIRECTORY/$exp"

  # Create output directory if not existent
  if [  ! -d "$tpath" ]; then
    mkdir -p "$tpath"
  fi

  log  "----------------------------------------------------------------------------------------"

  cd $ipath
  pwd -P

  # List all NetCDF files (excluding _tavg files)
  set +e
  ncfiles=($(ls ${exp}_${mDate}_*.nc 2>/dev/null | grep -v "_tavg.nc"))
  set -e

  log "Found ${#ncfiles[@]} NetCDF file(s) matching pattern"

  # Filter files based on MARS_RETRIEVALS if defined
  if [ ${#expected_vars[@]} -gt 0 ]; then
    filtered_ncfiles=()
    for file in "${ncfiles[@]}"; do
      # Extract var_id from filename: {exp}_{dates}_{var_id}.nc
      basename_file=$(basename "$file" .nc)
      var_id="${basename_file#${exp}_${mDate}_}"
      
      # Check if this var_id is in expected_vars
      for expected_var in "${expected_vars[@]}"; do
        if [ "$var_id" == "$expected_var" ]; then
          filtered_ncfiles+=("$file")
          break
        fi
      done
    done
    
    ncfiles=("${filtered_ncfiles[@]}")
    log "After filtering by MARS_RETRIEVALS: ${#ncfiles[@]} file(s) to process"
  fi

  if [ ${#ncfiles[@]} -eq 0 ]; then
    log "No NC-files found in $MARS_RETRIEVAL_DIRECTORY/$exp"
    log "Expected pattern: ${exp}_${mDate}_*.nc (excluding *_tavg.nc)"
    log "This may indicate:"
    log "  - GRIB to NetCDF conversion not yet complete (run B1-CONV first)"
    log "  - No files match MARS_RETRIEVALS filter"
  else
    log "Files to process: ${ncfiles[@]}"
    log  "----------------------------------------------------------------------------------------"

  cd $tpath
  pwd -P

  # Process each NetCDF file
  for ncfile in "${ncfiles[@]}"; do
    log "Processing: $ncfile"
    
    # Extract variable name and levtype from filename
    # Pattern: {exp}_{dates}_{levtype}_{myvar}.nc (matches var.var_id from Python parser)
    # Example: b2rn_20181201-20181221_pl_NH3.nc
    filename=$(basename "$ncfile" .nc)
    
    # Remove exp and dates prefix to get: {levtype}_{myvar}
    var_id="${filename#${exp}_${mDate}_}"
    
    # Extract levtype (first component before first underscore)
    levtype="${var_id%%_*}"
    
    # Extract myvar (everything after first underscore)
    myvar_from_file="${var_id#${levtype}_}"
    
    log "Extracted from filename:"
    log "  var_id: $var_id"
    log "  levtype: $levtype"
    log "  myvar: $myvar_from_file"
    
    # Build variable name for registry lookup (var_id format from registry)
    var_name="${var_id}"
    
    # Get metadata from Python parser (v0.4.02+ approach)
    # We use the simple format: one file = one variable, var_id is the key
    # For the new system, ncvar in the file will typically match var_id (e.g., "pl_NH3")
    # and we want to rename it to myvar (e.g., "NH3")
    
    log "Using: var_id=$var_id, myvar=$myvar_from_file, levtype=$levtype"
    
    # In the new system, each file contains one variable
    # The variable name in the NetCDF file is the var_id (e.g., "pl_NH3")
    # We want to rename it to myvar (e.g., "NH3")
    ncvar_name="${var_id}"  # Variable name in the NetCDF file (from MARS retrieval)
    myvar_name="${myvar_from_file}"  # Target variable name for analysis
    
    log "Variable mapping:"
    log "  ncvar_name (in file): ${ncvar_name}"
    log "  myvar_name (target): ${myvar_name}"

    # Get variables in the NetCDF file
    vars="$("$NCDUMP_CMD" -h "$ipath/$ncfile" | grep float | sed 's|(| |g' | awk '{printf("%20s", $2)}')"
    log "nc-file variables: $vars"

    # In the new system (v0.4.02+), the variable name in the file should match var_id
    # Auto-detect the data variable (skip coordinate variables)
    found_ncvar=""
    for v in ${vars[@]}; do
      # Skip coordinate and time variables
      if [[ "$v" != "time" && "$v" != "lat" && "$v" != "latitude" && "$v" != "lon" && "$v" != "longitude" && "$v" != "level" && "$v" != "lev" ]]; then
        found_ncvar="$v"
        break
      fi
    done
    
    if [ -z "$found_ncvar" ]; then
      log "ERROR: Could not detect variable name in file $ncfile"
      continue  # Skip to next file
    fi
    
    ncvar_name="$found_ncvar"
    log "Detected variable in file: $ncvar_name (will be renamed to $myvar_name)"

    # Extract the data level type (already extracted from filename above)
    ltype="_${levtype}"
    log "Data level type: $ltype - $ncfile / $exp"

    "$CDO_CMD" zaxisdes $ipath/$ncfile > $tpath/zaxisdes
    head -61                      $tpath/zaxisdes > $tpath/zaxis1

    # Process the single variable (new v0.4.02+ approach: one file = one variable)
    GO="GO"
    setctomiss="setctomiss,-999"
    sellevel=""
    variable_rename="$myvar_name"
    varn="$variable_rename"
    log "Processing variable: $ncvar_name → $variable_rename"

    # Check for special multi-level variables like EQdiag
    case "$variable_rename" in
      "EQdiag")
        GO="GO2"
#				  declare -a dvars=("GFh2o" "GFhsa" "GFhna" "GFhca" "GFxam" "GFalc" "GFasu" "GFahs" "GFano" "GFacl" "GFslc" "GFssu" "GFshs" "GFsno" "GFscl" "GFplc" "GFpsu" "GFphs" "GFpno" "GFpcl" "GFc01" "GFcsu" "GFc02" "GFcno" "GFccl" "GFm01" "GFmsu" "GFm02" "GFmno" "GFmcl" "AWh2o" "AWhsa" "AWhna" "AWhca" "AWxam" "AWalc" "AWasu" "AWahs" "AWano" "AWacl" "AWslc" "AWssu" "AWshs" "AWsno" "AWscl" "AWplc" "AWpsu" "AWphs" "AWpno" "AWpcl" "AWc01" "AWcsu" "AWc02" "AWcno" "AWccl" "AWm01" "AWmsu" "AWm02" "AWmno" "AWmcl" "EQpH1" "EQpH2" "EQpH3" "EQpH4" "EQpH5" "EQAW1" "EQAW2" "EQAW3" "EQAW4" "EQAD" "EQHp" "EQPMt" "EQPMs" "EQsPM" "EQaPM" "EQRHO" "EQGF" "EQTT" "EQRH" "EQP")
#				  declare -a nvars=(  "1"     "2"     "3"     "4"     "5"     "6"     "7"     "8"     "9"     "10"   "11"    "12"    "13"     "14"    "15"   "16"     "17"    "18"    "19"    "20"    "21"    "22"    "23"    "24"    "25"   "26"     "27"   "28"     "29"    "30"    "31"    "32"    "33"    "34"    "35"   "36"     "37"    "38"    "39"    "40"    "41"    "42"    "43"    "44"    "45"    "46"    "47"    "48"    "49"    "50"    "51"   "52"     "53"    "54"    "55"    "56"    "57"    "58"    "59"    "60"   "61"    "62"     "63"    "64"    "65"   "66"    "67"    "68"    "69"    "70"   "71"   "72"    "73"    "74"    "75"     "76"   "77"   "78"   "79"   "80")
   				  declare -a nvars=(  "1"     "2"     "3"     "4"     "5"     "6"     "7"     "8"     "9"     "10"   "11"    "12"    "13"     "14"    "15"   "16"     "17"    "18"    "19"    "20"    "21"    "22"    "23"    "24"    "25"   "26"     "27"   "28"     "29"    "30"    "31"    "32"    "33"    "34"    "35"   "36"     "37"    "38"    "39"    "40"    "41"    "42"    "43"    "44"    "45"    "46"    "47"    "48"    "49"    "50"    "51"   "52"     "53"    "54"    "55"    "56"    "57"    "58"    "59"    "60"   "61"    "62"     "63"    "64"    "65"   "66"    "67"    "68"    "69"    "70"     "71" )
#			 	  declare -a dvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre" "GFalc" "GFasu" "GFahs" "GFano" "GFacl" "GFslc" "GFssu" "GFshs" "GFsno" "GFscl" "GFplc" "GFpsu" "GFphs" "GFpno" "GFpcl" "GFc01" "GFcsu" "GFc02" "GFcno" "GFccl" "GFm01" "GFmsu" "GFm02" "GFmno" "GFmcl" "LWtot" "LWaeq" "LWaer" "LWcld" "LWpre" "AWalc" "AWasu" "AWahs" "AWano" "AWacl" "AWslc" "AWssu" "AWshs" "AWsno" "AWscl" "AWplc" "AWpsu" "AWphs" "AWpno" "AWpcl" "AWc01" "AWcsu" "AWc02" "AWcno" "AWccl" "AWm01" "AWmsu" "AWm02" "AWmno" "AWmcl" "eq_TT" "eq_RH" "eq__P" "eq_ID" "eqPMt" "eqPMs" "eqsPM" "eqaPM" "eqRHO" "eq_Hp" "eq_GF")
				  declare -a dvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre" "GFalc" "GFasu" "GFahs" "GFano" "GFacl" "GFslc" "GFssu" "GFshs" "GFsno" "GFscl" "GFplc" "GFpsu" "GFphs" "GFpno" "GFpcl" "GFc01" "GFcsu" "GFc02" "GFcno" "GFccl" "GFm01" "GFmsu" "GFm02" "GFmno" "GFmcl" "LWtot" "LWaeq" "LWaer" "LWcld" "LWpre" "AWalc" "AWasu" "AWahs" "AWano" "AWacl" "AWslc" "AWssu" "AWshs" "AWsno" "AWscl" "AWplc" "AWpsu" "AWphs" "AWpno" "AWpcl" "AWc01" "AWcsu" "AWc02" "AWcno" "AWccl" "AWm01" "AWmsu" "AWm02" "AWmno" "AWmcl" "eqTT"  "eqRH"   "eqP"   "eqID" "eqPMt" "eqPMs" "eqsPM" "eqaPM" "eqRHO" "eqHp"  "eqGF")
#  				  declare -a nvars=(  "1"     "2"     "3"     "4"     "5"  )
#				  declare -a dvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre")
				  ;;
			  esac

			varn="$variable_rename"

			if [ "${ltype}" == "_pl" ]; then
			tfile=`echo $ncfile | sed "s|${ltype}\.nc|${ltype}_${varn}\.nc|g"`
			else
#			tfile=`echo $ncfile | sed "s|${ltype}\.nc|_${varn}\.nc|g"`
			tfile=`echo $ncfile | sed "s|${ltype}\.nc|${ltype}_${varn}\.nc|g"`
			fi

			if [ "${ltype}" == "_sfc" ]; then
			  setzaxis="-setzaxis,$tpath/zaxis1"
			else
			  setzaxis=""
			fi

			if [ -f "$tpath/$tfile" ]; then
				GO="NO"
			    log "renaming $ncvar_name of $ncfile to $tfile"
      log "Nothing to do, target file exists:"
      ls -lh $tpath/$tfile
    else
      log "renaming $ncvar_name of $ncfile to $tfile"
    fi

		  if [ "${GO}" == "GO" ]; then
		log  "----------------------------------------------------------------------------------------"
		# Build conditional chname operations based on what variables exist
		chname_ops=""
		# Check and rename level/lev
		if "$NCDUMP_CMD" -h "$ipath/$ncfile" 2>/dev/null | grep -q "float level("; then
		  chname_ops="${chname_ops} -chname,level,lev"
		fi
		# Check and rename longitude/lon
		if "$NCDUMP_CMD" -h "$ipath/$ncfile" 2>/dev/null | grep -q "float longitude("; then
		  chname_ops="${chname_ops} -chname,longitude,lon"
		fi
		# Check and rename latitude/lat
		if "$NCDUMP_CMD" -h "$ipath/$ncfile" 2>/dev/null | grep -q "float latitude("; then
		  chname_ops="${chname_ops} -chname,latitude,lat"
		fi
		# Always rename the target variable
		chname_ops="${chname_ops} -chname,$ncvar_name,${varn}"
		
		log  "$CDO_CMD ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$ncvar_name  $ipath/$ncfile $tpath/$tfile"
			  # Suppress HDF5 diagnostic messages (harmless pre-creation file checks)
			  "$CDO_CMD" ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$ncvar_name  $ipath/$ncfile $tpath/$tfile 2>&1 | grep -v -E "HDF5-DIAG|H5F\.|H5VL|H5FD|major:|minor:" || true
		ls -lh    $tpath/$tfile
		log  "----------------------------------------------------------------------------------------"
		fi # GO

#			log "add time average"
			xfile=`echo $tfile | sed "s|${varn}\.nc|${varn}_tavg\.nc|g"`
			if [ -f "$tpath/$xfile" ]; then
				log  "Nothing to do, target file exists: $tpath/$xfile"
			else
				log  "$CDO_CMD timavg $tpath/$tfile $tpath/$xfile"
					  "$CDO_CMD" timavg $tpath/$tfile $tpath/$xfile
			fi
			ls -lh $tpath/$xfile

		  if [ "${GO}" == "GO2" ]; then
			if [ ${#dvars[@]} -ne ${#nvars[@]} ]; then
			  log  "Error: Arrays have different lengths."
			  exit 1
			fi
			EQdiag="$tpath/$tfile"
			for ((i=0; i<${#dvars[@]}; i++)); do
			  dvar="${dvars[$i]}"
			  nvar="${nvars[$i]}"
  
			  log  "dvar: ${dvar}"
			  log  "nvar: ${nvar}"
					varn="${dvar}"
					lev="${nvar}"
					sellevel="-sellevel,${lev}"
		  tfile=`echo $ncfile | sed "s|${ltype}\.nc|_${varn}\.nc|g"`
		  if [ -f "$tpath/$tfile" ]; then
				log  "Nothing to do, target file exists: $tpath/$tfile"
		  else
			# Build conditional chname operations based on what variables exist
			chname_ops=""
			if "$NCDUMP_CMD" -h "$ipath/$ncfile" 2>/dev/null | grep -q "float level("; then
			  chname_ops="${chname_ops} -chname,level,lev"
			fi
			if "$NCDUMP_CMD" -h "$ipath/$ncfile" 2>/dev/null | grep -q "float longitude("; then
			  chname_ops="${chname_ops} -chname,longitude,lon"
			fi
			if "$NCDUMP_CMD" -h "$ipath/$ncfile" 2>/dev/null | grep -q "float latitude("; then
			  chname_ops="${chname_ops} -chname,latitude,lat"
			fi
			chname_ops="${chname_ops} -chname,$ncvar_name,${varn}"
			
		log  "$CDO_CMD ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$ncvar_name  $ipath/$ncfile $tpath/$tfile"
			  # Suppress HDF5 diagnostic messages (harmless pre-creation file checks)
			  "$CDO_CMD" ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$ncvar_name  $ipath/$ncfile $tpath/$tfile 2>&1 | grep -v -E "HDF5-DIAG|H5F\.|H5VL|H5FD|major:|minor:|#[0-9]{3}:" || true
		  fi
		  ls -lh $tpath/$tfile

#			  log "add time average"
		      xfile=`echo $tfile | sed "s|${varn}\.nc|${varn}_tavg\.nc|g"`
			  if [ -f "$tpath/$xfile" ]; then
				 log  "Nothing to do, target file exists: $tpath/$xfile"
			  else
				 log  "$CDO_CMD timavg $tpath/$tfile $tpath/$xfile"
				   	   "$CDO_CMD" timavg $tpath/$tfile $tpath/$xfile
			  fi
			  ls -lh $tpath/$xfile

			done
			# link last entry to EQdiag.nc
			ln -s    $tpath/$tfile $EQdiag
#			ln -s    $tpath/$xfile $EQdiag_tavg
		  fi

		  if [ "${GO}" == "GO" ] || [ "${GO}" == "GO2" ] ;then
			log  "----------------------------------------------------------------------------------------"
			log  "rm  $ipath/$ncfile"
			#	  rm  $ipath/$ncfile
			log  "----------------------------------------------------------------------------------------"
		  fi # GO/GO2

    log  "----------------------------------------------------------------------------------------"
  done # ncfile loop
  
  fi # if ncfiles found

done # exps

log "$ipath"
log "$tpath"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
