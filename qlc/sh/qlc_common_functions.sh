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


