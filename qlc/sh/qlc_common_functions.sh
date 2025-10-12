#!/bin/bash

# Source the configuration file to load the settings
. "$CONFIG_FILE"

#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
#log  "----------------------------------------------------------------------------------------"

myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`

# Function to log messages to a file
log() {
  # Create a log message and write to stdout and log file
  # We use a subshell to ensure all output is captured and redirected atomically
  (
      local log_message
      log_message=$(printf "[%s] %s" "$(date +"%Y-%m-%d %H:%M:%S")" "$*")
      echo "$log_message"
  )
}

# Function to check if argument is a date (matches YYYY-MM-DD pattern)
is_date() {
  local arg="$1"
  if [ ${#arg} -eq 10 ] && [ "${arg:4:1}" = "-" ] && [ "${arg:7:1}" = "-" ]; then
    local year="${arg:0:4}"
    local month="${arg:5:2}"
    local day="${arg:8:2}"
    if [ "$year" -eq "$year" ] 2>/dev/null && [ "$month" -eq "$month" ] 2>/dev/null && [ "$day" -eq "$day" ] 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Function to parse QLC command line arguments
# Usage: parse_qlc_arguments "$@"
# Sets global variables: experiments (array), sDat, eDat, config_arg
parse_qlc_arguments() {
  log "Parsing command line arguments..."
  
  # Check minimum number of arguments
  if [ $# -lt 3 ]; then
    log "Error: Insufficient arguments. Expected: <exp1> [exp2 ...] <start_date> <end_date> [config]"
    return 1
  fi
  
  # Parse arguments from the end to handle variable number of experiments
  local args=("$@")
  local num_args=$#
  
  # Determine if last argument is a config name (not a date)
  config_arg=""
  local end_idx=$num_args
  if [ $num_args -ge 5 ] && ! is_date "${args[$((num_args-1))]}"; then
    # Last arg is config name - store it and adjust parsing
    config_arg="${args[$((num_args-1))]}"
    end_idx=$((num_args-1))
    log "Config argument detected: $config_arg"
  fi
  
  # Now parse: everything before the last two items are experiments, last two are dates
  if [ $end_idx -lt 3 ]; then
    log "Error: Insufficient arguments after removing config"
    return 1
  fi
  
  eDat="${args[$((end_idx-1))]}"
  sDat="${args[$((end_idx-2))]}"
  
  # Validate dates
  if ! is_date "$sDat" || ! is_date "$eDat"; then
    log "Error: Invalid date format. Expected YYYY-MM-DD"
    log "Got start_date='$sDat', end_date='$eDat'"
    return 1
  fi
  
  # Everything before the dates are experiments
  experiments=()
  for ((i=0; i<end_idx-2; i++)); do
    experiments+=("${args[$i]}")
  done
  
  # Validate we have at least one experiment
  if [ ${#experiments[@]} -eq 0 ]; then
    log "Error: At least one experiment must be specified"
    return 1
  fi
  
  log "Found ${#experiments[@]} experiment(s): ${experiments[*]}"
  log "Start date: $sDat"
  log "End date: $eDat"
  
  return 0
}

# Define the sorting function
sort_files() {
    local script_name="$1"
    local exp1="$2"
    local exp2="$3"
    local files_list="$4"
    local ext="$5"
    local hpath="$6"
    local fnam
    local fvar
    local sorted_file_list="${hpath}/sorted_files_${script_name}.list"
    local temp_file_list="${hpath}/temp_file_list_${script_name}.list"
    local variable_list="${hpath}/var_list_${script_name}.list"

    # Initialize arrays
    fnam=()
    
    # workaround for system dependency (obsolete)
	if [ "${myOS}" == "Darwin" ]; then
#		var_element=9
#		exp_element=10
		var_element=7
		exp_element=8
	else
		var_element=7
		exp_element=8
	fi

    # Read the list of files from the file list
    while read -r file; do
        fnam+=("$file")
        # Extract the variable name from the file name
        IFS="_" read -ra parts <<< "$file"
        var="${parts[$var_element]}"
        fvar+=("$var")
        vars+=" $var"  # Create a space-separated list of variable names
#       echo "file $file"
#       echo "var  $var"
    done < "$files_list"

    # Get unique variable list
    echo "$vars" | tr ' ' '\n' | sort -u > $variable_list
    var_list="`cat $variable_list`"
#   echo $var_list

	set -f  # Disable globbing

	# Split the var_list string into separate variables
	set -- $var_list

	# Create an array to store the variables
	variables=()

	# Store all variables from the var_list in the array
	while [ "$#" -ge 1 ]; do
		variables+=("$1")
		shift
	done

	# Loop through the variables
	for file_var in "${variables[@]}"; do
		# Loop through the files and populate the temporary file
		for file_nam in "${fnam[@]}"; do
			fxxx="$file_nam"
			# Extract the file name without directory and extension
			file_xxx="${fxxx##*/}"  # Remove directory path
			file_yyy="${file_xxx%.*}"  # Remove extension

			# Split the file name into parts
			IFS="_" read -ra parts <<< "$file_yyy"

			tvar="${parts[$var_element]}"
			texp="${parts[$exp_element]}"
			ftype="$(echo "${parts[@]:$exp_element}.${ext}2" | sed 's| |_|g')"

			if [ "$file_var" == "$tvar" ]; then
#				echo "Processing file: $file_nam"
				echo "$file_nam $ftype" >> "${temp_file_list}_${file_var}.$$"
#				ls -lh                      ${temp_file_list}_${file_var}.$$
			fi
		done
	done

	set +f  # Enable globbing

    # Define the desired sorting order
#   sorting_order=("${exp1}.${ext}2" "${exp2}.${ext}2" "${exp2}_diff.${ext}2" "${exp1}_log.${ext}2" "${exp2}_log.${ext}2" "${exp2}_log_diff.${ext}2")
#   sorting_order=("${exp1}.${ext}2" "${exp2}.${ext}2" "${exp1}_diff.${ext}2" "${exp1}_log.${ext}2" "${exp2}_log.${ext}2" "${exp1}_log_diff.${ext}2")
    sorting_order=("${exp1}_surface.${ext}2" "${exp2}_surface.${ext}2" "${exp1}_surface_diff.${ext}2" "${exp1}_surface_log.${ext}2" "${exp2}_surface_log.${ext}2" "${exp1}_surface_log_diff.${ext}2" \
                   "${exp1}_burden.${ext}2" "${exp2}_burden.${ext}2" "${exp1}_burden_diff.${ext}2" "${exp1}_burden_log.${ext}2" "${exp2}_burden_log.${ext}2" "${exp1}_burden_log_diff.${ext}2" \
                   "${exp1}_meridional.${ext}2" "${exp2}_meridional.${ext}2" "${exp1}_meridional_diff.${ext}2" "${exp1}_meridional_log.${ext}2" "${exp2}_meridional_log.${ext}2" "${exp1}_meridional_log_diff.${ext}2" \
                   "${exp1}_zonal.${ext}2" "${exp2}_zonal.${ext}2" "${exp1}_zonal_diff.${ext}2" "${exp1}_zonal_log.${ext}2" "${exp2}_zonal_log.${ext}2" "${exp1}_zonal_log_diff.${ext}2" \
                   "${exp1}_utls.${ext}2" "${exp2}_utls.${ext}2" "${exp1}_utls_diff.${ext}2" "${exp1}_utls_log.${ext}2" "${exp2}_utls_log.${ext}2" "${exp1}_utls_log_diff.${ext}2" \
                   )

	# Sort the temporary files and write the sorted files to sorted_file.list
	for file_var in "${variables[@]}"; do
		for type in "${sorting_order[@]}"; do
			grep -w "$type" "${temp_file_list}_${file_var}.$$" | sed "s|$type||g" >> "${sorted_file_list}_${file_var}.$$"
		done
#		ls -lh                                                                        ${sorted_file_list}_${file_var}.$$
	done
	# Concatenate the sorted files into the final sorted_file_list
	cat "${sorted_file_list}"*".$$" > "$sorted_file_list"
#	ls -lh  "$sorted_file_list"

    sorted_list="$(cat "$sorted_file_list")"

#   echo "Sorted file list: $sorted_file_list"
#   echo "$sorted_list"

    # Clean up the temporary file
    rm -f ${sorted_file_list}*.$$ ${temp_file_list}*.$$
}

# Custom function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}


