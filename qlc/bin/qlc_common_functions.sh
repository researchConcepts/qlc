#!/bin/bash

# ============================================================================
# QLC Common Functions: Shared Utilities and Environment Management
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Provides shared utility functions for all QLC workflow scripts including
#   logging, environment setup, module loading, tool detection, argument
#   parsing, and configuration management.
#
# Usage:
#   Sourced automatically by all QLC scripts
#   Do not execute directly
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Source the configuration file to load the settings (if available)
if [ -n "${CONFIG_FILE:-}" ] && [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

umask 0022

ARCH="`uname -m`"
myOS="`uname -s`"
#HOST="`hostname -s  | awk '{printf $1}' | cut -c 1`"
HOST="`hostname -s`"
CUSR="`echo $USER`"

# Function to log messages with consistent timestamp and optional tag format
# Usage: log "message"                    -> [2025-11-15 21:01:38] message
#        log "[QLC]" "message"            -> [2025-11-15 21:01:38] [QLC] message
#        log "[QLC-DEV]" "message"        -> [2025-11-15 21:01:38] [QLC-DEV] message
log() {
  local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
  local tag=""
  local message=""
  
  # Check if first argument is a tag (starts with [ and ends with ])
  if [[ "$1" =~ ^\[.*\]$ ]]; then
    tag="$1 "
    shift
  fi
  
  message="$*"
  printf "[%s] %s%s\n" "$timestamp" "$tag" "$message"
}

# Function to source the main qlc.conf configuration file
# This provides access to variable mappings (param_*, ncvar_*, myvar_*)
# Usage: source_qlc_conf
source_qlc_conf() {
  # Try multiple paths to find qlc.conf
  local qlc_conf_path=""
  
  # Option 1: CONFIG_DIR is set and qlc.conf is in the same directory
  if [ -n "${CONFIG_DIR}" ] && [ -f "${CONFIG_DIR}/qlc.conf" ]; then
    qlc_conf_path="${CONFIG_DIR}/qlc.conf"
  # Option 2: CONFIG_DIR is set and qlc.conf is one level up
  elif [ -n "${CONFIG_DIR}" ] && [ -f "${CONFIG_DIR}/../qlc.conf" ]; then
    qlc_conf_path="${CONFIG_DIR}/../qlc.conf"
  # Option 3: Relative to this script (bin/../config/qlc.conf)
  elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../config/qlc.conf" ]; then
    qlc_conf_path="$(dirname "${BASH_SOURCE[0]}")/../config/qlc.conf"
  # Option 4: QLC_HOME is set
  elif [ -n "${QLC_HOME}" ] && [ -f "${QLC_HOME}/config/qlc.conf" ]; then
    qlc_conf_path="${QLC_HOME}/config/qlc.conf"
  fi
  
  if [ -n "$qlc_conf_path" ]; then
    source "$qlc_conf_path"
    log "Loaded qlc.conf from $qlc_conf_path"
    return 0
  else
    log "WARNING: Could not find qlc.conf - variable mappings may not be available"
    return 1
  fi
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
# Sets global variables: experiments (array), sDat, eDat, config_arg, class_override (array)
parse_qlc_arguments() {
  log "Parsing command line arguments..."
  
  # Check minimum number of arguments
  # Minimum: 2 arguments for obs-only mode (start_date end_date)
  # Normal: 3+ arguments (exp1 start_date end_date [config] [options])
  if [ $# -lt 2 ]; then
    log "Error: Insufficient arguments."
    log "Usage: <exp1> [expN ...] <start_date> <end_date> [config] [options]"
    log "   or: <start_date> <end_date> [config] [options]  (obs-only mode)"
    return 1
  fi
  
  # Parse arguments and filter out options
  local args=()
  local class_arg=""
  class_override=()
  
  # First pass: extract options and build clean args array
  for arg in "$@"; do
    # Filter out mode flags (no value)
    if [[ "$arg" == "--obs-only" ]] || [[ "$arg" == "-obs-only" ]] || \
       [[ "$arg" == "--obs_only" ]] || [[ "$arg" == "-obs_only" ]] || \
       [[ "$arg" == "--mod-only" ]] || [[ "$arg" == "-mod-only" ]] || \
       [[ "$arg" == "--mod_only" ]] || [[ "$arg" == "-mod_only" ]]; then
      log "Mode flag detected: $arg (handled by Python)"
    # Filter out new named arguments (with values)
    elif [[ "$arg" == --exp_ids=* ]] || [[ "$arg" == -exp_ids=* ]] || \
         [[ "$arg" == --start_date=* ]] || [[ "$arg" == -start_date=* ]] || \
         [[ "$arg" == --start=* ]] || [[ "$arg" == -start=* ]] || \
         [[ "$arg" == --end_date=* ]] || [[ "$arg" == -end_date=* ]] || \
         [[ "$arg" == --end=* ]] || [[ "$arg" == -end=* ]] || \
         [[ "$arg" == --workflow=* ]] || [[ "$arg" == -workflow=* ]] || \
         [[ "$arg" == --region=* ]] || [[ "$arg" == -region=* ]] || \
         [[ "$arg" == --exp_labels=* ]] || [[ "$arg" == -exp_labels=* ]] || \
         [[ "$arg" == --station_selection=* ]] || [[ "$arg" == -station_selection=* ]] || \
         [[ "$arg" == --observation=* ]] || [[ "$arg" == -observation=* ]] || \
         [[ "$arg" == --obs_path=* ]] || [[ "$arg" == -obs_path=* ]] || \
         [[ "$arg" == --exp_path=* ]] || [[ "$arg" == -exp_path=* ]] || \
         [[ "$arg" == --mod_path=* ]] || [[ "$arg" == -mod_path=* ]]; then
      log "Named argument detected: $arg (handled by Python)"
    # Filter out class override
    elif [[ "$arg" == -class=* ]] || [[ "$arg" == --class=* ]]; then
      class_arg="${arg#*=}"
      log "Class override option detected: -class=$class_arg"
    # Filter out variable specification
    elif [[ "$arg" == -vars=* ]] || [[ "$arg" == --vars=* ]]; then
      log "Variables override option: $arg (handled by Python)"
    elif [[ "$arg" == -nml=* ]] || [[ "$arg" == --nml=* ]]; then
      log "Namelist override option: $arg"
    # Filter out script selection
    elif [[ "$arg" == -scripts=* ]] || [[ "$arg" == --scripts=* ]]; then
      log "Workflow scripts override: $arg"
    # Filter out MARS parameter overrides
    elif [[ "$arg" == -grid=* ]] || [[ "$arg" == --grid=* ]] || \
         [[ "$arg" == -step=* ]] || [[ "$arg" == --step=* ]] || \
         [[ "$arg" == -time=* ]] || [[ "$arg" == --time=* ]] || \
         [[ "$arg" == -type=* ]] || [[ "$arg" == --type=* ]] || \
         [[ "$arg" == -stream=* ]] || [[ "$arg" == --stream=* ]] || \
         [[ "$arg" == -levelist=* ]] || [[ "$arg" == --levelist=* ]] || \
         [[ "$arg" == -resol=* ]] || [[ "$arg" == --resol=* ]] || \
         [[ "$arg" == -area=* ]] || [[ "$arg" == --area=* ]] || \
         [[ "$arg" == -number=* ]] || [[ "$arg" == --number=* ]]; then
      log "MARS parameter override: $arg (handled by Python)"
    # Filter out expert mode options
    elif [[ "$arg" == -param=* ]] || [[ "$arg" == --param=* ]] || \
         [[ "$arg" == -ncvar=* ]] || [[ "$arg" == --ncvar=* ]] || \
         [[ "$arg" == -myvar=* ]] || [[ "$arg" == --myvar=* ]] || \
         [[ "$arg" == -levtype=* ]] || [[ "$arg" == --levtype=* ]]; then
      log "Expert mode option: $arg"
    else
      # Positional argument - keep it
      args+=("$arg")
    fi
  done
  
  local num_args=${#args[@]}
  
  # Determine if last argument is a config name (not a date)
  # Check if last argument exists and is not a date format
  config_arg=""
  local end_idx=$num_args
  if [ $num_args -ge 3 ] && ! is_date "${args[$((num_args-1))]}"; then
    # Last arg is config name - store it and adjust parsing
    config_arg="${args[$((num_args-1))]}"
    end_idx=$((num_args-1))
    log "Config argument detected: $config_arg"
  fi
  
  # Now parse: everything before the last two items are experiments, last two are dates
  # Allow 2 arguments minimum (obs-only mode: start_date end_date)
  if [ $end_idx -lt 2 ]; then
    log "Error: Insufficient arguments after removing config (need at least start_date and end_date)"
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
  # Store original experiment arguments (including "None") for directory naming
  experiments_original=()
  for ((i=0; i<end_idx-2; i++)); do
    experiments_original+=("${args[$i]}")
  done
  
  # Filter out "None" (case-insensitive) placeholder entries for actual processing
  experiments=()
  for ((i=0; i<end_idx-2; i++)); do
    # Convert to lowercase for comparison (case-insensitive "None" check)
    arg_lower=$(echo "${args[$i]}" | tr '[:upper:]' '[:lower:]')
    if [ "$arg_lower" != "none" ]; then
      experiments+=("${args[$i]}")
    else
      log "Skipping placeholder: ${args[$i]} (treated as 'no experiment')"
    fi
  done
  
  # Create directory-safe experiment string (preserves "None" placeholders)
  if [ ${#experiments_original[@]} -gt 0 ]; then
    experiments_dirname=$(IFS=-; echo "${experiments_original[*]}")
  else
    experiments_dirname="None"
  fi
  export experiments_dirname
  log "Directory name will use: ${experiments_dirname}"
  
  # Allow zero experiments (for obs-only mode), one experiment (quick tests), or multiple experiments
  # No validation error if experiments array is empty
  
  # Process class override if provided
  if [ -n "$class_arg" ]; then
    # Validate: class override only valid when experiments are specified
    if [ ${#experiments[@]} -eq 0 ]; then
      log "Error: Class override (-class=) cannot be used without experiments (obs-only mode)"
      return 1
    fi
    
    # Split comma-separated values into array
    IFS=',' read -ra class_override <<< "$class_arg"
    
    # Validate: must be either 1 (apply to all) or match number of experiments
    if [ ${#class_override[@]} -eq 1 ]; then
      log "Class override: ${class_override[0]} (will be applied to all experiments)"
    elif [ ${#class_override[@]} -eq ${#experiments[@]} ]; then
      log "Class override: ${class_override[*]} (one per experiment)"
    else
      log "Error: Number of classes (${#class_override[@]}) must be 1 or match number of experiments (${#experiments[@]})"
      return 1
    fi
  fi
  
  # Log parsing results
  if [ ${#experiments[@]} -eq 0 ]; then
    log "Running in OBS-ONLY mode (no experiments specified)"
  else
    log "Found ${#experiments[@]} experiment(s): ${experiments[*]}"
  fi
  log "Start date: $sDat"
  log "End date: $eDat"
  
  # Set exp1 and expN for backward compatibility
  # These can be used by scripts to simplify logic
  # - exp1: First experiment (or empty if no experiments)
  # - expN: Reference experiment (last) for diff plots (or empty if only one experiment or no experiments)
  if [ ${#experiments[@]} -eq 0 ]; then
    # No experiments (obs-only mode)
    exp1=""
    expN=""
    log "exp1: (empty - obs-only mode)"
    log "expN: (empty - obs-only mode)"
  elif [ ${#experiments[@]} -eq 1 ]; then
    # Single experiment: no diff plots needed
    exp1="${experiments[0]}"
    expN=""
    log "exp1: $exp1 (single experiment, no diff plots)"
    log "expN: (empty - single experiment mode)"
  else
    # Multiple experiments: expN is reference (last) for diff plots
    exp1="${experiments[0]}"
    expN="${experiments[$((${#experiments[@]}-1))]}"
    log "exp1: $exp1"
    log "expN: $expN (reference/last for diff plots)"
  fi
  
  # Process mode flags from environment (set by Python wrapper)
  # These flags force specific processing modes regardless of other settings
  if [ -n "${QLC_MODE_OBS_ONLY:-}" ]; then
    log "Mode flag detected: --obs-only (forced observation-only mode)"
    export QLC_MODE_OBS_ONLY
  fi
  
  if [ -n "${QLC_MODE_MOD_ONLY:-}" ]; then
    log "Mode flag detected: --mod-only (forced model-only mode)"
    export QLC_MODE_MOD_ONLY
  fi
  
  # Process additional CLI parameters from environment (set by Python wrapper)
  if [ -n "${QLC_CLI_REGION:-}" ]; then
    log "CLI parameter: --region=${QLC_CLI_REGION}"
    export QLC_CLI_REGION
  fi
  
  if [ -n "${QLC_CLI_EXP_LABELS:-}" ]; then
    log "CLI parameter: --exp_labels=${QLC_CLI_EXP_LABELS}"
    export QLC_CLI_EXP_LABELS
  fi
  
  if [ -n "${QLC_CLI_STATION_SELECTION:-}" ]; then
    log "CLI parameter: --station_selection=${QLC_CLI_STATION_SELECTION}"
    export QLC_CLI_STATION_SELECTION
  fi
  
  if [ -n "${QLC_CLI_OBSERVATION:-}" ]; then
    log "CLI parameter: --observation=${QLC_CLI_OBSERVATION}"
    export QLC_CLI_OBSERVATION
  fi
  
  if [ -n "${QLC_CLI_OBS_PATH:-}" ]; then
    log "CLI parameter: --obs_path=${QLC_CLI_OBS_PATH}"
    export QLC_CLI_OBS_PATH
  fi
  
  if [ -n "${QLC_CLI_EXP_PATH:-}" ]; then
    log "CLI parameter: --exp_path=${QLC_CLI_EXP_PATH}"
    export QLC_CLI_EXP_PATH
  fi
  
  if [ -n "${QLC_CLI_SCRIPTS:-}" ]; then
    log "CLI parameter: --scripts=${QLC_CLI_SCRIPTS}"
    export QLC_CLI_SCRIPTS
  fi
  
  return 0
}

# Define the sorting function
sort_files() {
    local script_name="$1"
    local exp1="$2"
    local expN="$3"
    local files_list="$4"
    local ext="$5"
    local hpath="$6"
    local varname="${7:-}"  # Optional variable name parameter
    local exp1_name="$2"     # Experiment name for per-experiment file
    local fnam
    # Use variable and experiment-specific sorted file name
    # This allows multiple experiments to be processed separately, then combined
    if [ -n "$varname" ]; then
        local sorted_file_list="${hpath}/sorted_files_${script_name}_${varname}_${exp1_name}.list"
        local temp_file_list="${hpath}/temp_file_list_${script_name}_${varname}_${exp1_name}.list"
    else
        local sorted_file_list="${hpath}/sorted_files_${script_name}_${exp1_name}.list"
        local temp_file_list="${hpath}/temp_file_list_${script_name}_${exp1_name}.list"
    fi

    # Initialize arrays
    fnam=()
    
    # Clear temp file at start (remove any existing temp files for this variable)
    rm -f "${temp_file_list}".* "${sorted_file_list}"

    # Read the list of files from the file list
    # Since we're now using per-variable lists, all files are for the same variable
    # We just need to extract experiment and plot type for sorting
    while read -r file; do
        fnam+=("$file")
    done < "$files_list"

	set -f  # Disable globbing

	# Process all files (they're all for the same variable in per-variable lists)
	# Extract experiment and plot type for sorting
	# Note: Variable name is known from config, so we don't extract it
	# We find experiment by matching against known experiments (exp1, expN)
	for file_nam in "${fnam[@]}"; do
		fxxx="$file_nam"
		# Extract the file name without directory and extension
		file_xxx="${fxxx##*/}"  # Remove directory path
		file_yyy="${file_xxx%.*}"  # Remove extension

		# If variable name contains underscores, temporarily replace them with dashes
		# in the filename before splitting, so the variable stays as one part
		# This doesn't change the actual filename, just the parsing string
		local file_yyy_for_split="$file_yyy"
		if [ -n "$varname" ]; then
			# Use function to convert variable name underscores to dashes
			local varname_dash=$(var_name_for_parsing "$varname")
			# Replace the variable name in filename with dash version
			file_yyy_for_split="${file_yyy_for_split//${varname}/${varname_dash}}"
		fi

		# Split the file name into parts (using modified version for parsing)
		IFS="_" read -ra parts <<< "$file_yyy_for_split"
		
		# Find experiment in filename (variable may contain underscores, so we search)
		# Known structure: {TEAM}_{experiments}_{mDate}_{QLTYPE}_{levtype}_{variable}_{exp}_{plottype}
		# For C1-GLOB: levtype is at parts[5], then variable (variable length), then experiment
		# For other scripts: similar but different index
		exp_idx=-1
		plot_type_idx=-1
		
		# Find experiment by matching against known experiments (exp1, expN)
		# Start searching after QLTYPE (which may be split: "qlc" and "C1-GLOB")
		start_idx=5  # After levtype for C1-GLOB
		if [[ "${script_name}" != *"C1-GLOB"* ]]; then
			start_idx=6  # Different structure for other scripts
		fi
		
		for i in "${!parts[@]}"; do
			if [ $i -lt $start_idx ]; then
				continue  # Skip prefix parts
			fi
			# Check if this part matches exp1 or expN (skip expN if empty - single experiment mode)
			if [ "${parts[$i]}" == "$exp1" ]; then
				exp_idx=$i
				plot_type_idx=$((i + 1))
				break
			elif [ -n "$expN" ] && [ "${parts[$i]}" == "$expN" ]; then
				exp_idx=$i
				plot_type_idx=$((i + 1))
				break
			fi
		done
		
		# Extract experiment and plot type
		if [ $exp_idx -ge 0 ]; then
			texp="${parts[$exp_idx]}"
			# ftype should match sorting_order pattern: {exp}_{plottype}[_{log}][_{diff}].{ext}2
			# Include experiment name and plot type with optional suffixes
			ftype="$(echo "${parts[@]:$exp_idx}.${ext}2" | sed 's| |_|g')"
		else
			# Could not find experiment - skip this file (it's from a different experiment)
			# This is normal when var_plot_list contains files from multiple experiments
			continue
		fi

		# Filter: only process files that match the current experiment (exp1) or reference (expN)
		# Skip files from other experiments
		if [ "$texp" != "$exp1" ] && [ "$texp" != "$expN" ]; then
			# File is from a different experiment - skip it
			continue
		fi

		# All files are for the same variable, so no need to filter by variable
		# Use a single temp file since all files are for one variable
		echo "$file_nam $ftype" >> "${temp_file_list}.$$"
	done

	set +f  # Enable globbing

    # Define the desired sorting order
    # Handle both single-experiment and multi-experiment cases
    # Parameters: exp1=$2 (current exp), expN=$3 (reference exp)
    if [ -z "$expN" ] || [ "$exp1" == "$expN" ]; then
        # Single experiment mode OR sorting the reference experiment:
        # Only include exp1 patterns (no diff plots - those are in non-reference folders)
        sorting_order=("${exp1}_surface.${ext}2" "${exp1}_surface_log.${ext}2" \
                       "${exp1}_burden.${ext}2" "${exp1}_burden_log.${ext}2" \
                       "${exp1}_meridional.${ext}2" "${exp1}_meridional_log.${ext}2" \
                       "${exp1}_zonal.${ext}2" "${exp1}_zonal_log.${ext}2" \
                       "${exp1}_utls.${ext}2" "${exp1}_utls_log.${ext}2" \
                       )
    else
        # Multi-experiment mode for non-reference experiment:
        # Include current experiment, reference experiment, and diff plots
        # This handles 2, 3, 4, ... N experiments correctly
        sorting_order=("${exp1}_surface.${ext}2" "${expN}_surface.${ext}2" "${exp1}_surface_diff.${ext}2" "${exp1}_surface_log.${ext}2" "${expN}_surface_log.${ext}2" "${exp1}_surface_log_diff.${ext}2" \
                       "${exp1}_burden.${ext}2" "${expN}_burden.${ext}2" "${exp1}_burden_diff.${ext}2" "${exp1}_burden_log.${ext}2" "${expN}_burden_log.${ext}2" "${exp1}_burden_log_diff.${ext}2" \
                       "${exp1}_meridional.${ext}2" "${expN}_meridional.${ext}2" "${exp1}_meridional_diff.${ext}2" "${exp1}_meridional_log.${ext}2" "${expN}_meridional_log.${ext}2" "${exp1}_meridional_log_diff.${ext}2" \
                       "${exp1}_zonal.${ext}2" "${expN}_zonal.${ext}2" "${exp1}_zonal_diff.${ext}2" "${exp1}_zonal_log.${ext}2" "${expN}_zonal_log.${ext}2" "${exp1}_zonal_log_diff.${ext}2" \
                       "${exp1}_utls.${ext}2" "${expN}_utls.${ext}2" "${exp1}_utls_diff.${ext}2" "${exp1}_utls_log.${ext}2" "${expN}_utls_log.${ext}2" "${exp1}_utls_log_diff.${ext}2" \
                       )
    fi

	# Sort the files and write to sorted_file.list
	# Since all files are for the same variable, use single temp file
	if [ -f "${temp_file_list}.$$" ]; then
		# Create a temporary file to track which files have been matched
		local matched_files="${temp_file_list}.matched.$$"
		touch "${matched_files}"
		
		# First, match files against known sorting patterns in order
		for type in "${sorting_order[@]}"; do
			# Find lines where ftype matches the type pattern
			# Line format: "file_path ftype"
			# We want to match ftype exactly (at end of line after space)
			while IFS= read -r line; do
				if [ -n "$line" ]; then
					# Extract the file path (everything before the last space)
					file_path="${line% *}"
					# Extract ftype (everything after the last space)
					ftype_value="${line##* }"
					
					# Check if ftype matches the type pattern exactly
					if [ "$ftype_value" = "$type" ]; then
						# Check if this file hasn't been added yet (avoid duplicates)
						if ! grep -Fxq "$file_path" "${matched_files}" 2>/dev/null; then
							# Add to sorted list
							echo "$file_path" >> "${sorted_file_list}"
							# Mark as matched
							echo "$file_path" >> "${matched_files}"
						fi
					fi
				fi
			done < "${temp_file_list}.$$"
		done
		
		# Add any remaining files that didn't match known patterns (fallback)
		# This ensures no files are lost
		while IFS= read -r line; do
			if [ -n "$line" ]; then
				file_path="${line% *}"
				# Check if this file was already matched
				if ! grep -Fxq "$file_path" "${matched_files}" 2>/dev/null; then
					log "Warning: File doesn't match known sorting pattern, adding at end: $file_path"
					echo "$file_path" >> "${sorted_file_list}"
				fi
			fi
		done < "${temp_file_list}.$$"
		
		# Clean up temporary matched files list
		rm -f "${matched_files}"
	fi
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

# Intelligent module loading with fallback to venv/conda
# Usage: load_tool_with_fallback <tool_name> [module_name] [venv_path] [conda_env]
# Returns: Sets global variable ${TOOL_NAME}_CMD with the full path to the tool
load_tool_with_fallback() {
  local tool_name="$1"
  local module_name="${2:-$tool_name}"
  local venv_path="${3:-$HOME/venv}"
  local conda_env="${4:-qlc}"
  
  local tool_cmd_var="$(echo "$tool_name" | tr '[:lower:]' '[:upper:]')_CMD"  # Convert to uppercase for variable name
  local tool_cmd=""
  
  log "Setting up $tool_name with intelligent module loading..."
  
  # Step 1: Check if tool is already available in PATH
  if command_exists "$tool_name"; then
    tool_cmd="$tool_name"
    log "Using $tool_name found in system PATH: $(which $tool_name)"
  else
    # Step 2: Try to load system module (preferred on HPC systems)
    if command_exists module; then
      log "Attempting to load module: $module_name"
      if module load "$module_name" 2>/dev/null; then
        log "Successfully loaded module: $module_name"
        if command_exists "$tool_name"; then
          tool_cmd="$tool_name"
          log "Using $tool_name from module: $(which $tool_name)"
        else
          log "Module loaded but $tool_name not found in PATH"
        fi
      else
        log "Failed to load module: $module_name"
      fi
    else
      log "Module system not available"
    fi
    
    # Step 3: Fallback to venv if module failed or not available
    if [ -z "$tool_cmd" ] && [ -f "$venv_path/bin/$tool_name" ]; then
      tool_cmd="$venv_path/bin/$tool_name"
      log "Using $tool_name from venv: $tool_cmd"
    fi
    
    # Step 4: Fallback to conda if venv failed
    if [ -z "$tool_cmd" ] && command_exists conda; then
      log "Attempting conda fallback for $tool_name"
      # Try multiple possible conda base paths
      for base in "$HOME/miniforge3" "$HOME/anaconda3" "/opt/homebrew/anaconda3"; do
        if [ -f "$base/etc/profile.d/conda.sh" ]; then
          . "$base/etc/profile.d/conda.sh"
          if conda activate "$conda_env" 2>/dev/null; then
            log "Activated conda environment: $conda_env"
            if command_exists "$tool_name"; then
              tool_cmd="$(which $tool_name)"
              log "Using $tool_name from conda: $tool_cmd"
              break
            fi
          fi
        fi
      done
    fi
  fi
  
  # Set the global variable
  eval "$tool_cmd_var=\"$tool_cmd\""
  
  if [ -n "$tool_cmd" ]; then
    log "Successfully configured $tool_name: $tool_cmd"
    return 0
  else
    log "Error: Could not find or configure $tool_name"
    log "Please install $tool_name using one of these methods:"
    log "  1. System package manager (apt, yum, brew, etc.)"
    log "  2. Module system: module load $module_name"
    log "  3. Python venv: pip install $tool_name in $venv_path"
    log "  4. Conda: conda install $tool_name in $conda_env environment"
    return 1
  fi
}

# Convenience functions for common tools
setup_cdo() {
  load_tool_with_fallback "cdo" "cdo" "$HOME/venv" "qlc"
}

setup_ncdump() {
  load_tool_with_fallback "ncdump" "netcdf4" "$HOME/venv" "qlc"
}

setup_eccodes() {
  # Setup eccodes library for GRIB file reading (required for cfgrib)
  # Priority: 1) System PATH, 2) Module system (HPC/ATOS)
  log "Setting up eccodes for GRIB file reading..."
  
  # Check if eccodes is available via grib_ls command
  if command_exists "grib_ls"; then
    log "eccodes already available in PATH: $(command -v grib_ls)"
    export ECCODES_CMD="grib_ls"
    return 0
  fi
  
  # Try to load eccodes module (preferred on HPC/ATOS)
  if command_exists module; then
    log "Attempting to load eccodes module..."
    # Try common module names for eccodes
    for eccodes_module in "eccodes" "eccodes/2.31.0" "eccodes/2.30.0" "grib_api"; do
      if module load "$eccodes_module" 2>/dev/null; then
        log "Successfully loaded module: $eccodes_module"
        if command_exists "grib_ls"; then
          export ECCODES_CMD="grib_ls"
          log "eccodes available via module: $(command -v grib_ls)"
          return 0
        fi
      fi
    done
    log "Could not load eccodes via module system"
  fi
  
  # Warning: eccodes not found but not critical (cfgrib will still try to use system library)
  log "eccodes command-line tools not found, but cfgrib may still work with system library" "WARN"
  log "For GRIB file support, install eccodes:" "WARN"
  log "  macOS: brew install eccodes" "WARN"
  log "  Linux: apt install libeccodes-dev  (or yum install eccodes-devel)" "WARN"
  log "  HPC/ATOS: module load eccodes" "WARN"
  return 0  # Don't fail - cfgrib might still work
}

setup_pyferret() {
  load_tool_with_fallback "pyferret" "ferret/7.6.3" "$HOME/venv" "pyferret_env"
}

# Check for evaltools Python environment (venv or conda)
# Priority: 1) Same venv as QLC, 2) Dedicated evaltools venv, 3) Conda fallback
setup_evaltools() {
  local tool_name="evaltools"
  local tool_cmd_var="$(echo "$tool_name" | tr '[:lower:]' '[:upper:]')_PYTHON"  # EVALTOOLS_PYTHON
  local tool_cmd=""
  
  log "Setting up evaltools with intelligent detection..."
  
  # Step 1: Check if evaltools is in the same venv as QLC
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -f "${VIRTUAL_ENV}/bin/python" ]; then
    if "${VIRTUAL_ENV}/bin/python" -c "import evaltools" 2>/dev/null; then
      tool_cmd="${VIRTUAL_ENV}/bin/python"
      log "Using evaltools from QLC venv: ${tool_cmd}"
    fi
  fi
  
  # Step 2: Check dedicated evaltools venv
  if [ -z "$tool_cmd" ] && [ -f "${HOME}/venv/evaltools_109/bin/python" ]; then
    if "${HOME}/venv/evaltools_109/bin/python" -c "import evaltools" 2>/dev/null; then
      tool_cmd="${HOME}/venv/evaltools_109/bin/python"
      log "Using evaltools from dedicated venv: ${tool_cmd}"
    fi
  fi
  
  # Step 3: Check conda fallback
  if [ -z "$tool_cmd" ] && command_exists conda; then
    log "Attempting conda fallback for evaltools"
    for base in "$HOME/miniforge3" "$HOME/anaconda3" "/opt/homebrew/anaconda3"; do
      if [ -f "$base/etc/profile.d/conda.sh" ]; then
        . "$base/etc/profile.d/conda.sh"
        if conda activate evaltools 2>/dev/null; then
          if python -c "import evaltools" 2>/dev/null; then
            tool_cmd="$(which python)"
            log "Using evaltools from conda: ${tool_cmd}"
            break
          fi
        fi
      fi
    done
  fi
  
  # Set the global variable
  eval "$tool_cmd_var=\"$tool_cmd\""
  
  if [ -n "$tool_cmd" ]; then
    log "Successfully configured evaltools: $tool_cmd"
    return 0
  else
    log "Error: Could not find evaltools installation"
    log "Please install evaltools using one of these methods:"
    log "  1. Integrated installation: qlc-install-extras --evaltools"
    log "  2. Dedicated venv: bash qlc/bin/tools/qlc_install_evaltools.sh"
    log "  3. Conda: conda install evaltools"
    return 1
  fi
}

# Check for pyferret Python environment (venv or conda)
# Priority: 1) Same venv as QLC, 2) Conda fallback
setup_pyferret_integrated() {
  local tool_name="pyferret"
  local tool_cmd_var="$(echo "$tool_name" | tr '[:lower:]' '[:upper:]')_CMD"  # PYFERRET_CMD
  local tool_cmd=""
  
  log "Setting up pyferret with intelligent detection..."
  
  # Step 1: Check if pyferret is in the same venv as QLC
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -f "${VIRTUAL_ENV}/bin/pyferret" ]; then
    tool_cmd="${VIRTUAL_ENV}/bin/pyferret"
    log "Using pyferret from QLC venv: ${tool_cmd}"
  elif [ -n "${VIRTUAL_ENV:-}" ] && command_exists pyferret; then
    tool_cmd="pyferret"
    log "Using pyferret from QLC venv PATH: ${tool_cmd}"
  fi
  
  # Step 2: Try loading ferret module on HPC systems
  if [ -z "$tool_cmd" ] && command_exists module; then
    log "Checking for ferret module on HPC..."
    # Try to load ferret module and check if pyferret becomes available
    if bash -c 'module load ferret 2>/dev/null && command -v pyferret' >/dev/null 2>&1; then
      tool_cmd="pyferret"
      log "Using pyferret from ferret module"
      # Load the module in current shell
      module load ferret 2>/dev/null || true
    fi
  fi
  
  # Step 3: Check system PATH
  if [ -z "$tool_cmd" ] && command_exists pyferret; then
    tool_cmd="pyferret"
    log "Using pyferret from system PATH: $(which pyferret)"
  fi
  
  # Step 4: Check conda fallback
  if [ -z "$tool_cmd" ] && command_exists conda; then
    log "Attempting conda fallback for pyferret"
    for base in "$HOME/miniforge3" "$HOME/anaconda3" "/opt/homebrew/anaconda3"; do
      if [ -f "$base/etc/profile.d/conda.sh" ]; then
        . "$base/etc/profile.d/conda.sh"
        for env in "pyferret_env" "pyferret" "ferret"; do
          if conda activate "$env" 2>/dev/null; then
            if command_exists pyferret; then
              tool_cmd="$(which pyferret)"
              log "Using pyferret from conda: ${tool_cmd}"
              break 2
            fi
          fi
        done
      fi
    done
  fi
  
  # Set the global variable
  eval "$tool_cmd_var=\"$tool_cmd\""
  
  # Step 5: Check and setup ferret environment variables if needed
  if [ -n "$tool_cmd" ]; then
    log "Checking ferret environment variables..."
    
    # Check if ferret module is loaded (module system)
    if command_exists module; then
      module_check=$(bash -c 'module list 2>&1 | grep -i ferret' 2>/dev/null || echo "")
      if [ -n "$module_check" ]; then
        log "Ferret module detected: $module_check"
        log "Ferret environment variables should be available via module system"
      else
        log "No ferret module detected, checking for manual ferret installation..."
        setup_ferret_paths
      fi
    else
      log "No module system available, checking for manual ferret installation..."
      setup_ferret_paths
    fi
    
    log "Successfully configured pyferret: $tool_cmd"
    return 0
  else
    log "Error: Could not find pyferret installation"
    log "Please install pyferret using one of these methods:"
    log "  1. Integrated installation: qlc-install-extras --pyferret"
    log "  2. Conda: conda install -c conda-forge pyferret"
    log "  3. System module: module load ferret/7.6.3"
    return 1
  fi
}

# Setup ferret environment variables for pyferret execution
# This function checks for FER_DIR and FER_DSETS and sources ferret_paths.sh if needed
setup_ferret_paths() {
  log "Setting up ferret environment variables..."
  
  # Check if ferret environment variables are already set
  if [ -n "${FER_DIR:-}" ] && [ -n "${FER_DSETS:-}" ]; then
    log "Ferret environment variables already set:"
    log "  FER_DIR: ${FER_DIR}"
    log "  FER_DSETS: ${FER_DSETS}"
    return 0
  fi
  
  log "Ferret environment variables not set, searching for ferret installation..."
  
  # Common ferret installation paths
  ferret_search_paths=(
    "/opt/PyFerret"
    "/usr/local/PyFerret"
    "/opt/ferret"
    "/usr/local/ferret"
    "/opt/Ferret"
    "/usr/local/Ferret"
    "$HOME/PyFerret"
    "$HOME/ferret"
    "$HOME/Ferret"
    "/opt/homebrew/PyFerret"
    "/opt/homebrew/ferret"
  )
  
  ferret_dir=""
  for search_path in "${ferret_search_paths[@]}"; do
    if [ -d "$search_path" ] && [ -f "$search_path/bin/ferret_paths.sh" ]; then
      ferret_dir="$search_path"
      log "Found ferret installation at: $ferret_dir"
      break
    fi
  done
  
  if [ -n "$ferret_dir" ]; then
    log "Sourcing ferret paths from: ${ferret_dir}/bin/ferret_paths.sh"
    if [ -f "${ferret_dir}/bin/ferret_paths.sh" ]; then
      # Source the ferret paths script
      source "${ferret_dir}/bin/ferret_paths.sh"
      
      # Verify the environment variables are now set
      if [ -n "${FER_DIR:-}" ] && [ -n "${FER_DSETS:-}" ]; then
        log "Successfully set ferret environment variables:"
        log "  FER_DIR: ${FER_DIR}"
        log "  FER_DSETS: ${FER_DSETS}"
        return 0
      else
        log "Warning: ferret_paths.sh sourced but environment variables not set"
        return 1
      fi
    else
      log "Error: ferret_paths.sh not found at ${ferret_dir}/bin/ferret_paths.sh"
      return 1
    fi
  else
    log "Warning: No ferret installation found in common paths"
    log "PyFerret may not work correctly without proper ferret environment variables"
    log "Please ensure FER_DIR and FER_DSETS are set manually or install ferret"
    return 1
  fi
}

setup_python() {
  local tool_cmd_var="PYTHON_CMD"
  local tool_cmd=""
  
  log "Setting up Python with intelligent detection..."
  
  # Step 1: Use current venv Python if available (preferred)
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -f "${VIRTUAL_ENV}/bin/python" ]; then
    tool_cmd="${VIRTUAL_ENV}/bin/python"
    log "Using Python from current venv: ${tool_cmd}"
  else
    # Step 2: Try to load system module (preferred on HPC systems)
    if command_exists module; then
      log "Attempting to load module: python3/3.10.10-01"
      if module load "python3/3.10.10-01" 2>/dev/null; then
        log "Successfully loaded module: python3/3.10.10-01"
        tool_cmd="python3"
      fi
    fi
    
    # Step 3: Check for Python in QLC venv
    if [ -z "$tool_cmd" ] && [ -f "$HOME/venv/qlc-dev/bin/python" ]; then
      tool_cmd="$HOME/venv/qlc-dev/bin/python"
      log "Using Python from QLC dev venv: ${tool_cmd}"
    fi
    
    # Step 4: Check for Python in versioned QLC venvs
    if [ -z "$tool_cmd" ]; then
      for venv_dir in "$HOME/venv"/qlc-*; do
        if [ -f "$venv_dir/bin/python" ]; then
          tool_cmd="$venv_dir/bin/python"
          log "Using Python from QLC versioned venv: ${tool_cmd}"
          break
        fi
      done
    fi
    
    # Step 5: Fallback to system Python
    if [ -z "$tool_cmd" ] && command_exists python3; then
      tool_cmd="python3"
      log "Using system Python3: $(which python3)"
    elif [ -z "$tool_cmd" ] && command_exists python; then
      tool_cmd="python"
      log "Using system Python: $(which python)"
    fi
  fi
  
  if [ -n "$tool_cmd" ]; then
    eval "$tool_cmd_var=\"$tool_cmd\""
    log "Success: Python configured as $tool_cmd"
    return 0
  else
    log "Error: Could not find Python interpreter"
    return 1
  fi
}

# Setup PDF conversion tool (XeLaTeX - cross-platform LaTeX)
setup_pdf_converter() {
  local tool_cmd=""
  
  log "Setting up PDF converter with intelligent detection..."
  
  # Step 1: Check if xelatex or pdflatex is in current venv (if active)
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    local venv_name=$(basename "$VIRTUAL_ENV")
    log "Checking for LaTeX in current venv: ${venv_name}"
    
    if [ -f "${VIRTUAL_ENV}/bin/xelatex" ]; then
      tool_cmd="${VIRTUAL_ENV}/bin/xelatex"
      log "Using xelatex from venv: ${venv_name}"
    elif [ -f "${VIRTUAL_ENV}/bin/pdflatex" ]; then
      tool_cmd="${VIRTUAL_ENV}/bin/pdflatex"
      log "Using pdflatex from venv: ${venv_name}"
    else
      log "LaTeX not found in venv: ${venv_name}"
    fi
  fi
  
  # Step 2: Try loading TexLive module on HPC systems (like Pyferret)
  if [ -z "$tool_cmd" ] && command_exists module; then
    log "Checking for TexLive module on HPC..."
    # Try common TexLive module names
    for texlive_module in "texlive/2025" "texlive/2024" "texlive" "TeXLive"; do
      if bash -c "module load $texlive_module 2>/dev/null && command -v pdflatex" >/dev/null 2>&1; then
        tool_cmd="pdflatex"
        log "Using pdflatex from TexLive module: $texlive_module"
        # Load the module in current shell
        module load "$texlive_module" 2>/dev/null || true
        break
      elif bash -c "module load $texlive_module 2>/dev/null && command -v xelatex" >/dev/null 2>&1; then
        tool_cmd="xelatex"
        log "Using xelatex from TexLive module: $texlive_module"
        # Load the module in current shell
        module load "$texlive_module" 2>/dev/null || true
        break
      fi
    done
  fi
  
  # Step 3: Check system PATH for xelatex
  if [ -z "$tool_cmd" ] && command_exists xelatex; then
    tool_cmd="xelatex"
    log "Using xelatex from system PATH: $(which xelatex)"
  fi
  
  # Step 4: Check system PATH for pdflatex
  if [ -z "$tool_cmd" ] && command_exists pdflatex; then
    tool_cmd="pdflatex"
    log "Using pdflatex from system PATH: $(which pdflatex)"
  fi
  
  # Set the global variable
  if [ -n "$tool_cmd" ]; then
    PDF_CONVERTER="$tool_cmd"
    log "Successfully configured PDF converter: $PDF_CONVERTER"
    return 0
  else
    log "Error: Could not find or configure PDF converter"
    log "Please install LaTeX using one of these methods:"
    log "  1. System module: module load texlive/2025"
    log "  2. System LaTeX distribution (TeX Live, MacTeX, etc.)"
    return 1
  fi
}

# Convert LaTeX-like document to PDF using weasyprint
# Usage: convert_tex_to_pdf <input_file> <output_file>
convert_tex_to_pdf() {
  local input_file="$1"
  local output_file="$2"
  
  if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    log "Error: convert_tex_to_pdf requires input and output file paths"
    return 1
  fi
  
  if [ ! -f "$input_file" ]; then
    log "Error: Input file does not exist: $input_file"
    return 1
  fi
  
  # Use XeLaTeX if available (preferred cross-platform LaTeX)
  if command -v xelatex >/dev/null 2>&1; then
    log "Converting $input_file to $output_file using XeLaTeX"
    local tex_dir=$(dirname "$input_file")
    local tex_basename=$(basename "$input_file" .tex)
    
    # Run XeLaTeX in the directory containing the .tex file
    (cd "$tex_dir" && xelatex -interaction=nonstopmode "$tex_basename.tex")
    
    # Check if PDF was created
    local expected_pdf="$tex_dir/$tex_basename.pdf"
    if [ -f "$expected_pdf" ]; then
      # Move to desired output location if different
      if [ "$expected_pdf" != "$output_file" ]; then
        mv "$expected_pdf" "$output_file"
      fi
      log "Successfully created PDF: $output_file"
      return 0
    else
      log "Error: XeLaTeX failed to create PDF"
      return 1
    fi
  fi
  
  # Fallback to pdflatex
  if command -v pdflatex >/dev/null 2>&1; then
    log "Converting $input_file to $output_file using pdflatex"
    local tex_dir=$(dirname "$input_file")
    local tex_basename=$(basename "$input_file" .tex)
    
    (cd "$tex_dir" && pdflatex -interaction=nonstopmode "$tex_basename.tex")
    
    local expected_pdf="$tex_dir/$tex_basename.pdf"
    if [ -f "$expected_pdf" ]; then
      if [ "$expected_pdf" != "$output_file" ]; then
        mv "$expected_pdf" "$output_file"
      fi
      log "Successfully created PDF: $output_file"
      return 0
    else
      log "Error: pdflatex failed to create PDF"
      return 1
    fi
  fi
  
  # Fallback to weasyprint (limited LaTeX support)
  log "Converting $input_file to $output_file using weasyprint (limited LaTeX support)"
  if command -v weasyprint >/dev/null 2>&1; then
    weasyprint "$input_file" "$output_file"
    if [ -f "$output_file" ]; then
      log "Successfully created PDF: $output_file"
      return 0
    else
      log "Error: weasyprint failed to create PDF"
      return 1
    fi
  else
    log "Error: No LaTeX or PDF converter found"
    log "Please install LaTeX or weasyprint"
    return 1
  fi
}

# ============================================================================
# QLC ENVIRONMENT DETECTION AND ACTIVATION
# ============================================================================

# Detect and activate QLC virtual environment
# Priority: 1) Current VIRTUAL_ENV, 2) QLC_HOME override, 3) Auto-detection
# Supports: ~/venv/qlc-dev, ~/venv/qlc, ~/venv/qlc-0.4.3, etc.
setup_qlc_environment() {
  local mode="${1:-auto}"  # auto, dev, prod, or specific version
  local force_activation="${2:-false}"
  
  log "Setting up QLC environment (mode: ${mode})..."
  
  # Step 1: Check if already in a QLC virtual environment
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    local venv_name=$(basename "$VIRTUAL_ENV")
    if [[ "$venv_name" =~ ^qlc ]]; then
      log "Already in QLC virtual environment: ${VIRTUAL_ENV}"
      log "Environment: ${venv_name}"
      return 0
    fi
  fi
  
  # Step 2: Check for explicit QLC_HOME override
  if [ -n "${QLC_HOME:-}" ]; then
    log "Using explicit QLC_HOME: ${QLC_HOME}"
    # Extract venv path from QLC_HOME if it's a venv-based runtime
    if [[ "$QLC_HOME" =~ /venv/qlc ]]; then
      local venv_path=$(echo "$QLC_HOME" | sed 's|/current/.*||')
      if [ -f "${venv_path}/bin/activate" ]; then
        log "Activating QLC venv from QLC_HOME: ${venv_path}"
        source "${venv_path}/bin/activate"
        return 0
      fi
    fi
  fi
  
  # Step 3: Auto-detect QLC virtual environment
  local venv_candidates=()
  
  # Add candidates based on mode
  case "$mode" in
    "dev")
      venv_candidates+=("${HOME}/venv/qlc-dev")
      ;;
    "prod")
      venv_candidates+=("${HOME}/venv/qlc")
      ;;
    "auto")
      # Auto-detection priority: dev -> current version -> prod
      venv_candidates+=("${HOME}/venv/qlc-dev")
      # Add versioned venvs (most recent first)
      for venv_dir in "${HOME}/venv"/qlc-*; do
        if [ -d "$venv_dir" ]; then
          venv_candidates+=("$venv_dir")
        fi
      done | sort -V -r
      venv_candidates+=("${HOME}/venv/qlc")
      ;;
    *)
      # Specific version requested
      venv_candidates+=("${HOME}/venv/qlc-${mode}")
      venv_candidates+=("${HOME}/venv/qlc-dev")
      venv_candidates+=("${HOME}/venv/qlc")
      ;;
  esac
  
  # Step 4: Try to activate the first available venv
  for venv_path in "${venv_candidates[@]}"; do
    if [ -f "${venv_path}/bin/activate" ]; then
      log "Found QLC virtual environment: ${venv_path}"
      
      # Check if qlc package is installed in this venv
      if [ -f "${venv_path}/bin/python" ]; then
        if "${venv_path}/bin/python" -c "import qlc" 2>/dev/null; then
          log "Activating QLC virtual environment: ${venv_path}"
          source "${venv_path}/bin/activate"
          
          # Verify activation
          if [ -n "${VIRTUAL_ENV:-}" ]; then
            log "Successfully activated: ${VIRTUAL_ENV}"
            return 0
          else
            log "Warning: Activation failed for ${venv_path}"
          fi
        else
          log "Skipping ${venv_path} - qlc package not found"
        fi
      fi
    fi
  done
  
  # Step 5: Fallback - try to activate any available venv
  if [ "$force_activation" = "true" ]; then
    log "Force activation requested - trying any available QLC venv..."
    for venv_path in "${venv_candidates[@]}"; do
      if [ -f "${venv_path}/bin/activate" ]; then
        log "Force activating: ${venv_path}"
        source "${venv_path}/bin/activate"
        return 0
      fi
    done
  fi
  
  log "Warning: No QLC virtual environment found"
  log "Available candidates checked:"
  for venv_path in "${venv_candidates[@]}"; do
    if [ -d "$venv_path" ]; then
      log "  - ${venv_path} (exists)"
    else
      log "  - ${venv_path} (not found)"
    fi
  done
  
  return 1
}

# Load required modules for HPC environments (ATOS, etc.)
load_hpc_modules() {
  local modules=("cdo/2.5.3" "netcdf4/4.9.3" "hdf5/1.14.6" "geos/3.13.1" "proj/9.5.1" "gdal/3.10.2" "texlive/2025")
  
  # Check if we're on an HPC system
  if command_exists module; then
    log "Detected HPC environment - loading required modules..."
    
    for module in "${modules[@]}"; do
      log "Loading module: ${module}"
      if module load "${module}" 2>/dev/null; then
        log "Successfully loaded: ${module}"
      else
        log "Warning: Failed to load module: ${module}"
      fi
    done
    
    log "HPC modules loaded successfully"
    return 0
  else
    log "No module system detected - skipping HPC module loading"
    return 0
  fi
}

# Complete QLC environment setup
# Usage: setup_qlc_complete [mode] [load_modules]
setup_qlc_complete() {
  local mode="${1:-auto}"
  local load_modules="${2:-true}"
  
  log "Setting up complete QLC environment..."
  
  # Step 1: Setup QLC virtual environment
  if setup_qlc_environment "$mode"; then
    log "QLC virtual environment activated"
  else
    log "Warning: QLC virtual environment not activated"
  fi
  
  # Step 2: Load HPC modules if requested
  if [ "$load_modules" = "true" ]; then
#   load_hpc_modules
    log "HPC modules will be loaded on demand"
  fi
  
  # Step 3: Verify environment
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    local venv_name=$(basename "$VIRTUAL_ENV")
    log "Final environment: ${venv_name}"
    log "Python: $(which python)"
    log "QLC version: $("$(which python)" -c "import qlc; from qlc.py.version import QLC_VERSION; print(QLC_VERSION)" 2>/dev/null || echo "unknown")"
    return 0
  else
    log "Warning: No virtual environment active"
    return 1
  fi
}

# ==============================================================================
# VARIABLE REGISTRY FUNCTIONS
# ==============================================================================
# Functions for loading and managing the variable registry system
# Supports individual variables, groups, and legacy namelist mapping
# ==============================================================================

# Global variable to track if registry is loaded
VARIABLE_REGISTRY_LOADED=false

# Load the variable registry configuration
# Usage: load_variable_registry
# NOTE: This function is deprecated as of v0.4.3
# Variable registry is now handled by Python parser (qlc/py/parse_variables.py)
# Bash scripts receive variables from Python-generated exports
load_variable_registry() {
  # DEPRECATED: Variable registry now parsed by Python
  # This function is kept for backward compatibility but does nothing
  # Variables are now provided by the Python wrapper via exported arrays
  # NOTE: Don't log here - this function is called in command substitutions
  # and any output would be captured as data
  VARIABLE_REGISTRY_LOADED=true
  return 0

}

# Get variable metadata from registry
# Usage: get_variable_metadata <var_name> <field>
# Fields: param, ncvar, myvar, levtype, description
# NOTE: As of v0.4.3, this calls Python parser instead of bash associative arrays
get_variable_metadata() {
  local var_name="$1"
  local field="$2"
  
  # Ensure registry is loaded (now a no-op, just for compatibility)
  load_variable_registry || return 1
  
  # Call Python parser to get variable metadata
  # This replaces the old associative array approach
  python -c "
from qlc.py.parse_variables import VariableRegistry
import sys
import os

# Find qlc.conf
qlc_home = os.environ.get('QLC_HOME', os.path.expanduser('~/qlc'))
config_file = os.path.join(qlc_home, 'config', 'qlc.conf')

try:
    registry = VariableRegistry(config_file)
    vars_list = registry.get_variables('$var_name')
    
    if vars_list:
        var = vars_list[0]
        if '$field' == 'param':
            print(var.param)  # Correct attribute name
        elif '$field' == 'ncvar':
            print(var.var_id)  # NetCDF var is same as var_id
        elif '$field' == 'myvar':
            print(var.myvar)  # Use myvar attribute
        elif '$field' == 'levtype':
            print(var.levtype)
        elif '$field' == 'description':
            print(var.description)
    else:
        sys.exit(1)
except Exception as e:
    sys.stderr.write(f'Error getting metadata for $var_name: {e}\n')
    sys.exit(1)
"
}

# Expand variable specification to list of individual variables
# Handles: individual vars, groups (@GROUP), legacy names, comma-separated lists
# Usage: expand_variable_spec <spec>
# Example: expand_variable_spec "@EAC5_SFC,sfc_PM10,sfc_O3"
# NOTE: As of v0.4.3, this calls Python parser instead of bash associative arrays
expand_variable_spec() {
  local spec="$1"
  
  # Ensure registry is loaded (now a no-op, just for compatibility)
  load_variable_registry || return 1
  
  # Call Python parser to expand variable specification
  # This replaces the old bash associative array approach
  # Pass workflow config if WORKFLOW_CONFIG is set (for workflow-specific groups/variables)
  python -c "
from qlc.py.parse_variables import VariableRegistry
import sys
import os

# Find qlc.conf
qlc_home = os.environ.get('QLC_HOME', os.path.expanduser('~/qlc'))
config_file = os.path.join(qlc_home, 'config', 'qlc.conf')

# Check for workflow config (workflow-specific overrides)
workflow_config = os.environ.get('WORKFLOW_CONFIG')

try:
    # Initialize registry with workflow config support
    registry = VariableRegistry(config_file, workflow_config_file=workflow_config)
    vars_list = registry.get_variables('$spec')
    
    if vars_list:
        # Print one variable ID per line
        for var in vars_list:
            print(var.var_id)
    else:
        sys.stderr.write('WARNING: No variables found for spec: $spec\n')
        sys.exit(1)
except Exception as e:
    sys.stderr.write(f'Error expanding variable spec: {e}\n')
    sys.exit(1)
"
}

# Parse command-line arguments for variable and MARS overrides
# Sets global variables: vars_override, nml_override, mars_overrides (associative array)
#                        expert_params, expert_ncvars, expert_myvars, expert_levtypes (arrays)
# Usage: parse_variable_and_mars_options "$@"
parse_variable_and_mars_options() {
  # DEPRECATED as of v0.4.3 - Variable parsing now handled by Python
  # This stub keeps basic functionality for backward compatibility
  
  # Initialize global variables (Bash 3.2 compatible)
  vars_override=""
  nml_override=""
  # Note: mars_overrides no longer uses associative array (Bash 4+)
  # MARS overrides now handled by Python parser
  
  # Expert mode: direct parameter specification (kept for compatibility)
  local param_spec=""
  local ncvar_spec=""
  local myvar_spec=""
  local levtype_spec=""
  
  for arg in "$@"; do
    # Parse -vars= option
    if [[ "$arg" == -vars=* ]]; then
      vars_override="${arg#-vars=}"
      log "Variables override: $vars_override"
      
    # Parse -nml= option (legacy support)
    elif [[ "$arg" == -nml=* ]]; then
      nml_override="${arg#-nml=}"
      log "Namelist override: $nml_override"
      
    # Expert mode: direct parameter specification
    elif [[ "$arg" == -param=* ]]; then
      param_spec="${arg#-param=}"
      log "Expert mode - PARAM specification: $param_spec"
      
    elif [[ "$arg" == -ncvar=* ]]; then
      ncvar_spec="${arg#-ncvar=}"
      log "Expert mode - NCVAR specification: $ncvar_spec"
      
    elif [[ "$arg" == -myvar=* ]]; then
      myvar_spec="${arg#-myvar=}"
      log "Expert mode - MYVAR specification: $myvar_spec"
      
    elif [[ "$arg" == -levtype=* ]]; then
      levtype_spec="${arg#-levtype=}"
      log "Expert mode - LEVTYPE specification: $levtype_spec"
      
    # Parse MARS parameter overrides
    # NOTE: MARS overrides now handled by Python parser as of v0.4.3
    # These command-line options are captured and passed to Python
    elif [[ "$arg" == -grid=* ]]; then
      # mars_overrides[grid]="${arg#-grid=}"  # Disabled: associative array (Bash 4+)
      log "MARS grid override: ${arg#-grid=} (will be handled by Python parser)"
      
    elif [[ "$arg" == -step=* ]]; then
      # mars_overrides[step]="${arg#-step=}"  # Disabled: associative array (Bash 4+)
      log "MARS step override: ${arg#-step=} (will be handled by Python parser)"
      
    elif [[ "$arg" == -time=* ]]; then
      # mars_overrides[time]="${arg#-time=}"  # Disabled: associative array (Bash 4+)
      log "MARS time override: ${arg#-time=} (will be handled by Python parser)"
      
    elif [[ "$arg" == -type=* ]]; then
      # mars_overrides[type]="${arg#-type=}"  # Disabled: associative array (Bash 4+)
      log "MARS type override: ${arg#-type=} (will be handled by Python parser)"
      
    elif [[ "$arg" == -stream=* ]]; then
      # mars_overrides[stream]="${arg#-stream=}"  # Disabled: associative array (Bash 4+)
      log "MARS stream override: ${arg#-stream=} (will be handled by Python parser)"
      
    elif [[ "$arg" == -levelist=* ]]; then
      # mars_overrides[levelist]="${arg#-levelist=}"  # Disabled: associative array (Bash 4+)
      log "MARS levelist override: ${arg#-levelist=} (will be handled by Python parser)"
    fi
  done
  
  # Process expert mode parameter specifications
  if [ -n "$param_spec" ] && [ -n "$myvar_spec" ] && [ -n "$levtype_spec" ]; then
    log "Expert mode activated: processing direct parameter specifications"
    
    # Parse comma-separated values into arrays
    IFS=',' read -ra expert_params <<< "$param_spec"
    IFS=',' read -ra expert_myvars <<< "$myvar_spec"
    IFS=',' read -ra expert_levtypes <<< "$levtype_spec"
    
    # Parse ncvar if provided, otherwise default to "unknown"
    if [ -n "$ncvar_spec" ]; then
      IFS=',' read -ra expert_ncvars <<< "$ncvar_spec"
    else
      # Default all ncvars to "unknown" for auto-detection
      expert_ncvars=()
      for ((i=0; i<${#expert_params[@]}; i++)); do
        expert_ncvars+=("unknown")
      done
      log "Expert mode: ncvar not specified, defaulting to 'unknown' for auto-detection"
    fi
    
    # Validate array lengths
    local num_params=${#expert_params[@]}
    local num_myvars=${#expert_myvars[@]}
    local num_ncvars=${#expert_ncvars[@]}
    local num_levtypes=${#expert_levtypes[@]}
    
    if [ $num_params -ne $num_myvars ]; then
      log "ERROR: Number of params ($num_params) does not match number of myvars ($num_myvars)"
      return 1
    fi
    
    if [ -n "$ncvar_spec" ] && [ $num_params -ne $num_ncvars ]; then
      log "ERROR: Number of params ($num_params) does not match number of ncvars ($num_ncvars)"
      return 1
    fi
    
    # Handle levtype: either single value for all, or one per variable
    if [ $num_levtypes -eq 1 ]; then
      # Single levtype - apply to all variables
      local single_levtype="${expert_levtypes[0]}"
      expert_levtypes=()
      for ((i=0; i<num_params; i++)); do
        expert_levtypes+=("$single_levtype")
      done
      log "Expert mode: single levtype '$single_levtype' applied to all $num_params variables"
    elif [ $num_params -ne $num_levtypes ]; then
      log "ERROR: Number of levtypes ($num_levtypes) must be 1 or match number of params ($num_params)"
      return 1
    fi
    
    # Export arrays for use in other functions
    export expert_params expert_ncvars expert_myvars expert_levtypes
    
    log "Expert mode validated: $num_params custom variable(s) defined"
    for ((i=0; i<num_params; i++)); do
      log "  Variable $((i+1)): param=${expert_params[$i]}, ncvar=${expert_ncvars[$i]}, myvar=${expert_myvars[$i]}, levtype=${expert_levtypes[$i]}"
    done
  elif [ -n "$param_spec" ] || [ -n "$myvar_spec" ] || [ -n "$levtype_spec" ]; then
    log "ERROR: Expert mode requires all three: -param, -myvar, and -levtype"
    log "  Provided: param=${param_spec:+yes}, myvar=${myvar_spec:+yes}, levtype=${levtype_spec:+yes}"
    return 1
  fi
  
  return 0
}

# Get final MARS parameter value (with override support)
# Usage: get_mars_param <param_name> <default_value>
# NOTE: DEPRECATED as of v0.4.3 - MARS parameters now handled by Python parser
get_mars_param() {
  local param_name="$1"
  local default_value="$2"
  
  # DEPRECATED: MARS overrides now handled by Python parser
  # Just return the default value for backward compatibility
  # Python-generated MARS requests already have overrides applied
  echo "$default_value"
  
  # OLD CODE (disabled - used associative arrays):
  # # Check if override exists
  # if [ -n "${mars_overrides[$param_name]}" ]; then
  #   echo "${mars_overrides[$param_name]}"
  # else
  #   echo "$default_value"
  # fi
}

# Get MARS default value based on level type
# Usage: get_mars_default <levtype> <param_name>
get_mars_default() {
  local levtype="$1"
  local param_name="$2"
  
  # Default values based on level type
  case "$levtype" in
    sfc)
      case "$param_name" in
        type) echo "fc" ;;
        stream) echo "oper" ;;
        grid) echo "1.0/1.0" ;;
        time) echo "00:00:00" ;;
        step) echo "0/to/21/by/3" ;;
        *) echo "" ;;
      esac
      ;;
    pl)
      case "$param_name" in
        type) echo "fc" ;;
        stream) echo "oper" ;;
        grid) echo "1.0/1.0" ;;
        time) echo "00:00:00" ;;
        step) echo "12/24" ;;
        levelist) echo "${PL_LEVELIST:-1000/to/10}" ;;
        *) echo "" ;;
      esac
      ;;
    ml)
      case "$param_name" in
        type) echo "fc" ;;
        stream) echo "oper" ;;
        grid) echo "1.0/1.0" ;;
        time) echo "00:00:00" ;;
        step) echo "12/24" ;;
        levelist) echo "${ML_LEVELIST:-137/to/1}" ;;
        *) echo "" ;;
      esac
      ;;
    *)
      echo ""
      ;;
  esac
}

# Generate MARS namelist from template for a specific variable
# Usage: generate_mars_namelist <var_name> <exp> <xclass> <sdate> <edate> <output_path> <output_prefix>
generate_mars_namelist() {
  local var_name="$1"
  local exp="$2"
  local xclass="$3"
  local sdate="$4"
  local edate="$5"
  local output_path="$6"
  local output_prefix="$7"
  
  # Ensure registry is loaded
  load_variable_registry || return 1
  
  # Get variable metadata
  local param=$(get_variable_metadata "$var_name" "param")
  local levtype=$(get_variable_metadata "$var_name" "levtype")
  
  if [ -z "$param" ] || [ -z "$levtype" ]; then
    log "ERROR: Variable $var_name not found in registry"
    return 1
  fi
  
  # Determine template path
  local template_dir="${NAMELIST_DIR}/templates"
  local template_file="${template_dir}/mars_${levtype}.template"
  
  if [ ! -f "$template_file" ]; then
    log "ERROR: Template not found: $template_file"
    return 1
  fi
  
  # Get MARS parameters with override support
  local mars_type=$(get_mars_param "type" "$(get_mars_default "$levtype" "type")")
  local mars_stream=$(get_mars_param "stream" "$(get_mars_default "$levtype" "stream")")
  local mars_grid=$(get_mars_param "grid" "$(get_mars_default "$levtype" "grid")")
  local mars_time=$(get_mars_param "time" "$(get_mars_default "$levtype" "time")")
  local mars_step=$(get_mars_param "step" "$(get_mars_default "$levtype" "step")")
  local mars_levelist=$(get_mars_param "levelist" "$(get_mars_default "$levtype" "levelist")")
  
  # Generate output namelist
  local output_file="${output_path}/mars_${var_name}.nml"
  
  # Process template with substitutions
  sed -e "s/XCLASS/$xclass/g" \
      -e "s/MARS_TYPE/$mars_type/g" \
      -e "s/MARS_STREAM/$mars_stream/g" \
      -e "s/MARS_GRID/$mars_grid/g" \
      -e "s/MARS_TIME/$mars_time/g" \
      -e "s/MARS_STEP/$mars_step/g" \
      -e "s/MARS_LEVELIST/$mars_levelist/g" \
      -e "s/EXP/$exp/g" \
      -e "s/PARAM/$param/g" \
      -e "s/SDATE/$sdate/g" \
      -e "s/EDATE/$edate/g" \
      -e "s|MYPATH|${output_path}|g" \
      -e "s/MYFILE/${output_prefix}_${sdate//[-:]/}-${edate//[-:]/}/g" \
      -e "s/VARNAME/${var_name}/g" \
      "$template_file" > "$output_file"
  
  echo "$output_file"
}

# Build backward-compatible param/ncvar/myvar arrays for a variable
# This allows existing scripts to work with the new registry
# Usage: build_legacy_arrays <var_name>
# Sets: param_<var_name>, ncvar_<var_name>, myvar_<var_name>
build_legacy_arrays() {
  local var_name="$1"
  
  # Ensure registry is loaded
  load_variable_registry || return 1
  
  local param=$(get_variable_metadata "$var_name" "param")
  local ncvar=$(get_variable_metadata "$var_name" "ncvar")
  local myvar=$(get_variable_metadata "$var_name" "myvar")
  
  if [ -n "$param" ]; then
    eval "param_${var_name}=(\"$param\")"
    eval "ncvar_${var_name}=(\"$ncvar\")"
    eval "myvar_${var_name}=(\"$myvar\")"
    log "Built legacy arrays for: $var_name (param=$param, ncvar=$ncvar, myvar=$myvar)"
    return 0
  else
    log "WARNING: Could not build legacy arrays for: $var_name"
    return 1
  fi
}

# Create temporary expert mode variables from command-line specifications
# Returns list of variable names in format: myvar_levtype (e.g., PM1_sfc, NEW_VAR_pl)
# Usage: create_expert_mode_variables
create_expert_mode_variables() {
  local expert_var_names=()
  
  # Check if expert mode variables are defined
  if [ ${#expert_params[@]} -eq 0 ]; then
    return 0
  fi
  
  log "Creating expert mode temporary variables..."
  
  # Create temporary variable definitions for each expert parameter
  for ((i=0; i<${#expert_params[@]}; i++)); do
    local param="${expert_params[$i]}"
    local ncvar="${expert_ncvars[$i]}"
    local myvar="${expert_myvars[$i]}"
    local levtype="${expert_levtypes[$i]}"
    
    # Create unique variable name: myvar_levtype
    local var_name="${myvar}_${levtype}"
    
    # Create temporary associative array for this variable
    declare -gA "VAR_${var_name}"
    eval "VAR_${var_name}[param]=\"$param\""
    eval "VAR_${var_name}[ncvar]=\"$ncvar\""
    eval "VAR_${var_name}[myvar]=\"$myvar\""
    eval "VAR_${var_name}[levtype]=\"$levtype\""
    eval "VAR_${var_name}[description]=\"Expert mode custom variable\""
    
    expert_var_names+=("$var_name")
    log "Created expert variable: $var_name (param=$param, ncvar=$ncvar, myvar=$myvar, levtype=$levtype)"
  done
  
  # Return the list of created variable names
  printf '%s\n' "${expert_var_names[@]}"
}

# Function to get list of required MARS variables based on current configuration
# This consolidates the logic for determining which variables need to be retrieved
# Returns: Array of variable names (one per line)
# Usage: 
#   check_retrievals=()
#   while IFS= read -r var; do
#     check_retrievals+=("$var")
#   done < <(get_required_mars_variables)
get_required_mars_variables() {
  local vars=()
  
  # Priority 1: Expert mode parameters
  if [ ${#expert_params[@]} -gt 0 ]; then
    # Expert mode variables
    while IFS= read -r expert_var; do
      vars+=("$expert_var")
    done < <(create_expert_mode_variables)
    
    # Add registry variables if in additive mode
    if [ -n "$vars_option" ]; then
      vars_spec="${vars_option#-vars=}"
      while IFS= read -r var; do
        vars+=("$var")
      done < <(expand_variable_spec "$vars_spec")
    elif [ -n "$nml_option" ]; then
      nml_spec="${nml_option#-nml=}"
      while IFS= read -r var; do
        vars+=("$var")
      done < <(expand_variable_spec "$nml_spec")
    fi
  # Priority 2: Variable registry (via -vars= or -nml= options)
  elif [ -n "$vars_option" ]; then
    vars_spec="${vars_option#-vars=}"
    while IFS= read -r var; do
      vars+=("$var")
    done < <(expand_variable_spec "$vars_spec")
  elif [ -n "$nml_option" ]; then
    nml_spec="${nml_option#-nml=}"
    while IFS= read -r var; do
      vars+=("$var")
    done < <(expand_variable_spec "$nml_spec")
  # Priority 3: Default MARS_RETRIEVALS from workflow config
  elif [ ${#MARS_RETRIEVALS[@]} -gt 0 ]; then
    for retrieval_spec in "${MARS_RETRIEVALS[@]}"; do
      while IFS= read -r var; do
        vars+=("$var")
      done < <(expand_variable_spec "$retrieval_spec")
    done
  fi
  
  # Remove duplicates and return
  printf '%s\n' "${vars[@]}" | sort -u
}

# Function to build list of expected variables from MARS_RETRIEVALS configuration
# This allows filtering to only process files that were actually requested
# Sets global array: expected_vars
# Usage: get_expected_variables_from_mars_retrievals
# Returns: 0 if variables found or MARS_RETRIEVALS not set, 1 on error
get_expected_variables_from_mars_retrievals() {
  expected_vars=()
  
  if [ -n "${MARS_RETRIEVALS:-}" ] && [ ${#MARS_RETRIEVALS[@]} -gt 0 ]; then
    log "MARS_RETRIEVALS defined - will filter files based on requested variables"
    
    # Extract variable IDs from MARS_RETRIEVALS specification
    # MARS_RETRIEVALS contains var specs like "sfc_PM25", "pl_O3", "@GROUP_NAME", etc.
    for var_spec in "${MARS_RETRIEVALS[@]}"; do
      # Use Python parser to expand variable specs (handles groups, individual vars)
      while IFS= read -r var_id; do
        [ -n "$var_id" ] && expected_vars+=("$var_id")
      done < <(expand_variable_spec "$var_spec" 2>/dev/null || echo "")
    done
    
    if [ ${#expected_vars[@]} -gt 0 ]; then
      log "Expected variables from MARS_RETRIEVALS (${#expected_vars[@]}): ${expected_vars[*]}"
      return 0
    else
      log "WARNING: MARS_RETRIEVALS set but no variables could be expanded"
      log "Will process all files found"
      return 0
    fi
  else
    log "MARS_RETRIEVALS not set - will consider all files as valid"
    return 0
  fi
}

# Function to convert underscores in variable name to dashes for parsing purposes
# This allows proper splitting on underscores when variable names contain underscores
# Example: "NH4_as" -> "NH4-as"
# Usage: var_name_for_parsing "variable_name"
# Returns: variable name with underscores replaced by dashes
var_name_for_parsing() {
  local var_name="$1"
  
  if [ -z "$var_name" ]; then
    echo ""
    return
  fi
  
  # Replace underscores in variable name with dashes (for parsing only)
  echo "${var_name//_/-}"
}

# Function to format variable names with LaTeX math subscripts
# Converts: NH4_as -> NH$_4$\_as, NH_3 -> NH$_3$, SO2 -> SO$_2$
# Uses simple string replacements similar to Python approach
# Usage: format_var_name_tex "NH4_as"
format_var_name_tex() {
  local var_name="$1"
  if [ -z "$var_name" ]; then
    echo ""
    return
  fi
  
  # Step 1: Handle underscore before number (NH_3 -> NHSUB3) - replace with placeholder
  var_name=$(echo "$var_name" | sed -E 's/([A-Za-z]+)_([0-9]+)/\1SUB\2/g')
  
  # Step 2: Convert all numbers after letters to subscripts (NH4 -> NH$_4$, NHSUB3 -> NH$_3$)
  # Match letter(s) followed by "SUB" + digit(s) or just digit(s)
  var_name=$(echo "$var_name" | sed -E 's/([A-Za-z]+)SUB([0-9]+)/\1$_\2$/g')
  var_name=$(echo "$var_name" | sed -E 's/([A-Za-z]+)([0-9]+)/\1$_\2$/g')
  
  # Step 3: Protect subscripts by replacing $_digit$ with placeholder that includes the digit
  var_name=$(echo "$var_name" | sed -E 's/\$_([0-9]+)\$/SUBSCRIPTPLACEHOLDER\1SUBSCRIPTPLACEHOLDER/g')
  
  # Step 4: Escape all underscores
  var_name=$(echo "$var_name" | sed 's/_/\\_/g')
  
  # Step 5: Restore subscripts (replace placeholder back to $_digit$)
  echo "$var_name" | sed -E 's/SUBSCRIPTPLACEHOLDER([0-9]+)SUBSCRIPTPLACEHOLDER/\$_\1\$/g'
}


