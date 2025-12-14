#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create evaltools Evaluator objects from processed NC-files"
 log  "Multi-experiment and multi-region support enabled"
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
pwd -P

# module load for ATOS
myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
module reset
module load conda
fi
if [ "${myOS}" == "Darwin" ]; then
source $HOME/.profile_anaconda
fi
# Check if conda exists
if ! command_exists conda; then
  log  "Error: conda command not found" >&2
  exit 1
else
  log  "Success: conda command found"
  which conda
  conda deactivate
  conda activate evaltools
  which python
fi

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
    "${CONFIG_DIR}/evaltools/qlc_evaluator4evaltools.py"
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
extract_experiments_and_variables_from_collocated_files() {
    local search_dir=$1
    local exp_set=()
    local var_set=()
    
    log "Extracting experiments and variables from collocated NetCDF files in: ${search_dir}"
    
    # Find collocated files
    local collocated_files=($(find "${search_dir}" -maxdepth 1 -type f -name "qlc_D1_*_collocated_obs_*_mod_*.nc" 2>/dev/null))
    
    if [ ${#collocated_files[@]} -eq 0 ]; then
        log "Warning: No collocated NetCDF files found"
        return 1
    fi
    
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
    
    # Export results
    discovered_experiments=("${exp_set[@]}")
    discovered_variables=$(IFS=,; echo "${var_set[*]}")
    
    log "Total experiments found: ${#discovered_experiments[@]} (${discovered_experiments[*]})"
    log "Total variables found: ${discovered_variables}"
    
    return 0
}

# Function to process a single region (or base directory for legacy mode)
process_single_region() {
    local region_name=$1
    local region_hpath=$2
    
    log "========================================"
    log "Processing region: ${region_name}"
    log "========================================"
    log "Region path: ${region_hpath}"
    
    # Check if directory exists
    if [ ! -d "$region_hpath" ]; then
        log "Error: Region directory not found: ${region_hpath}"
        return 1
    fi
    
    # Find qlc-py collocated files in this region
    log "Searching for qlc-py collocated NetCDF files..."
    log "Pattern: qlc_D1_*_collocated_obs_*_mod_*.nc"
    
    collocated_files=($(find "${region_hpath}" -maxdepth 1 -type f -name "qlc_D1_*_collocated_obs_*_mod_*.nc" 2>/dev/null))
    
    if [ ${#collocated_files[@]} -eq 0 ]; then
        log "Warning: No collocated files found in ${region_hpath}"
        log "Skipping region ${region_name}"
        return 1
    fi
    
    log "Found ${#collocated_files[@]} collocated file(s):"
    for cfile in "${collocated_files[@]}"; do
        log "  - $(basename "$cfile")"
    done
    
    # Extract experiments and variables from NetCDF metadata
    if ! extract_experiments_and_variables_from_collocated_files "${region_hpath}"; then
        log "Error: Could not extract experiments and variables from NetCDF files"
        return 1
    fi
    
    # Create a temporary JSON config file for evaluator creation
    local temp_config_file="${region_hpath}/temp_qlc_E1_evaltools_config.json"
    rm -f "$temp_config_file"
    
    # Create experiments string for JSON (comma-separated)
    local experiments_json=$(IFS=,; echo "${discovered_experiments[*]}")
    
    log "Creating JSON configuration for ${region_name}: ${temp_config_file}"
    log "  Experiments: ${experiments_json}"
    log "  Variables: ${discovered_variables}"
    log "  Region: ${region_name}"
    
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
    "forecast_horizon": ${EVALTOOLS_FORECAST_HORIZON:-1},
    "availability_ratio": ${EVALTOOLS_AVAILABILITY_RATIO:-0.25}
  },
  "listing": {
    "listing_name": "stations_from_collocated.csv",
    "listing_dir": "${region_hpath}"
  },
  "input_output": {
    "plots_dir": "${region_hpath}",
    "output_dir": "${EVALUATOR_OUTPUT_DIR}",
    "temp_dir": "${EVALUATOR_OUTPUT_DIR}/temp",
    "output_file_pattern": "${EVALTOOLS_OUTPUT_PATTERN}"
  },
  "metadata": {
    "user": "$(echo $USER)",
    "host": "$(hostname -s)",
    "qlc_version": "${QLC_VERSION:-0.4.1}",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "command": "qlc_E1.sh ${experiments[*]} ${sDat} ${eDat}",
    "note": "Stations extracted from qlc_D1_*_collocated.csv files (actual collocated data)",
    "region": "${region_name}",
    "multi_region_mode": "${MULTI_REGION_MODE:-false}"
  }
}
EOM
    
    log "JSON configuration generated successfully"
    
    # Verify collocated CSV files exist
    collocated_csv_count=$(find "${region_hpath}" -name "*_collocated.csv" -type f 2>/dev/null | wc -l)
    if [ "$collocated_csv_count" -eq 0 ]; then
        log "Warning: No collocated CSV files found in ${region_hpath}"
        log "  Expected pattern: *_collocated.csv"
        log "  These files should be created by qlc_D1.sh"
        log "Converter will proceed but may need fallback station file"
    else
        log "  Found $collocated_csv_count collocated CSV file(s)"
    fi
    
    # Create log directory and file
    mkdir -p "${QLC_HOME}/log"
    local E1_LOG="${QLC_HOME}/log/qlc_E1_${region_name}_${experiments_hyphen}_${sDate}-${eDate}.log"
    
    # Run the converter
    log "Converting qlc-py collocation to evaltools evaluators..."
    log "Running: python $EVALTOOLS_SCRIPT --config $temp_config_file"
    log "Logging output to: $E1_LOG"
    
    if python "$EVALTOOLS_SCRIPT" --config "$temp_config_file" 2>&1 | tee "$E1_LOG"; then
        log "Successfully converted to evaltools evaluators for ${region_name}"
        log "  Output directory: ${EVALUATOR_OUTPUT_DIR}/"
        
        # List created evaluators for this region
        local created_count=0
        for exp in "${discovered_experiments[@]}"; do
            local exp_files=$(find "$EVALUATOR_OUTPUT_DIR" -name "${region_name}_${exp}_${sDate}-${eDate}_*.evaluator.evaltools" 2>/dev/null | wc -l)
            created_count=$((created_count + exp_files))
        done
        
        log "  Created: $created_count evaluator file(s) for ${region_name}"
        
        if [ $created_count -gt 0 ]; then
            log "  Example files:"
            for exp in "${discovered_experiments[@]}"; do
                find "$EVALUATOR_OUTPUT_DIR" -name "${region_name}_${exp}_${sDate}-${eDate}_*.evaluator.evaltools" 2>/dev/null | head -2 | while read f; do
                    log "    - $(basename "$f")"
                done
            done
        else
            log "  Warning: No evaluator files were created for ${region_name}"
        fi
    else
        log "Error converting to evaltools evaluators for ${region_name}"
        log "  Check log for details: $E1_LOG"
        log "  JSON config: $temp_config_file"
        log "  You can run the converter manually:"
        log "    conda activate evaltools"
        log "    python $EVALTOOLS_SCRIPT --config $temp_config_file --debug"
        return 1
    fi
    
    log "Completed processing region: ${region_name}"
    return 0
}

# Function to detect and process multi-region mode
process_multi_region() {
    log "Multi-region mode detection..."
    
    # Check if base directory exists
    if [ ! -d "$base_hpath" ]; then
        log "Error: Base plots directory not found: ${base_hpath}"
        log "Please ensure qlc_D1.sh has been run successfully."
        exit 1
    fi
    
    # Look for region subdirectories
    local region_dirs=()
    while IFS= read -r dir; do
        if [ -d "$dir" ]; then
            local region_name=$(basename "$dir")
            # Skip if it's a file or hidden directory
            if [[ ! "$region_name" =~ ^\. ]]; then
                region_dirs+=("$dir")
            fi
        fi
    done < <(find "${base_hpath}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    
    if [ ${#region_dirs[@]} -eq 0 ]; then
        log "No region subdirectories found - processing base directory"
        # Process base directory as single region (legacy mode)
        process_single_region "default" "${base_hpath}"
    else
        log "Found ${#region_dirs[@]} region subdirectories - multi-region mode active"
        
        # Process each region
        local success_count=0
        local fail_count=0
        
        for region_dir in "${region_dirs[@]}"; do
            local region_name=$(basename "$region_dir")
            
            if process_single_region "${region_name}" "${region_dir}"; then
                ((success_count++))
            else
                ((fail_count++))
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
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log "Starting evaluator generation..."
log "Base directory: ${base_hpath}"
log "Output directory: ${EVALUATOR_OUTPUT_DIR}"

# Process regions (auto-detects multi-region vs single-region)
process_multi_region

log "Ready for plotting with evaltools (qlc_E2.sh)"
log "Next step: qlc_E2.sh will use these evaluators to create evaltools plots"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
