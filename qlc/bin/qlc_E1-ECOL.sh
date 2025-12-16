#!/bin/bash -e

# ============================================================================
# QLC E1-ECOL: Evaltools Collocation Converter
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Creates evaltools Evaluator objects from QLC-PY collocated NetCDF files.
#   Converts qlc-py station collocation output to evaltools format for
#   advanced statistical analysis. Supports multi-experiment and multi-region
#   processing.
#
# Attribution:
#   Uses evaltools (CNRM Open Source by CNRS and Météo-France)
#   https://redmine.umr-cnrm.fr/projects/evaltools/wiki
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
 log  "Create evaltools Evaluator objects from processed NC-files"
 log  "Multi-experiment and multi-region support enabled"
 log  "----------------------------------------------------------------------------------------"

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
pwd -P

# Intelligent module loading with fallback to venv/conda
log "Setting up evaltools with intelligent module loading..."

# Check for evaltools Python environment (integrated or dedicated)
if ! setup_evaltools; then
  log "Error: Failed to setup evaltools" >&2
  exit 1
fi

log "Success: Evaltools configured"
log "EVALTOOLS_PYTHON: $EVALTOOLS_PYTHON"
export EVALTOOLS_PYTHON

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# Experiments come first, followed by dates in YYYY-MM-DD format, optional config at end
# ----------------------------------------------------------------------------------------
parse_qlc_arguments "$@" || exit 1

# Create experiment strings for different uses
experiments_comma=$(IFS=,; echo "${experiments[*]}")
experiments_hyphen=$(IFS=-; echo "${experiments[*]}")

# Process dates
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# Create output directory for evaluators
EVALUATOR_OUTPUT_DIR="${EVALTOOLS_OUTPUT_DIR:-${ANALYSIS_DIRECTORY}/evaluators}"
mkdir -p "$EVALUATOR_OUTPUT_DIR"

# Base path for plots directory
base_hpath="$PLOTS_DIRECTORY/${experiments_hyphen}_${mDate}"

# Path to the qlc_evaluator4evaltools.py script (converter from qlc-py collocation)
EVALTOOLS_SCRIPT=""
SCRIPT_LOCATIONS=(
    "${CONFIG_DIR}/workflows/evaltools/qlc_evaluator4evaltools.py"
)

for loc in "${SCRIPT_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        EVALTOOLS_SCRIPT="$loc"
        break
    fi
done

# Check if script was found
if [ -z "$EVALTOOLS_SCRIPT" ] || [ ! -f "$EVALTOOLS_SCRIPT" ]; then
    log "Warning: qlc_evaluator4evaltools.py not found in:"
    for loc in "${SCRIPT_LOCATIONS[@]}"; do
        log "  - $loc"
    done
    log "Evaluator objects will not be created"
    log "________________________________________________________________________________________"
    log "End ${SCRIPT} at `date`"
    exit 0
fi

log "Found evaltools converter script: $EVALTOOLS_SCRIPT"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to extract variables and experiments from NetCDF file metadata
# This reads the actual variable names from the NetCDF structure
extract_metadata_from_netcdf() {
    local nc_file=$1
    
    # Use Python with netCDF4 to extract variable names and experiment names
    # Note: All logging goes to stderr, only data goes to stdout
    python3 << EOF
import sys
import netCDF4 as nc

try:
    # Open NetCDF file
    ds = nc.Dataset('${nc_file}', 'r')
    
    # Get all variable names
    all_vars = list(ds.variables.keys())
    
    # Extract variable name (those ending with _obs)
    var_names = set()
    for var in all_vars:
        if var.endswith('_obs'):
            # Variable name is everything before _obs
            base_var = var.replace('_obs', '')
            var_names.add(base_var)
    
    # Extract experiment names (variables matching <var>_<exp> pattern)
    exp_names = set()
    for base_var in var_names:
        for var in all_vars:
            if var.startswith(base_var + '_') and not var.endswith('_obs'):
                # Extract experiment name (everything after <var>_)
                exp_name = var.replace(base_var + '_', '')
                exp_names.add(exp_name)
    
    ds.close()
    
    # Output format: var1,var2,var3|exp1,exp2,exp3
    # IMPORTANT: Only output data to stdout, no logging or debug info
    vars_str = ','.join(sorted(var_names))
    exps_str = ','.join(sorted(exp_names))
    print(f"{vars_str}|{exps_str}")
    sys.exit(0)
    
except Exception as e:
    # Errors go to stderr
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Function to extract experiment names and variables from collocated NetCDF files
# for a specific time average
extract_experiments_and_variables_from_collocated_files() {
    local search_dir=$1
    local time_avg=$2
    local exp_set=()
    local var_set=()
    
    log "Extracting experiments and variables from collocated files in: ${search_dir}"
    log "  Time average filter: ${time_avg}"
    
    # Determine file extension from SAVE_DATA_FORMAT (default to nc)
    local data_ext="${SAVE_DATA_FORMAT:-nc}"
    
    # Check if CSV files are found - evaltools requires NetCDF format
    local csv_files=()
    csv_files+=($(find "${search_dir}" -maxdepth 1 -type f -name "qlc_D1-ANAL_*_*_*_*_${time_avg}_collocated_obs_mod_*.csv" 2>/dev/null))
    
    if [ ${#csv_files[@]} -gt 0 ] && [ "$data_ext" != "nc" ]; then
        log "ERROR: CSV format files found, but NetCDF format required!"
        log "  Found ${#csv_files[@]} CSV file(s):"
        for csv_file in "${csv_files[@]}"; do
            log "    - $(basename "$csv_file")"
        done
        log "  Evaltools evaluator creation requires NetCDF format files (.nc)"
        log "  Please set SAVE_DATA_FORMAT=nc in your configuration"
        log "  Or re-run qlc_D1-ANAL.sh with SAVE_DATA_FORMAT=nc to generate NetCDF files"
        return 1
    fi
    
    # Find collocated files using new naming convention (qlc_D1-ANAL_*)
    # Pattern: {output_base}_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.nc
    # Example: qlc_D1-ANAL_AIFS-COMPO_US_Airnow_stations-test_O3_20251101-20251103_3hourly_collocated_obs_mod_9191.nc
    local collocated_files=()
    
    log "  Searching for files with time average: ${time_avg}"
    collocated_files=($(find "${search_dir}" -maxdepth 1 -type f -name "qlc_D1-ANAL_*_*_*_*_${time_avg}_collocated_obs_mod_*.${data_ext}" 2>/dev/null))
    
    if [ ${#collocated_files[@]} -eq 0 ]; then
        log "ERROR: No collocated files found for time average: ${time_avg} (format: ${data_ext})"
        log "  Searched pattern:"
        log "    - qlc_D1-ANAL_*_*_*_*_${time_avg}_collocated_obs_mod_*.${data_ext}"
        log "  Expected format: {output_base}_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.${data_ext}"
        if [ "$data_ext" != "nc" ]; then
            log "  Evaltools requires NetCDF format (.nc) - please set SAVE_DATA_FORMAT=nc"
        fi
        return 1
    fi
    
    log "  Found ${#collocated_files[@]} collocated file(s) for ${time_avg}"
    
    # Process each file to extract metadata
    for nc_file in "${collocated_files[@]}"; do
        local nc_basename=$(basename "$nc_file")
        log "  Processing: ${nc_basename}"
        
        # Extract metadata from NetCDF (capture both stdout and stderr separately)
        local temp_err=$(mktemp)
        local metadata=$(extract_metadata_from_netcdf "$nc_file" 2>"$temp_err")
        local extract_status=$?
        
        if [ $extract_status -eq 0 ] && [ -n "$metadata" ]; then
            log "    Extracted metadata: ${metadata}"
            # Parse output: var1,var2|exp1,exp2
            local vars_part=$(echo "$metadata" | cut -d'|' -f1)
            local exps_part=$(echo "$metadata" | cut -d'|' -f2)
            
            # Add variables to set
            if [ -n "$vars_part" ]; then
                IFS=',' read -ra vars_array <<< "$vars_part"
                for var in "${vars_array[@]}"; do
                    if [[ ! " ${var_set[*]} " =~ " ${var} " ]]; then
                        var_set+=("$var")
                        log "    Found variable: $var"
                    fi
                done
            fi
            
            # Add experiments to set
            if [ -n "$exps_part" ]; then
                IFS=',' read -ra exps_array <<< "$exps_part"
                for exp in "${exps_array[@]}"; do
                    if [[ ! " ${exp_set[*]} " =~ " ${exp} " ]]; then
                        exp_set+=("$exp")
                        log "    Found experiment: $exp"
                    fi
                done
            fi
        else
            log "    Warning: Could not extract metadata from ${nc_basename}"
            if [ -s "$temp_err" ]; then
                log "    Error details: $(cat $temp_err)"
            fi
        fi
        rm -f "$temp_err"
    done
    
    if [ ${#var_set[@]} -eq 0 ] || [ ${#exp_set[@]} -eq 0 ]; then
        log "Error: No variables or experiments found in NetCDF files"
        log "  Variables: ${#var_set[@]}"
        log "  Experiments: ${#exp_set[@]}"
        return 1
    fi
    
    # Export results (including the actual file paths found)
    discovered_experiments=("${exp_set[@]}")
    discovered_variables=$(IFS=,; echo "${var_set[*]}")
    discovered_collocated_files=("${collocated_files[@]}")
    
    log "Total experiments found: ${#discovered_experiments[@]} (${discovered_experiments[*]})"
    log "Total variables found: ${discovered_variables}"
    log "Total collocated files found: ${#discovered_collocated_files[@]}"
    
    return 0
}

# Function to process a single region with a specific time average
process_single_region_and_timeavg() {
    local region_name=$1
    local region_hpath=$2
    local time_avg=$3
    
    log "========================================"
    log "Processing region: ${region_name}, time average: ${time_avg}"
    log "========================================"
    log "Region path: ${region_hpath}"
    
    # Check if directory exists
    if [ ! -d "$region_hpath" ]; then
        log "Error: Region directory not found: ${region_hpath}"
        return 1
    fi
    
    # Check for existing evaluator files for this specific time average and remove them for regeneration
    local existing_evaluators=($(find "$EVALUATOR_OUTPUT_DIR" -name "${region_name}_*_${sDate}-${eDate}_*_${time_avg}.evaluator.evaltools" 2>/dev/null))
    
    if [ ${#existing_evaluators[@]} -gt 0 ]; then
        log "Found ${#existing_evaluators[@]} existing evaluator file(s) for ${region_name} (${time_avg})"
        log "  Removing existing files for regeneration:"
        for eval_file in "${existing_evaluators[@]}"; do
            log "    Removing: $(basename "$eval_file")"
            rm -f "$eval_file"
        done
        log "  Files removed. Proceeding with regeneration..."
    fi
    
    # Extract experiments and variables from NetCDF metadata for this specific time average
    # This function finds collocated files and extracts metadata from them
    if ! extract_experiments_and_variables_from_collocated_files "${region_hpath}" "${time_avg}"; then
        log "Error: Could not extract experiments and variables from NetCDF files for ${time_avg}"
        log "Skipping region ${region_name}, time average ${time_avg}"
        return 1
    fi
    
    # Create a temporary JSON config file for evaluator creation
    # Pattern: qlc_E1_evaltools_config_{region}_{daterange}_{time_avg}.json
    local temp_config_file="${region_hpath}/qlc_E1_evaltools_config_${region_name}_${sDate}-${eDate}_${time_avg}.json"
    rm -f "$temp_config_file"
    
    # Create experiments string for JSON (comma-separated)
    local experiments_json=$(IFS=,; echo "${discovered_experiments[*]}")
    
    # Create JSON array of collocated file paths
    local collocated_files_json="["
    local first=true
    for file in "${discovered_collocated_files[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            collocated_files_json+=", "
        fi
        collocated_files_json+="\"$file\""
    done
    collocated_files_json+="]"
    
    log "Creating JSON configuration for ${region_name} (${time_avg}): ${temp_config_file}"
    log "  Experiments: ${experiments_json}"
    log "  Variables: ${discovered_variables}"
    log "  Region: ${region_name}"
    log "  Time average: ${time_avg}"
    log "  Collocated files to process: ${#discovered_collocated_files[@]}"
    
    # Get region plot code and bounds from configuration
    local plot_region_var="REGION_${region_name}_PLOT_REGION"
    local plot_region="${!plot_region_var:-Globe}"
    log "  Plot region code: ${plot_region}"
    
    # Get region bounds from style.py REGION_METADATA (-180/180 convention for evaltools)
    local region_bounds=$("${EVALTOOLS_PYTHON}" -c "
try:
    import qlc.py.style as style
    bounds = style.get_region_bounds('${plot_region}', normalize_to_0_360=False)
    print(' '.join(map(str, bounds)))
except Exception as e:
    # Fallback to Globe bounds on any error
    print('-90.0 90.0 -180.0 180.0')
" 2>/dev/null)
    
    # Parse bounds: lat_min lat_max lon_min lon_max
    read lat_min lat_max lon_min lon_max <<< "$region_bounds"
    log "  Region bounds (-180/180 convention): lat[${lat_min},${lat_max}] lon[${lon_min},${lon_max}]"
    
    # Set output file pattern (avoiding brace expansion in heredoc)
    : ${EVALTOOLS_OUTPUT_PATTERN:='{region}_{model}_{start}-{end}_{species}_{time_res}.evaluator.evaltools'}
    
    cat > "$temp_config_file" << EOM
{
  "general": {
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "species_list": "${discovered_variables}",
    "models": "${experiments_json}",
    "region": "${region_name}",
    "time_average": "${time_avg}",
    "forecast_horizon": ${EVALTOOLS_FORECAST_HORIZON:-1},
    "availability_ratio": ${EVALTOOLS_AVAILABILITY_RATIO:-0.25},
    "save_data_format": "${SAVE_DATA_FORMAT:-nc}",
    "default_station_lat": ${EVALTOOLS_DEFAULT_STATION_LAT:-0.0},
    "default_station_lon": ${EVALTOOLS_DEFAULT_STATION_LON:-0.0},
    "default_station_altitude": ${EVALTOOLS_DEFAULT_STATION_ALTITUDE:-0.0}
  },
  "region_info": {
    "plot_region": "${plot_region}",
    "lat_min": ${lat_min},
    "lat_max": ${lat_max},
    "lon_min": ${lon_min},
    "lon_max": ${lon_max}
  },
  "model_colors": {
    "b2ro": "${EVALTOOLS_MODEL_COLOR_B2RO:-firebrick}",
    "b2rn": "${EVALTOOLS_MODEL_COLOR_B2RN:-dodgerblue}",
    "b2rm": "${EVALTOOLS_MODEL_COLOR_B2RM:-forestgreen}",
    "b285": "${EVALTOOLS_MODEL_COLOR_B285:-lime}",
    "b287": "${EVALTOOLS_MODEL_COLOR_B287:-red}",
    "b289": "${EVALTOOLS_MODEL_COLOR_B289:-chocolate}",
    "default": "${EVALTOOLS_MODEL_COLOR_DEFAULT:-blue}"
  },
  "listing": {
    "listing_name": "${EVALTOOLS_LISTING_NAME:-stations_from_collocated.csv}",
    "listing_dir": "${region_hpath}"
  },
  "input_output": {
    "plots_dir": "${region_hpath}",
    "output_dir": "${EVALUATOR_OUTPUT_DIR}",
    "temp_dir": "${EVALUATOR_OUTPUT_DIR}/temp",
    "output_file_pattern": "${EVALTOOLS_OUTPUT_PATTERN}",
    "collocated_files": ${collocated_files_json}
  },
  "metadata": {
    "user": "$(echo $USER)",
    "host": "$(hostname -s)",
    "qlc_version": "${QLC_VERSION:-0.4.1}",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "command": "qlc_E1-ECOL.sh ${experiments[*]} ${sDat} ${eDat}",
    "note": "Stations extracted from qlc_D1_*_collocated.csv files (actual collocated data)",
    "region": "${region_name}",
    "multi_region_mode": "${MULTI_REGION_MODE:-false}"
  }
}
EOM
    
    log "JSON configuration generated successfully"
    
    # Run the converter
    log "Converting qlc-py collocation to evaltools evaluators..."
    log "Running: python $EVALTOOLS_SCRIPT --config $temp_config_file"
    
    # Run the converter and capture exit status
    local converter_exit=0
    "${EVALTOOLS_PYTHON}" "$EVALTOOLS_SCRIPT" --config "$temp_config_file" 2>&1 || converter_exit=$?
    
    # Count created evaluators for this region and time average
    local created_count=0
    for exp in "${discovered_experiments[@]}"; do
        local exp_files=$(find "$EVALUATOR_OUTPUT_DIR" -name "${region_name}_${exp}_${sDate}-${eDate}_*_${time_avg}.evaluator.evaltools" 2>/dev/null | wc -l)
        created_count=$((created_count + exp_files))
    done
    
    log "  Created: $created_count evaluator file(s) for ${region_name} (${time_avg})"
    
    if [ $created_count -gt 0 ]; then
        log "Successfully converted to evaltools evaluators for ${region_name} (${time_avg})"
        log "  Output directory: ${EVALUATOR_OUTPUT_DIR}/"
        log "  Created files:"
        for exp in "${discovered_experiments[@]}"; do
            local example_files=($(find "$EVALUATOR_OUTPUT_DIR" -name "${region_name}_${exp}_${sDate}-${eDate}_*_${time_avg}.evaluator.evaltools" 2>/dev/null))
            for f in "${example_files[@]}"; do
                if [ -n "$f" ]; then
                    log "    - $(basename "$f")"
                fi
            done
        done
    else
        log "ERROR: No evaluator files were created for ${region_name} (${time_avg})"
        log "  Check log for details: $E1_LOG"
        log "  JSON config: $temp_config_file"
        log "  You can run the converter manually:"
        log "    ${EVALTOOLS_PYTHON} $EVALTOOLS_SCRIPT --config $temp_config_file --debug"
        return 1
    fi
    
    # Check converter exit status
    if [ $converter_exit -ne 0 ]; then
        log "ERROR: Converter exited with error code $converter_exit"
        log "  Check log for details: $E1_LOG"
        return 1
    fi
    
    log "Completed processing region: ${region_name}, time average: ${time_avg}"
    return 0
}

# Function to process a single region (loops over time averages)
process_single_region() {
    local region_name=$1
    local region_hpath=$2
    
    log "========================================"
    log "Processing region: ${region_name}"
    log "========================================"
    
    # Parse TIME_AVERAGE as comma-separated list
    IFS=',' read -ra time_avg_list <<< "${TIME_AVERAGE}"
    log "TIME_AVERAGE settings: ${time_avg_list[*]}"
    log "Will process ${#time_avg_list[@]} time averaging value(s) for this region"
    
    local success_count=0
    local fail_count=0
    
    # Loop over each time average
    for time_avg in "${time_avg_list[@]}"; do
        log ""
        log "----------------------------------------"
        log "Processing time average: ${time_avg}"
        log "----------------------------------------"
        
        if process_single_region_and_timeavg "${region_name}" "${region_hpath}" "${time_avg}"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    log ""
    log "========================================"
    log "Region ${region_name} processing complete"
    log "  Time averages successful: ${success_count}"
    log "  Time averages failed/skipped: ${fail_count}"
    log "========================================"
    
    # Return success if at least one time average succeeded
    if [ $success_count -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to detect and process multi-region mode
process_multi_region() {
    log "Multi-region mode detection..."
    
    # Check if base directory exists
    if [ ! -d "$base_hpath" ]; then
        log "Error: Base plots directory not found: ${base_hpath}"
        log "Please ensure qlc_D1-ANAL.sh has been run successfully."
        exit 1
    fi
    
    # Look for region subdirectories
    local region_dirs=()
    local temp_file=$(mktemp)
    
    # Find directories and write to temp file
    find "${base_hpath}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null > "$temp_file"
    
    # Read from temp file
    while IFS= read -r dir; do
        if [ -d "$dir" ]; then
            local region_name=$(basename "$dir")
            # Skip if it's a file or hidden directory
            if [[ ! "$region_name" =~ ^\. ]]; then
                region_dirs+=("$dir")
            fi
        fi
    done < "$temp_file"
    
    # Clean up temp file
    rm -f "$temp_file"
    
    if [ ${#region_dirs[@]} -eq 0 ]; then
        log "No region subdirectories found - processing base directory"
        # Process base directory as single region (legacy mode)
        process_single_region "${DEFAULT_REGION_NAME:-default}" "${base_hpath}"
    else
        log "Found ${#region_dirs[@]} region subdirectories - multi-region mode active"
        
        # Process each region
        local success_count=0
        local fail_count=0
        
        for region_dir in "${region_dirs[@]}"; do
            local region_name=$(basename "$region_dir")
            
            if process_single_region "${region_name}" "${region_dir}"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        done
        
        log "========================================"
        log "Multi-region processing complete"
        log "  Successful: ${success_count}"
        log "  Failed/Skipped: ${fail_count}"
        log "========================================"
        
        if [ ${success_count} -eq 0 ]; then
            log "Error: No regions were processed successfully"
            exit 1
        fi
    fi
    
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log "Starting evaluator generation..."
log "Base directory: ${base_hpath}"
log "Output directory: ${EVALUATOR_OUTPUT_DIR}"

# Process regions (auto-detects multi-region vs single-region)
if ! process_multi_region; then
    log "Error: Failed to process regions"
    exit 1
fi

log "Ready for plotting with evaltools (qlc_E2-EVAL.sh)"
log "Next step: qlc_E2-EVAL.sh will use these evaluators to create evaltools plots"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
