#!/bin/bash -e

# ============================================================================
# QLC_D1_MULTI_REGION - Implementation
# ============================================================================

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="python"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create Python plots for selected variables (multi-region mode)"
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

# Module load for ATOS
myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`
#log   ${HOST} ${ARCH}
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
    module load python3/3.10.10-01
fi

# Check if qlc-py exists
if ! command_exists qlc-py; then
  log  "Error: qlc-py command not found" >&2
  exit 1
else
  log  "Success: qlc-py command found"
  which qlc-py
fi

# Create output directory if not existent
if [    ! -d "$PLOTS_DIRECTORY" ]; then
    mkdir -p "$PLOTS_DIRECTORY"
fi

# Get script name without path and extension
script_name="${SCRIPT##*/}"     # Remove directory path
script_name="${script_name%.*}" # Remove extension
QLTYPE="$script_name"

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# Experiments come first, followed by dates in YYYY-MM-DD format, optional config at end
# ----------------------------------------------------------------------------------------
parse_qlc_arguments "$@" || exit 1

# Create experiment strings for different uses
experiments_comma=$(IFS=,; echo "${experiments[*]}")  # Comma-separated for JSON
experiments_hyphen=$(IFS=-; echo "${experiments[*]}") # Hyphen-separated for paths
exp1="${experiments[0]}" # Keep exp1 for backward compatibility in some operations

# Process dates
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"
ext="${QLTYPE}.pdf"

# Base path for outputs
base_hpath="$PLOTS_DIRECTORY/${experiments_hyphen}_${mDate}"

# ============================================================================
# MULTI-REGION SUPPORT FUNCTIONS
# ============================================================================

# Function to get MARS retrievals for current region (with override support)
get_region_mars_retrievals() {
    local region_code=$1
    local override_var="REGION_${region_code}_MARS_RETRIEVALS[@]"
    
    if compgen -v | grep -q "^REGION_${region_code}_MARS_RETRIEVALS$"; then
        # Use region-specific override
        local region_retrievals=("${!override_var}")
        log "Using region-specific MARS_RETRIEVALS for ${region_code}: ${region_retrievals[*]}"
        echo "${region_retrievals[@]}"
    else
        # Use global default
        log "Using global MARS_RETRIEVALS for ${region_code}: ${MARS_RETRIEVALS[*]}"
        echo "${MARS_RETRIEVALS[@]}"
    fi
}

# Function to discover available variables from MARS_RETRIEVALS
discover_available_variables() {
    local mars_retrievals=("$@")
    log "Discovering variables from MARS_RETRIEVALS..."
    available_vars=()
    
    if [[ ${#mars_retrievals[@]} -eq 0 ]]; then
        log "Warning: MARS_RETRIEVALS array is empty. Using file-based discovery."
        available_vars=($(find "${ANALYSIS_DIRECTORY}/${exp1}" -type f -name "*.nc" ! -name "*_tavg.nc" -print0 | \
            xargs -0 -n 1 basename | \
            sed -E 's/.*_[A-Z][0-9]+_[a-z]+_(.*)\.nc/\1/' | \
            sort -u))
    else
        for name in "${mars_retrievals[@]}"; do
            # Use eval for safer indirect array expansion (works across bash versions)
            eval "myvars=(\"\${myvar_${name}[@]}\")" 2>/dev/null || myvars=()
            
            for var_name in "${myvars[@]}"; do
                if compgen -G "${ANALYSIS_DIRECTORY}/${exp1}/*_${var_name}.nc" > /dev/null; then
                    available_vars+=("$var_name")
                fi
            done
        done
        # De-duplicate
        available_vars=($(printf "%s\n" "${available_vars[@]}" | sort -u))
    fi
    
    if [ ${#available_vars[@]} -eq 0 ]; then
        log "Error: Could not find any variables in MARS_RETRIEVALS."
        return 1
    fi
    
    log "Available variables from MARS_RETRIEVALS: ${available_vars[*]}"
    return 0
}

# Function to load region-specific configuration
load_region_config() {
    local region_code=$1
    
    # Use indirect variable expansion to get region settings
    CURRENT_REGION_NAME="${region_code}"
    CURRENT_REGION_OBS_PATH=$(eval echo \${REGION_${region_code}_OBS_PATH})
    CURRENT_REGION_OBS_DATASET_TYPE=$(eval echo \${REGION_${region_code}_OBS_DATASET_TYPE})
    CURRENT_REGION_OBS_DATASET_VERSION=$(eval echo \${REGION_${region_code}_OBS_DATASET_VERSION:-latest})
    CURRENT_REGION_STATION_FILE=$(eval echo \${REGION_${region_code}_STATION_FILE})
    CURRENT_REGION_PLOT_REGION=$(eval echo \${REGION_${region_code}_PLOT_REGION})
    CURRENT_REGION_VARIABLES=$(eval echo \${REGION_${region_code}_VARIABLES})
    CURRENT_REGION_STATION_RADIUS_DEG=$(eval echo \${REGION_${region_code}_STATION_RADIUS_DEG})
    
    log "Loaded configuration for region: ${CURRENT_REGION_NAME}"
    log "  OBS_PATH: ${CURRENT_REGION_OBS_PATH}"
    log "  OBS_DATASET_TYPE: ${CURRENT_REGION_OBS_DATASET_TYPE}"
    log "  STATION_FILE: ${CURRENT_REGION_STATION_FILE}"
    log "  PLOT_REGION: ${CURRENT_REGION_PLOT_REGION}"
    log "  REQUESTED_VARIABLES: ${CURRENT_REGION_VARIABLES}"
    log "  STATION_RADIUS_DEG: ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG} (global default)}"
    
    # Validate required parameters
    if [ -z "$CURRENT_REGION_OBS_PATH" ] || [ -z "$CURRENT_REGION_OBS_DATASET_TYPE" ]; then
        log "Error: Missing required configuration for region ${region_code}"
        return 1
    fi
    
    # Warn if station file doesn't exist
    if [ -n "$CURRENT_REGION_STATION_FILE" ] && [ ! -f "$CURRENT_REGION_STATION_FILE" ]; then
        log "Warning: Station file not found: ${CURRENT_REGION_STATION_FILE}"
    fi
    
    # Warn if obs path doesn't exist
    if [ ! -d "$CURRENT_REGION_OBS_PATH" ]; then
        log "Warning: Observation data path not found: ${CURRENT_REGION_OBS_PATH}"
    fi
    
    return 0
}

# Function to filter region variables based on available MARS variables
filter_region_variables() {
    # Split requested variables by comma
    IFS=',' read -ra region_vars <<< "$CURRENT_REGION_VARIABLES"
    
    # Filter to only include available variables
    local filtered_vars=()
    local missing_vars=()
    
    for rv in "${region_vars[@]}"; do
        # Trim whitespace
        rv=$(echo "$rv" | xargs)
        
        if [[ " ${available_vars[*]} " =~ " ${rv} " ]]; then
            filtered_vars+=("$rv")
        else
            missing_vars+=("$rv")
        fi
    done
    
    # Report results
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log "Warning: Variables requested for ${CURRENT_REGION_NAME} but not available in MARS_RETRIEVALS:"
        log "  Missing: ${missing_vars[*]}"
    fi
    
    if [ ${#filtered_vars[@]} -eq 0 ]; then
        log "Error: No valid variables found for region ${CURRENT_REGION_NAME}"
        log "  Requested: ${CURRENT_REGION_VARIABLES}"
        log "  Available: ${available_vars[*]}"
        return 1
    fi
    
    # Store filtered variables
    CURRENT_REGION_VARIABLES_FILTERED=$(IFS=,; echo "${filtered_vars[*]}")
    CURRENT_REGION_VARIABLES_ARRAY=("${filtered_vars[@]}")
    
    log "Variables to process for ${CURRENT_REGION_NAME}: ${CURRENT_REGION_VARIABLES_FILTERED}"
    return 0
}

# Function to generate region-specific JSON configuration
generate_region_json() {
    local region_hpath="${base_hpath}/${CURRENT_REGION_NAME}"
    mkdir -p "$region_hpath"
    
    local temp_config_file="${region_hpath}/temp_qlc_D1_config.json"
    local texPlotsfile="${region_hpath}/texPlotfiles_${QLTYPE}.list"
    local texFile="${texPlotsfile%.list}.tex"
    
    # Clean up old files
    rm -f "$texPlotsfile" "$temp_config_file" "$texFile"
    touch "$texPlotsfile"
    
    log "Generating JSON configuration for ${CURRENT_REGION_NAME}: ${temp_config_file}"
    
    # Generate JSON with three entries: obs-only, mod-only, collocation
    cat > "$temp_config_file" << EOM
[
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${region_hpath}/${QLTYPE}",
    "station_file": "${CURRENT_REGION_STATION_FILE:-""}",
    "obs_path": "${CURRENT_REGION_OBS_PATH:-""}",
    "obs_dataset_type": "${CURRENT_REGION_OBS_DATASET_TYPE:-""}",
    "obs_dataset_version": "${CURRENT_REGION_OBS_DATASET_VERSION:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${CURRENT_REGION_VARIABLES_FILTERED}",
    "plot_region": "${CURRENT_REGION_PLOT_REGION:-""}",
    "station_radius_deg": ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG:-0.5}},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": true,
    "show_station_timeseries_obs": true,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": false,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${CURRENT_REGION_PLOT_REGION:-""}, ${CURRENT_REGION_VARIABLES_FILTERED}",
      "summary": "netCDF output: ${CURRENT_REGION_OBS_DATASET_TYPE:-""} observations for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  },
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${region_hpath}/${QLTYPE}",
    "station_file": "${CURRENT_REGION_STATION_FILE:-""}",
    "mod_path": "${ANALYSIS_DIRECTORY:-""}",
    "model": "${MODEL:-""}",
    "experiments": "${experiments_comma}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${CURRENT_REGION_VARIABLES_FILTERED}",
    "plot_region": "${CURRENT_REGION_PLOT_REGION:-""}",
    "station_radius_deg": ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG:-0.5}},
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "show_station_timeseries_obs": false,
    "show_station_timeseries_mod": true,
    "show_station_timeseries_com": false,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${CURRENT_REGION_PLOT_REGION:-""}, ${CURRENT_REGION_VARIABLES_FILTERED}",
      "summary": "netCDF output: Model data for ${experiments_comma} for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  },
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${region_hpath}/${QLTYPE}",
    "station_file": "${CURRENT_REGION_STATION_FILE:-""}",
    "obs_path": "${CURRENT_REGION_OBS_PATH:-""}",
    "obs_dataset_type": "${CURRENT_REGION_OBS_DATASET_TYPE:-""}",
    "obs_dataset_version": "${CURRENT_REGION_OBS_DATASET_VERSION:-""}",
    "mod_path": "${ANALYSIS_DIRECTORY:-""}",
    "model": "${MODEL:-""}",
    "experiments": "${experiments_comma}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${CURRENT_REGION_VARIABLES_FILTERED}",
    "plot_region": "${CURRENT_REGION_PLOT_REGION:-""}",
    "station_radius_deg": ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG:-0.5}},
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": false,
    "show_station_timeseries_obs": false,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": true,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${CURRENT_REGION_PLOT_REGION:-""}, ${CURRENT_REGION_VARIABLES_FILTERED}",
      "summary": "netCDF output: Collocated model and observation data for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  }
]
EOM
    
    log "JSON configuration generated successfully"
    
    # Store paths for later use
    CURRENT_REGION_CONFIG_FILE="$temp_config_file"
    CURRENT_REGION_HPATH="$region_hpath"
    CURRENT_REGION_TEXFILE="$texFile"
    CURRENT_REGION_TEXPLOTSFILE="$texPlotsfile"
    
    return 0
}

# Function to execute qlc-py for a region
execute_qlc_py_for_region() {
    log "Executing qlc-py for region ${CURRENT_REGION_NAME}..."
    log "Config file: ${CURRENT_REGION_CONFIG_FILE}"
    
    # Execute qlc-py
    qlc-py --config "${CURRENT_REGION_CONFIG_FILE}"
    
    if [ $? -ne 0 ]; then
        log "Error: qlc-py execution failed for region ${CURRENT_REGION_NAME}"
        return 1
    fi
    
    log "qlc-py execution completed successfully for ${CURRENT_REGION_NAME}"
    return 0
}

# Function to generate TeX file for region
generate_region_tex() {
    log "Generating TeX file for region ${CURRENT_REGION_NAME}..."
    
    rm -f "${CURRENT_REGION_TEXPLOTSFILE}"
    touch "${CURRENT_REGION_TEXPLOTSFILE}"
    
    # Helper function to find and add plots
    add_plot_if_found() {
        local plot_pattern=$1
        find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f -name "${plot_pattern}" 2>/dev/null | sort | while IFS= read -r plot_file; do
            if [ -n "$plot_file" ] && ! grep -qF "$plot_file" "${CURRENT_REGION_TEXPLOTSFILE}"; then
                echo "$plot_file" >> "${CURRENT_REGION_TEXPLOTSFILE}"
                log "Added plot to TeX list: $plot_file"
            fi
        done
    }
    
    # Loop through each variable to control plot order
    for var in "${CURRENT_REGION_VARIABLES_ARRAY[@]}"; do
        log "Ordering plots for variable: $var"
        
        # Find plots in specified order
        add_plot_if_found "*${var}*collocated*regional_mean*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*collocated*regional_bias*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*collocated*stats_plot_Error_Metrics*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*collocated*stats_plot_Correlation_Metrics*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*collocated*stats_plot_Descriptive_Statistics*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*val.${PLOTEXTENSION}"
    done
    
    # Generate TeX file header
    local tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
    local tREGION=$(echo "${CURRENT_REGION_NAME}" | sed 's/_/\\_/g')
    
    cat > "${CURRENT_REGION_TEXFILE}" <<EOF
%===============================================================================
\subsection{${tQLTYPE} -- ${tREGION} -- ${mDate} (${TIME_AVERAGE})}
EOF
    
    # Add frames for each plot
    if [ -s "${CURRENT_REGION_TEXPLOTSFILE}" ]; then
        while IFS= read -r plot_path; do
            plot_filename=$(basename -- "$plot_path")
            var_name_tex=""
            title_prefix=""
            
            # Extract variable name for title
            for var in "${CURRENT_REGION_VARIABLES_ARRAY[@]}"; do
                if [[ "$plot_filename" == *"${var}"* ]]; then
                    var_name_tex=$(echo "$var" | sed 's/_/\\_/g')
                    break
                fi
            done
            
            # Determine title prefix based on plot type
            case "$plot_filename" in
                *regional_bias*)
                    title_prefix="Collocation time series bias" ;;
                *stats_plot_Error_Metrics*)
                    title_prefix="Collocation error stats" ;;
                *stats_plot_Correlation_Metrics*)
                    title_prefix="Collocation correlation stats" ;;
                *stats_plot_Descriptive_Statistics*)
                    title_prefix="Collocation descriptive stats" ;;
                *val.*)
                    title_prefix="Collocation map value plot" ;;
                *regional_mean*)
                    title_prefix="Collocation time series" ;;
                *)
                    title_prefix="Collocation station plot" ;;
            esac
            
            # Build experiment list for title
            experiments_tex=""
            for i in "${!experiments[@]}"; do
                exp_escaped=$(echo "${experiments[$i]}" | sed 's/_/\\_/g')
                if [ $i -eq 0 ]; then
                    experiments_tex="$exp_escaped"
                elif [ $i -eq $((${#experiments[@]} - 1)) ]; then
                    experiments_tex="${experiments_tex} vs ${exp_escaped}"
                else
                    experiments_tex="${experiments_tex}, ${exp_escaped}"
                fi
            done
            
            title_final="${title_prefix} for ${var_name_tex} of ${experiments_tex} (${tREGION})"
            
            # Append frame to TeX file
            cat >> "${CURRENT_REGION_TEXFILE}" <<EOF
%===============================================================================
\frame{
\frametitle{${title_final}}
\vspace{0mm}
\centering
\includegraphics[width=0.9\textwidth]{${plot_path}}
}
EOF
            log "Generated TeX frame for $plot_filename"
        done < "${CURRENT_REGION_TEXPLOTSFILE}"
        
        log "Finished generating TeX file: ${CURRENT_REGION_TEXFILE}"
    else
        log "No plots found for region ${CURRENT_REGION_NAME}"
    fi
    
    return 0
}

# Function to process a single region
process_single_region() {
    local region_code=$1
    
    log "========================================" 
    log "Processing region: ${region_code}"
    log "========================================"
    
    # Load region configuration
    if ! load_region_config "${region_code}"; then
        log "Skipping region ${region_code} due to configuration error"
        return 1
    fi
    
    # Filter variables
    if ! filter_region_variables; then
        log "Skipping region ${region_code} - no valid variables"
        return 1
    fi
    
    # Generate JSON configuration
    if ! generate_region_json; then
        log "Error generating JSON for region ${region_code}"
        return 1
    fi
    
    # Execute qlc-py
    if ! execute_qlc_py_for_region; then
        log "Error executing qlc-py for region ${region_code}"
        return 1
    fi
    
    # Generate TeX file
    generate_region_tex
    
    log "Completed processing region: ${region_code}"
    return 0
}

# Function to generate combined TeX file for all regions
generate_combined_tex_file() {
    local combined_tex="${base_hpath}/texPlotfiles_${QLTYPE}_all_regions.tex"
    local tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
    
    log "Generating combined TeX file for all regions: ${combined_tex}"
    
    # Build experiment list for title
    experiments_tex=""
    for i in "${!experiments[@]}"; do
        exp_escaped=$(echo "${experiments[$i]}" | sed 's/_/\\_/g')
        if [ $i -eq 0 ]; then
            experiments_tex="$exp_escaped"
        elif [ $i -eq $((${#experiments[@]} - 1)) ]; then
            experiments_tex="${experiments_tex} vs ${exp_escaped}"
        else
            experiments_tex="${experiments_tex}, ${exp_escaped}"
        fi
    done
    
    # Header
    cat > "$combined_tex" << EOF
%===============================================================================
\section{Multi-Region Analysis: ${tQLTYPE}}
\subsection{Experiments: ${experiments_tex} (${mDate}, ${TIME_AVERAGE})}
EOF
    
    # Add each region's content
    for region_code in "${processed_regions[@]}"; do
        local region_tex="${base_hpath}/${region_code}/texPlotfiles_${QLTYPE}.tex"
        if [ -f "$region_tex" ]; then
            echo "%===============================================================================" >> "$combined_tex"
            echo "% Region: ${region_code}" >> "$combined_tex"
            echo "%===============================================================================" >> "$combined_tex"
            cat "$region_tex" >> "$combined_tex"
        fi
    done
    
    log "Generated combined TeX file: ${combined_tex}"
    
    # Also create a copy with the standard name for qlc_Z1.sh compatibility
    local standard_tex="${base_hpath}/texPlotfiles_${QLTYPE}.tex"
    cp "$combined_tex" "$standard_tex"
    log "Created standard TeX file for Z1 compatibility: ${standard_tex}"
    
    log "Content:"
    cat "$combined_tex"
}

# Main multi-region processing function
process_multi_region() {
    log "Multi-region mode activated"
    
    # Determine regions to process
    local regions_to_process=()
    
    if [ ${#ACTIVE_REGIONS[@]} -gt 0 ]; then
        regions_to_process=("${ACTIVE_REGIONS[@]}")
        log "Processing user-specified regions: ${regions_to_process[*]}"
    else
        # Auto-detect all defined regions
        regions_to_process=($(compgen -A variable | grep '^REGION_.*_NAME$' | \
            sed 's/REGION_\(.*\)_NAME/\1/' | sort -u))
        log "Auto-detected regions: ${regions_to_process[*]}"
    fi
    
    if [ ${#regions_to_process[@]} -eq 0 ]; then
        log "Error: No regions configured. Please define REGION_*_NAME variables in config."
        exit 1
    fi
    
    log "Total regions to process: ${#regions_to_process[@]}"
    
    # Process each region
    local success_count=0
    local fail_count=0
    processed_regions=()
    
    for region_code in "${regions_to_process[@]}"; do
        # Get region-specific MARS_RETRIEVALS or use global
        local region_mars_retrievals=($(get_region_mars_retrievals "${region_code}"))
        
        # Discover available variables for this region
        if discover_available_variables "${region_mars_retrievals[@]}"; then
            if process_single_region "${region_code}"; then
                ((success_count++))
                processed_regions+=("${region_code}")
            else
                ((fail_count++))
            fi
        else
            log "Warning: No variables available for region ${region_code}"
            ((fail_count++))
        fi
    done
    
    # Generate combined TeX file if requested
    if [[ "${TEX_FILE_MODE:-combined}" == "combined" ]] && [ ${#processed_regions[@]} -gt 0 ]; then
        generate_combined_tex_file
    fi
    
    log "========================================" 
    log "Multi-region processing complete"
    log "  Successful: ${success_count}"
    log "  Failed/Skipped: ${fail_count}"
    log "  Processed regions: ${processed_regions[*]}"
    log "========================================"
    
    if [ ${success_count} -eq 0 ]; then
        log "Error: No regions were processed successfully"
        exit 1
    fi
}

# ============================================================================
# LEGACY SINGLE-REGION PROCESSING (Backward Compatibility)
# ============================================================================

process_legacy_single_region() {
    log "Single-region mode (legacy)"
    
    # Create paths for single-region mode
    local hpath="$base_hpath"
    local texPlotsfile="${hpath}/texPlotfiles_${QLTYPE}.list"
    local texFile="${texPlotsfile%.list}.tex"
    local temp_config_file="${hpath}/temp_qlc_D1_config.json"
    
    # Ensure the output directory exists
    mkdir -p "$hpath"
    rm -f "$texPlotsfile" "$temp_config_file" "$texFile"
    touch "$texPlotsfile"
    
    # Dynamically discover variables from config, validated against existing .nc files.
    log "Discovering variables from config and validating against files in ${ANALYSIS_DIRECTORY}/${exp1}..."
    validated_vars=()
    if [[ -z "${MARS_RETRIEVALS[*]}" ]]; then
        log "Warning: MARS_RETRIEVALS array is not defined in the configuration. Falling back to filename parsing."
        # Fallback to the old method if config arrays are missing
        myvar_list_array=($(find "${ANALYSIS_DIRECTORY}/${exp1}" -type f -name "*.nc" ! -name "*_tavg.nc" -print0 | \
            xargs -0 -n 1 basename | \
            sed -E 's/.*_[A-Z][0-9]+_[a-z]+_(.*)\.nc/\1/' | \
            sort -u))
    else
        for name in "${MARS_RETRIEVALS[@]}"; do
            myvar_array_name="myvar_${name}[@]"
            myvars=("${!myvar_array_name}")
    
            for var_name in "${myvars[@]}"; do
                # Check if a file for this variable exists for the first experiment.
                # The pattern looks for any file ending in _<var_name>.nc
                if compgen -G "${ANALYSIS_DIRECTORY}/${exp1}/*_${var_name}.nc" > /dev/null; then
                    validated_vars+=("$var_name")
                fi
            done
        done
        # De-duplicate the results
        myvar_list_array=($(printf "%s\n" "${validated_vars[@]}" | sort -u))
    fi
    
    
    if [ ${#myvar_list_array[@]} -eq 0 ]; then
        log "Error: Could not find any variables to process. Check config and analysis files. Exiting."
        exit 1
    fi
    myvar_list_string=$(IFS=,; echo "${myvar_list_array[*]}")
    log "Found variables: ${myvar_list_string}"
    
    # Dynamically create a temporary JSON config file with three entries.
    cat > "$temp_config_file" << EOM
[
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${hpath}/${QLTYPE}",
    "station_file": "${STATION_FILE:-""}",
    "obs_path": "${OBS_DATA_PATH:-""}",
    "obs_dataset_type": "${OBS_DATASET_TYPE:-""}",
    "obs_dataset_version": "${OBS_DATASET_VERSION:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${myvar_list_string}",
    "plot_region": "${REGION:-""}",
    "station_radius_deg": ${STATION_RADIUS_DEG:-0.5},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": true,
    "show_station_timeseries_obs": true,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": false,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${REGION:-""}, ${myvar_list_string}",
      "summary": "netCDF output: ${OBS_DATASET_TYPE:-""} observations for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  },
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${hpath}/${QLTYPE}",
    "station_file": "${STATION_FILE:-""}",    
    "mod_path": "${ANALYSIS_DIRECTORY:-""}",
    "model": "${MODEL:-""}",
    "experiments": "${experiments_comma}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${myvar_list_string}",
    "plot_region": "${REGION:-""}",
    "station_radius_deg": ${STATION_RADIUS_DEG:-0.5},
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "show_station_timeseries_obs": false,
    "show_station_timeseries_mod": true,
    "show_station_timeseries_com": false,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${REGION:-""}, ${myvar_list_string}",
      "summary": "netCDF output: Model data for ${experiments_comma} for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  },
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${hpath}/${QLTYPE}",
    "station_file": "${STATION_FILE:-""}",
    "obs_path": "${OBS_DATA_PATH:-""}",
    "obs_dataset_type": "${OBS_DATASET_TYPE:-""}",
    "obs_dataset_version": "${OBS_DATASET_VERSION:-""}",
    "mod_path": "${ANALYSIS_DIRECTORY:-""}",
    "model": "${MODEL:-""}",
    "experiments": "${experiments_comma}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${myvar_list_string}",
    "plot_region": "${REGION:-""}",
    "station_radius_deg": ${STATION_RADIUS_DEG:-0.5},
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": false,
    "show_station_timeseries_obs": false,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": true,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${REGION:-""}, ${myvar_list_string}",
      "summary": "netCDF output: Collocated model and observation data for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  }
]
EOM
    
    log "Generated temporary config file for qlc-py: ${temp_config_file}"
    
    # Execute qlc-py with the temporary config file.
    log "Executing qlc-py with the multi-entry config file..."
    qlc-py --config "${temp_config_file}"
    
    # After the run, find the specific final collocation plot(s) and add them to the TeX list.
    log "Searching for final collocation plots in ${hpath}..."
    rm -f "$texPlotsfile" # Start with an empty list
    touch "$texPlotsfile" # Ensure the file exists before grep is called
    
    # Loop through each variable to control the order of plots in the TeX file
    for var in "${myvar_list_array[@]}"; do
        log "Ordering plots for variable: $var"
    
        # Helper function to find a plot and add it to the list if it exists and is not already there
        add_plot_if_found() {
            local plot_pattern=$1
            # Use find and sort to ensure a consistent order if multiple files match
            find "${hpath}" -maxdepth 1 -type f -name "${plot_pattern}" 2>/dev/null | sort | while IFS= read -r plot_file; do
                if [ -n "$plot_file" ] && ! grep -qF "$plot_file" "$texPlotsfile"; then
                    echo "$plot_file" >> "$texPlotsfile"
                    log "Added plot to TeX list: $plot_file"
                fi
            done
        }
    
        # Find plots in the specified order using more precise patterns
        # 1. Time series plots (individual experiments first, then collocated)
        add_plot_if_found "*${var}*collocated*regional_mean*.${PLOTEXTENSION}"
        
        # 2. Bias plot
        add_plot_if_found "*${var}*collocated*regional_bias*.${PLOTEXTENSION}"
        
        # 3. All statistics plots
        add_plot_if_found "*${var}*collocated*stats_plot_Error_Metrics*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*collocated*stats_plot_Correlation_Metrics*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*collocated*stats_plot_Descriptive_Statistics*.${PLOTEXTENSION}"
    
        # 4. Value map plots (individual experiments)
        add_plot_if_found "*${var}*val.${PLOTEXTENSION}"
        
    done
    
    # ----------------------------------------------------------------------------------------
    # Generate a .tex file with frames for each plot found, for inclusion in the final presentation.
    # ----------------------------------------------------------------------------------------
    log "Generating TeX file for plots: ${texFile}"
    
    # Create the main .tex file for this section with a subsection header
    tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
    cat > "$texFile" <<EOF
%===============================================================================
\subsection{${tQLTYPE} -- ${mDate} (${TIME_AVERAGE})}
EOF
    
    # Loop through the found plot files and generate a TeX frame for each
    if [ -s "$texPlotsfile" ]; then
      # Read from the ordered file list
      while IFS= read -r plot_path; do
        plot_filename=$(basename -- "$plot_path")
        var_name_tex=""
        title_prefix=""
    
        # Extract the variable name for the title
        for var in "${myvar_list_array[@]}"; do
            if [[ "$plot_filename" == *"${var}"* ]]; then
                var_name_tex=$(echo "$var" | sed 's/_/\\_/g')
                break
            fi
        done
    
        # Use a case statement for robust title generation
        case "$plot_filename" in
            *regional_bias*)
                title_prefix="Collocation time series bias" ;;
            *stats_plot_Error_Metrics*)
                title_prefix="Collocation error stats" ;;
            *stats_plot_Correlation_Metrics*)
                title_prefix="Collocation correlation stats" ;;
            *stats_plot_Descriptive_Statistics*)
                title_prefix="Collocation descriptive stats" ;;
            *val.*)
                title_prefix="Collocation map value plot" ;;
            *regional_mean*)
                title_prefix="Collocation time series" ;;
            *)
                title_prefix="Collocation station plot" ;;
        esac
        
        # Build experiment list for title - escape underscores for TeX
        experiments_tex=""
        for i in "${!experiments[@]}"; do
            exp_escaped=$(echo "${experiments[$i]}" | sed 's/_/\\_/g')
            if [ $i -eq 0 ]; then
                experiments_tex="$exp_escaped"
            elif [ $i -eq $((${#experiments[@]} - 1)) ]; then
                experiments_tex="${experiments_tex} vs ${exp_escaped}"
            else
                experiments_tex="${experiments_tex}, ${exp_escaped}"
            fi
        done
        
        title_final="${title_prefix} for ${var_name_tex} of ${experiments_tex}"
    
        # Append the frame to the main .tex file
        cat >> "$texFile" <<EOF
%===============================================================================
\frame{
\frametitle{${title_final}}
\vspace{0mm}
\centering
\includegraphics[width=0.9\textwidth]{${plot_path}}
}
EOF
        log "Generated TeX frame for $plot_filename"
      done < "$texPlotsfile"
      log "Finished generating TeX file."
      log "${texFile}"
      cat  "${texFile}"
    else
      log "No plots found to generate TeX file."
    fi
}

# ============================================================================
# MAIN EXECUTION - MODE DETECTION
# ============================================================================

# Check if multi-region mode is enabled
if [[ "${MULTI_REGION_MODE:-false}" == "true" ]]; then
    log "Multi-region mode detected: MULTI_REGION_MODE=true"
    process_multi_region
else
    log "Single-region mode (backward compatibility): MULTI_REGION_MODE=false or unset"
    process_legacy_single_region
fi

# ----------------------------------------------------------------------------------------
# End of script
# ----------------------------------------------------------------------------------------

log "$ANALYSIS_DIRECTORY"
log "$PLOTS_DIRECTORY"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
