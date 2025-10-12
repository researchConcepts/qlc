#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Process NC-files (converted grib files of MARS_RETRIEVALS as specified in $CONFIG_FILE) "
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
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

  ipath="$MARS_RETRIEVAL_DIRECTORY/$exp"
  tpath="$ANALYSIS_DIRECTORY/$exp"

  # Create output directory if not existent
  if [  ! -d "$tpath" ]; then
    mkdir -p "$tpath"
  fi

  log  "----------------------------------------------------------------------------------------"

  for name in "${MARS_RETRIEVALS[@]}"; do

	  # Define the corresponding arrays based on the name
	  param_var="param_${name}[@]"
	  ncvar_var="ncvar_${name}[@]"
	  myvar_var="myvar_${name}[@]"

	  # Use variable indirection to access the arrays
	  param=("${!param_var}")
	  ncvar=("${!ncvar_var}")
	  myvar=("${!myvar_var}")

	  log "ipath : ${ipath}"
	  log "tpath : ${tpath}"

	  log "name : ${name}"
	  log "param: ${param[*]}"
	  log "ncvar: ${ncvar[*]}"
	  log "myvar: ${myvar[*]}"

	  cd $ipath
      pwd -P

	  set +e
	  # List available NC-files
#	  ncfiles=($(ls *${mDate}*_${name}_*.nc 2>/dev/null))
	  ncfiles=($(ls *${mDate}*_${name}*.nc 2>/dev/null))
	  set -e

	  log "ncfiles : ${ncfiles}"

	  cd $tpath
      pwd -P

	  # Loop through the variables for this $name
	  for ((i = 0; i < ${#ncvar[@]}; i++)); do
		ncvar_name="${ncvar[i]}"
		myvar_name="${myvar[i]}"
	  	log "ncvar_name: ${ncvar_name}"
	  	log "myvar_name: ${myvar_name}"

	  if [ ${#ncfiles[@]} -eq 0 ]; then
		log "No NC-files found in $MARS_RETRIEVAL_DIRECTORY/$exp"
	  else
		log "Files to process: ${ncfiles[@]}"
		log  "----------------------------------------------------------------------------------------"
		for file in "${ncfiles[@]}"; do
#		  log    "$file"
		  ncfile="$file"

		  vars="$(ncdump -h "$ipath/$ncfile" | grep float | sed 's|(| |g' | awk '{printf("%20s", $2)}')"
		  log "nc-file variables: $vars"

		  # Extract the data level type
		  ltype="_$(echo "$file" | awk -F'_' '{print $4}' | cut -d'.' -f1)"
		  log "Data level type: $ltype - $file / $exp"

		  cdo zaxisdes $ipath/$ncfile > $tpath/zaxisdes
		  head -61                      $tpath/zaxisdes > $tpath/zaxis1

		  for var in ${vars[@]}; do

			GO="NO"
			setctomiss="setctomiss,-999"
			sellevel=""
		  	log "var: ${var}"

		    if [ "$ncvar_name" == "$var" ]; then
			  variable_rename="$myvar_name"
			  log "ncvar_name / myvar_name: $ncvar_name / $variable_rename"
			  GO="GO"
		    fi

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

			if [ -f "$tpath/$tfile" ] && [ "$ncvar_name" == "$var" ]; then
				GO="NO"
			    log "renaming $ncvar_name of $ncfile to $tfile"
				log "Nothing to do, target file exists:"
				ls -lh $tpath/$tfile
			elif [ ! -f "$tpath/$tfile" ] && [ "$ncvar_name" == "$var" ]; then
			    log "renaming $ncvar_name of $ncfile to $tfile"
				log    $tpath/zaxis1
				cat    $tpath/zaxis1
#			else
#			    log "No renaming for $ncvar_name != $var of $ncfile to $tfile"
			fi

		  if [ "${GO}" == "GO" ]; then
		log  "----------------------------------------------------------------------------------------"
		# Build conditional chname operations based on what variables exist
		chname_ops=""
		# Check and rename level/lev
		if ncdump -h "$ipath/$ncfile" 2>/dev/null | grep -q "float level("; then
		  chname_ops="${chname_ops} -chname,level,lev"
		fi
		# Check and rename longitude/lon
		if ncdump -h "$ipath/$ncfile" 2>/dev/null | grep -q "float longitude("; then
		  chname_ops="${chname_ops} -chname,longitude,lon"
		fi
		# Check and rename latitude/lat
		if ncdump -h "$ipath/$ncfile" 2>/dev/null | grep -q "float latitude("; then
		  chname_ops="${chname_ops} -chname,latitude,lat"
		fi
		# Always rename the target variable
		chname_ops="${chname_ops} -chname,$var,${varn}"
		
		log  "cdo ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$var  $ipath/$ncfile $tpath/$tfile"
			  # Suppress HDF5 diagnostic messages (harmless pre-creation file checks)
			  cdo ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$var  $ipath/$ncfile $tpath/$tfile 2>&1 | grep -v -E "HDF5-DIAG|H5F\.|H5VL|H5FD|major:|minor:" || true
		ls -lh    $tpath/$tfile
		log  "----------------------------------------------------------------------------------------"
		fi # GO

#			log "add time average"
			xfile=`echo $tfile | sed "s|${varn}\.nc|${varn}_tavg\.nc|g"`
			if [ -f "$tpath/$xfile" ]; then
				log  "Nothing to do, target file exists: $tpath/$xfile"
			else
				log  "cdo timavg $tpath/$tfile $tpath/$xfile"
					  cdo timavg $tpath/$tfile $tpath/$xfile
			fi
			ls -lh $tpath/$xfile

		  done # var

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
			if ncdump -h "$ipath/$ncfile" 2>/dev/null | grep -q "float level("; then
			  chname_ops="${chname_ops} -chname,level,lev"
			fi
			if ncdump -h "$ipath/$ncfile" 2>/dev/null | grep -q "float longitude("; then
			  chname_ops="${chname_ops} -chname,longitude,lon"
			fi
			if ncdump -h "$ipath/$ncfile" 2>/dev/null | grep -q "float latitude("; then
			  chname_ops="${chname_ops} -chname,latitude,lat"
			fi
			chname_ops="${chname_ops} -chname,$var,${varn}"
			
		log  "cdo ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$var  $ipath/$ncfile $tpath/$tfile"
			  # Suppress HDF5 diagnostic messages (harmless pre-creation file checks)
			  cdo ${setctomiss} ${setzaxis} -setcalendar,standard ${chname_ops} ${sellevel} -selvar,$var  $ipath/$ncfile $tpath/$tfile 2>&1 | grep -v -E "HDF5-DIAG|H5F\.|H5VL|H5FD|major:|minor:|#[0-9]{3}:" || true
		  fi
		  ls -lh $tpath/$tfile

#			  log "add time average"
		      xfile=`echo $tfile | sed "s|${varn}\.nc|${varn}_tavg\.nc|g"`
			  if [ -f "$tpath/$xfile" ]; then
				 log  "Nothing to do, target file exists: $tpath/$xfile"
			  else
				 log  "cdo timavg $tpath/$tfile $tpath/$xfile"
				  	   cdo timavg $tpath/$tfile $tpath/$xfile
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

		done # file
		log  "----------------------------------------------------------------------------------------"
	  fi

 	  done # ncvar
  done # name
done # exps

log "$ipath"
log "$tpath"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
