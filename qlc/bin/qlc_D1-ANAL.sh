#!/bin/bash -e

# ============================================================================
# QLC D1-ANAL: Multi-Region Station Analysis with qlc-py
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Processes collocation and model-observation comparison plots for multiple
#   regions using the qlc-py Python package. Generates maps, time series,
#   scatter plots, and statistical metrics.
#
# Key Features:
#   - Multi-region processing (configurable via ACTIVE_REGIONS)
#   - Generates per-variable TeX files (e.g., texPlotfiles_qlc_D1-ANAL_EU_NH3.tex)
#   - Supports obs-only, mod-only, and collocation modes
#   - Processes plots in predefined order: map, burden, zonal, meridional, scatter, taylor
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

PLOTTYPE="python"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create Python plots for selected variables (multi-region mode)"
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

# Apply global CLI overrides (before region processing)
if [ -n "${QLC_CLI_EXP_PATH:-}" ]; then
    # Override experiment/model path globally
    ANALYSIS_DIRECTORY="${QLC_CLI_EXP_PATH/#\~/$HOME}"
    export ANALYSIS_DIRECTORY
    log "CLI override: mod_path (global) = ${ANALYSIS_DIRECTORY}"
fi

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
pwd -P

# Intelligent module loading with fallback to venv/conda
log "Setting up Python with intelligent module loading..."

# Setup Python
if ! setup_python; then
  log "Error: Failed to setup Python" >&2
  exit 1
fi

log "Success: Python configured"
log "PYTHON: $PYTHON_CMD"

# Setup eccodes for GRIB file reading (if USE_GRIB_SOURCE=true)
# Non-critical: setup_eccodes will warn but not fail if not found
if [ "${USE_GRIB_SOURCE:-false}" = "true" ]; then
  log "GRIB source enabled - checking for eccodes..."
  setup_eccodes || log "Warning: eccodes not found, but cfgrib may still work with system library" "WARN"
fi

# Clear PYTHONPATH to avoid conflicts with system Python libraries
# The Python interpreter knows where its own site-packages are, so we don't need to set PYTHONPATH
unset PYTHONPATH
log "Cleared PYTHONPATH to avoid library conflicts"

# Suppress HDF5 diagnostic messages (warnings about missing optional attributes)
export HDF5_USE_FILE_LOCKING=FALSE
export HDF5_DISABLE_VERSION_CHECK=2
# Suppress HDF5 error stack printing (these are harmless warnings about optional attributes)
# 0=no errors, 1=errors only, 2=errors+warnings (default is 2)
export H5E_DEBUG=0

# Check if qlc-py module exists
log "Checking for qlc module..."

# Temporarily disable exit-on-error to capture the import error
set +e
import_error=$("$PYTHON_CMD" -c "import qlc.cli.qlc_main" 2>&1)
import_status=$?
set -e

if [ $import_status -ne 0 ]; then
  log "Error: Failed to import qlc.cli.qlc_main" >&2
  log "Import error message:" >&2
  echo "$import_error" | while IFS= read -r line; do log "  $line" >&2; done
  log "" >&2
  log "Diagnostic information:" >&2
  log "  Python executable: $PYTHON_CMD" >&2
  log "  Python version: $("$PYTHON_CMD" --version 2>&1)" >&2
  log "  Python sys.path:" >&2
  "$PYTHON_CMD" -c "import sys; print('    ' + '\n    '.join(sys.path))" 2>&1 | while IFS= read -r line; do log "$line" >&2; done
  log "  Installed qlc packages:" >&2
  "$PYTHON_CMD" -m pip list 2>&1 | grep -i qlc | while IFS= read -r line; do log "    $line" >&2; done
  exit 1
else
  log "Success: qlc-py module found"
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
# Parse command line arguments: <exp1> [exp2 ... expN] <start_date> <end_date> [config]
# Experiments come first, followed by dates in YYYY-MM-DD format, optional config at end
# ----------------------------------------------------------------------------------------
parse_qlc_arguments "$@" || exit 1

# Check if we should skip this script entirely (Case 0)
# Skip if no experiments AND no observation dataset configured in any region
# Note: Individual regions will be checked later for obs_dataset_type
has_obs_configured=false
if [ ${#ACTIVE_REGIONS[@]} -gt 0 ]; then
    for region_code in "${ACTIVE_REGIONS[@]}"; do
        obs_dataset_var="REGION_${region_code}_OBS_DATASET_TYPE"
        if [ -n "${!obs_dataset_var:-}" ]; then
            has_obs_configured=true
            break
        fi
    done
else
    # Auto-detect regions with obs configured
    for region_var in $(compgen -A variable | grep '^REGION_.*_OBS_DATASET_TYPE$'); do
        if [ -n "${!region_var:-}" ]; then
            has_obs_configured=true
            break
        fi
    done
fi

# Case 0: Skip if no experiments and no observations configured
if [ ${#experiments[@]} -eq 0 ] && [ "$has_obs_configured" = false ]; then
    log "No experiments and no observations configured - skipping D1-ANAL (nothing to process)"
    log "End ${SCRIPT} at `date`"
    log "________________________________________________________________________________________"
    exit 0
fi

# Determine processing mode based on experiments and observations
if [ ${#experiments[@]} -eq 0 ]; then
    log "Processing mode: Obs-only (no experiments specified)"
    PROCESSING_MODE="obs_only"
else
    log "Processing mode: Model with collocation (experiments: ${experiments[*]})"
    PROCESSING_MODE="model_with_collocation"
fi

# Generic experiment handling: last experiment is the reference (only if experiments exist)
num_experiments=${#experiments[@]}
if [ $num_experiments -gt 0 ]; then
    # Last experiment is the reference for difference plots
    ref_exp="${experiments[$((num_experiments-1))]}"
    log "Reference experiment (for diff plots): $ref_exp"
else
    ref_exp=""
    log "No experiments - obs-only mode"
fi

# Parse EXP_LABELS if defined (comma-separated list matching experiments order)
# Otherwise use experiments array for labels
if [ -n "${EXP_LABELS:-}" ]; then
    IFS=',' read -ra exp_labels_array <<< "${EXP_LABELS}"
    # Trim whitespace from each label
    for i in "${!exp_labels_array[@]}"; do
        exp_labels_array[$i]=$(echo "${exp_labels_array[$i]}" | xargs)
    done
    # Ensure we have enough labels (pad with experiment names if needed)
    while [ ${#exp_labels_array[@]} -lt ${#experiments[@]} ]; do
        exp_labels_array+=("${experiments[${#exp_labels_array[@]}]}")
    done
    log "Using EXP_LABELS: ${exp_labels_array[*]}"
else
    # Use experiments array as labels
    exp_labels_array=("${experiments[@]}")
    log "Using experiments as labels: ${exp_labels_array[*]}"
fi

# Create experiment strings for different uses
# Note: experiments array has "None" placeholders already filtered out by parse_qlc_arguments

# Use experiments_dirname set by parse_qlc_arguments (preserves "None" placeholders)
# This variable was exported by parse_qlc_arguments in common_functions
experiments_hyphen="${experiments_dirname:-None}"

# For JSON, use the filtered experiments array (without "None")
experiments_comma=$(IFS=,; echo "${experiments[*]}")
if [ ${#experiments[@]} -eq 0 ]; then
    experiments_comma=""  # Empty string for JSON when no actual experiments
fi

log "Directory name will use: ${experiments_hyphen}"
log "JSON will use experiments: ${experiments_comma:-"(none)"}"

# Note: exp1 and expN are already set by parse_qlc_arguments in common_functions
# exp1 = first experiment (or empty if no experiments)
# expN = reference experiment (last) for diff plots (or empty if only one experiment or no experiments)

# Process dates
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# Parse plot format(s) from SAVE_PLOT_FORMAT (can be comma-separated: "pdf,png")
if [ -n "$SAVE_PLOT_FORMAT" ]; then
    # Convert comma-separated list to array for iteration
    IFS=',' read -ra PLOT_FORMATS <<< "$SAVE_PLOT_FORMAT"
    # Trim whitespace from each format
    for i in "${!PLOT_FORMATS[@]}"; do
        PLOT_FORMATS[$i]=$(echo "${PLOT_FORMATS[$i]}" | xargs)
    done
else
    PLOT_FORMATS=("png")  # Default to pdf
fi
log "Plot formats configured: ${PLOT_FORMATS[*]}"

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
        log "Using region-specific MARS_RETRIEVALS for ${region_code}: ${region_retrievals[*]}" >&2
        echo "${region_retrievals[@]}"
    else
        # Use global default
        log "Using global MARS_RETRIEVALS for ${region_code}: ${MARS_RETRIEVALS[*]}" >&2
        echo "${MARS_RETRIEVALS[@]}"
    fi
}

# Function to discover available variables from file names
# Naming convention: {exp}_{dates}_{levtype}_{myvar}.nc or {exp}_{dates}_{levtype}_{myvar}_tavg.nc
# Variables are named as {levtype}_{myvar} to match MARS_RETRIEVALS format
# Note: D1-ANAL uses full time-resolved files (not just _tavg.nc) for collocation and map plots
discover_available_variables() {
    local mars_retrievals=("$@")
    log "Discovering variables from NetCDF files..."
    available_vars=()
    
    # Use file-based discovery with naming convention matching qlc_C1-GLOB.sh
    # Pattern: {exp}_{dates}_{levtype}_{myvar}.nc or {exp}_{dates}_{levtype}_{myvar}_tavg.nc
    # We want to extract unique {levtype}_{myvar} values
    # Unlike C1-GLOB, we include all .nc files (not just _tavg.nc) for time series analysis
    if [ -d "${ANALYSIS_DIRECTORY}/${exp1}" ]; then
        log "Scanning directory: ${ANALYSIS_DIRECTORY}/${exp1}"
        
        # Find all .nc files, extract variable names (exclude _tavg.nc for discovery to avoid duplicates)
        while IFS= read -r file; do
            if [ -n "$file" ]; then
                # Extract basename without .nc extension
                filename=$(basename "$file" .nc)
                
                # Skip _tavg files for discovery (we'll use the base time-resolved files)
                if [[ "$filename" == *"_tavg" ]]; then
                    continue
                fi
                
                # Pattern: {exp}_{dates}_{levtype}_{myvar}
                # Remove exp prefix (everything up to and including date pattern)
                # This regex removes: exp_YYYYMMDD-YYYYMMDD_
                var_info=$(echo "$filename" | sed -E 's/^[^_]+_[0-9]{8}-[0-9]{8}_//')
                
                # Extract levtype (first component)
                levtype="${var_info%%_*}"
                # Extract myvar (everything after first underscore)
                myvar="${var_info#${levtype}_}"
                
                # Build variable name as levtype_myvar (matches MARS_RETRIEVALS format)
                if [ -n "$levtype" ] && [ -n "$myvar" ]; then
                    varname="${levtype}_${myvar}"
                    available_vars+=("$varname")
                fi
            fi
        done < <(find "${ANALYSIS_DIRECTORY}/${exp1}" -type f -name "*.nc" -print0 | xargs -0 -n 1 echo)
        
        # De-duplicate and sort
        available_vars=($(printf "%s\n" "${available_vars[@]}" | sort -u))
    else
        log "Warning: Directory not found: ${ANALYSIS_DIRECTORY}/${exp1}"
    fi
    
    if [ ${#available_vars[@]} -eq 0 ]; then
        log "Warning: Could not find any variables in ${ANALYSIS_DIRECTORY}/${exp1}"
        log "Expected file pattern: {exp}_{dates}_{levtype}_{myvar}.nc"
    else
        log "Discovered variables: ${available_vars[*]}"
    fi
    
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
    
    # Apply command-line overrides (highest priority)
    # These override workflow configuration settings
    if [ -n "${QLC_CLI_OBS_PATH:-}" ]; then
        CURRENT_REGION_OBS_PATH="${QLC_CLI_OBS_PATH}"
        log "CLI override: obs_path = ${CURRENT_REGION_OBS_PATH}"
    fi
    
    if [ -n "${QLC_CLI_OBSERVATION:-}" ]; then
        CURRENT_REGION_OBS_DATASET_TYPE="${QLC_CLI_OBSERVATION}"
        log "CLI override: obs_dataset_type = ${CURRENT_REGION_OBS_DATASET_TYPE}"
    fi
    
    if [ -n "${QLC_CLI_STATION_SELECTION:-}" ]; then
        # Expand tilde in path
        CURRENT_REGION_STATION_FILE="${QLC_CLI_STATION_SELECTION/#\~/$HOME}"
        log "CLI override: station_file = ${CURRENT_REGION_STATION_FILE}"
    fi
    
    # Set default obs_dataset_version to 'latest' if not specified
    if [ -z "${CURRENT_REGION_OBS_DATASET_VERSION}" ]; then
        CURRENT_REGION_OBS_DATASET_VERSION="latest"
    fi
    
    # Variable selection priority:
    # 1. REGION_*_VARIABLES (if set in config)
    # 2. MARS_RETRIEVALS (if REGION_*_VARIABLES not set)
    # 3. Discover from files (if neither is set)
    if [ -z "$CURRENT_REGION_VARIABLES" ]; then
        # Get region-specific MARS_RETRIEVALS or use global
        local region_mars_retrievals=($(get_region_mars_retrievals "${region_code}"))
        
        if [ ${#region_mars_retrievals[@]} -gt 0 ]; then
            # Use MARS_RETRIEVALS (expand groups like @AIFS_SFC)
            available_vars=()
            for spec in "${region_mars_retrievals[@]}"; do
                while IFS= read -r var; do
                    available_vars+=("$var")
                done < <(expand_variable_spec "$spec")
            done
            CURRENT_REGION_VARIABLES=$(IFS=,; echo "${available_vars[*]}")
            log "Loaded configuration for region: ${CURRENT_REGION_NAME}"
            log "  OBS_PATH: ${CURRENT_REGION_OBS_PATH}"
            log "  OBS_DATASET_TYPE: ${CURRENT_REGION_OBS_DATASET_TYPE}"
            log "  STATION_FILE: ${CURRENT_REGION_STATION_FILE}"
            log "  PLOT_REGION: ${CURRENT_REGION_PLOT_REGION}"
            log "  REQUESTED_VARIABLES: ${CURRENT_REGION_VARIABLES} (from MARS_RETRIEVALS)"
            log "  STATION_RADIUS_DEG: ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG} (global default)}"
        else
            # No MARS_RETRIEVALS either, discover from files (fallback)
            discover_available_variables "${region_mars_retrievals[@]}" || true
            
            if [ ${#available_vars[@]} -gt 0 ]; then
                CURRENT_REGION_VARIABLES=$(IFS=,; echo "${available_vars[*]}")
                log "Loaded configuration for region: ${CURRENT_REGION_NAME}"
                log "  OBS_PATH: ${CURRENT_REGION_OBS_PATH}"
                log "  OBS_DATASET_TYPE: ${CURRENT_REGION_OBS_DATASET_TYPE}"
                log "  STATION_FILE: ${CURRENT_REGION_STATION_FILE}"
                log "  PLOT_REGION: ${CURRENT_REGION_PLOT_REGION}"
                log "  REQUESTED_VARIABLES: ${CURRENT_REGION_VARIABLES} (discovered from files)"
                log "  STATION_RADIUS_DEG: ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG} (global default)}"
            else
                log "Warning: No variables found in config, MARS_RETRIEVALS, or files for region ${CURRENT_REGION_NAME}"
                log "Loaded configuration for region: ${CURRENT_REGION_NAME}"
                log "  OBS_PATH: ${CURRENT_REGION_OBS_PATH}"
                log "  OBS_DATASET_TYPE: ${CURRENT_REGION_OBS_DATASET_TYPE}"
                log "  STATION_FILE: ${CURRENT_REGION_STATION_FILE}"
                log "  PLOT_REGION: ${CURRENT_REGION_PLOT_REGION}"
                log "  REQUESTED_VARIABLES: (none - no variables available)"
                log "  STATION_RADIUS_DEG: ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG} (global default)}"
            fi
        fi
    else
        # REGION_VARIABLES is set - populate available_vars for validation
        # Check against MARS_RETRIEVALS if available, otherwise discover from files
        local region_mars_retrievals=($(get_region_mars_retrievals "${region_code}"))
        
        if [ ${#region_mars_retrievals[@]} -gt 0 ]; then
            # Use MARS_RETRIEVALS for validation (expand groups like @AIFS_SFC)
            available_vars=()
            for spec in "${region_mars_retrievals[@]}"; do
                while IFS= read -r var; do
                    available_vars+=("$var")
                done < <(expand_variable_spec "$spec")
            done
        else
            # Discover from files for validation
            discover_available_variables "${region_mars_retrievals[@]}" || true
            # available_vars is populated by discover_available_variables
        fi
        
        log "Loaded configuration for region: ${CURRENT_REGION_NAME}"
        log "  OBS_PATH: ${CURRENT_REGION_OBS_PATH}"
        log "  OBS_DATASET_TYPE: ${CURRENT_REGION_OBS_DATASET_TYPE}"
        log "  STATION_FILE: ${CURRENT_REGION_STATION_FILE}"
        log "  PLOT_REGION: ${CURRENT_REGION_PLOT_REGION}"
        log "  REQUESTED_VARIABLES: ${CURRENT_REGION_VARIABLES} (from config)"
        log "  STATION_RADIUS_DEG: ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG} (global default)}"
    fi
    
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
# Also extracts just the variable names (without levtype prefix) for qlc-py
filter_region_variables() {
    # Split requested variables by comma
    IFS=',' read -ra region_vars <<< "$CURRENT_REGION_VARIABLES"
    
    # Filter to only include available variables
    local filtered_vars=()
    local filtered_vars_only=()  # Just variable names without levtype
    local missing_vars=()
    
    for rv in "${region_vars[@]}"; do
        # Trim whitespace
        rv=$(echo "$rv" | xargs)
        
        if [[ " ${available_vars[*]} " =~ " ${rv} " ]]; then
            filtered_vars+=("$rv")
            # Extract just the variable name (everything after first underscore)
            # e.g., "sfc_NH4_as" -> "NH4_as", "pl_NH3" -> "NH3"
            local levtype="${rv%%_*}"
            local varname="${rv#${levtype}_}"
            filtered_vars_only+=("$varname")
        else
            missing_vars+=("$rv")
        fi
    done
    
    # Report results
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log "Warning: Variables requested for ${CURRENT_REGION_NAME} but not available (will be skipped):"
        log "  Missing: ${missing_vars[*]}"
        if [ ${#available_vars[@]} -gt 0 ]; then
            log "  Available: ${available_vars[*]}"
        fi
    fi
    
    if [ ${#filtered_vars[@]} -eq 0 ]; then
        log "Error: No valid variables found for region ${CURRENT_REGION_NAME}"
        log "  Requested: ${CURRENT_REGION_VARIABLES}"
        log "  Available: ${available_vars[*]}"
        return 1
    fi
    
    # Store filtered variables (full format for logging)
    CURRENT_REGION_VARIABLES_FILTERED=$(IFS=,; echo "${filtered_vars[*]}")
    CURRENT_REGION_VARIABLES_ARRAY=("${filtered_vars[@]}")
    
    # Store variable names only (for qlc-py JSON, without levtype prefix)
    CURRENT_REGION_VARIABLES_FOR_JSON=$(IFS=,; echo "${filtered_vars_only[*]}")
    
    log "Variables to process for ${CURRENT_REGION_NAME}: ${CURRENT_REGION_VARIABLES_FILTERED}"
    log "Variable names for qlc-py: ${CURRENT_REGION_VARIABLES_FOR_JSON}"
    return 0
}

# Function to generate region-specific JSON configuration
generate_region_json() {
    local region_hpath="${base_hpath}/${CURRENT_REGION_NAME}"
    mkdir -p "$region_hpath"
    
    local temp_config_file="${region_hpath}/${QLTYPE}_config.json"
#   local temp_config_file="${region_hpath}/temp_${QLTYPE}_config.json"
    
    # Clean up old temporary config file
    rm -f "$temp_config_file"
    
    log "Generating JSON configuration for ${CURRENT_REGION_NAME}: ${temp_config_file}"
    
    # Determine what configurations to generate based on availability
    local has_obs=false
    local has_experiments=false
    
    if [ -n "${CURRENT_REGION_OBS_DATASET_TYPE:-}" ]; then
        has_obs=true
    fi
    
    if [ ${#experiments[@]} -gt 0 ]; then
        has_experiments=true
    fi
    
    # Set explicit use_* flags for data processing control
    # These control what data is loaded and processed (independent of visualization)
    local use_obs="false"
    local use_mod="false"
    local use_com="false"
    
    # Check for mode flags from command line (highest priority)
    # These override all other settings
    if [ -n "${QLC_MODE_OBS_ONLY:-}" ]; then
        # Force observation-only mode
        use_obs="true"
        use_mod="false"
        use_com="false"
        log "Forced mode: Observation-only (--obs-only flag)"
    elif [ -n "${QLC_MODE_MOD_ONLY:-}" ]; then
        # Force model-only mode
        use_obs="false"
        use_mod="true"
        use_com="false"
        log "Forced mode: Model-only (--mod-only flag)"
    else
        # Normal mode: determine from available data
        if [ "$has_obs" = true ]; then
            use_obs="true"
        fi
        
        if [ "$has_experiments" = true ]; then
            use_mod="true"
        fi
        
        # use_com (collocation) requires BOTH obs and mod
        if [ "$use_obs" = "true" ] && [ "$use_mod" = "true" ]; then
            use_com="true"
        fi
    fi
    
    # Set show_station_timeseries_* flags from config (default: false)
    # These control visualization only (separate from data processing)
    # Can be overridden via workflow config: SHOW_STATION_TIMESERIES_OBS, etc.
    local show_obs_flag="${SHOW_STATION_TIMESERIES_OBS:-false}"
    local show_mod_flag="${SHOW_STATION_TIMESERIES_MOD:-false}"
    local show_com_flag="${SHOW_STATION_TIMESERIES_COM:-false}"
    
    # Log the determined mode and set summary text for this region
    if [ "$use_obs" = "true" ] && [ "$use_mod" = "false" ]; then
        log "Region ${CURRENT_REGION_NAME}: Obs-only mode (use_obs=true, use_mod=false, use_com=false)"
        global_summary="netCDF output: ${CURRENT_REGION_OBS_DATASET_TYPE:-""} observations for selected stations."
    elif [ "$use_mod" = "true" ] && [ "$use_obs" = "false" ]; then
        log "Region ${CURRENT_REGION_NAME}: Model-only mode (use_obs=false, use_mod=true, use_com=false)"
        global_summary="netCDF output: Model data for ${experiments_comma} for selected stations."
    elif [ "$use_obs" = "true" ] && [ "$use_mod" = "true" ]; then
        log "Region ${CURRENT_REGION_NAME}: Collocation mode (use_obs=true, use_mod=true, use_com=true)"
        global_summary="netCDF output: Collocated model and observation data for selected stations."
    else
        # Case 0: Nothing to process (should not reach here due to earlier check)
        log "Warning: Region ${CURRENT_REGION_NAME} has no experiments and no observations - skipping"
        return 1
    fi
    
    # Determine mod_path based on USE_GRIB_SOURCE setting
    # If USE_GRIB_SOURCE=true: use Results directory (contains .grb files)
    # If USE_GRIB_SOURCE=false: use Analysis directory (contains .nc files from B1-CONV)
    local mod_path_to_use
    if [ "${USE_GRIB_SOURCE:-false}" = "true" ]; then
        mod_path_to_use="${MARS_RETRIEVAL_DIRECTORY:-""}"
        log "Using GRIB source: mod_path = ${mod_path_to_use}"
        log "  Reading .grb files directly (preserves forecast step dimension)"
        log "  Requires: cfgrib package and eccodes library"
    else
        mod_path_to_use="${ANALYSIS_DIRECTORY:-""}"
        log "Using NetCDF source: mod_path = ${mod_path_to_use}"
        log "  Reading .nc files from B1-CONV conversion"
    fi
    
    # Generate JSON configuration with explicit use_* flags
    # use_obs, use_mod, use_com: Control data loading/processing (independent of visualization)
    # show_station_timeseries_*: Control visualization only
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
    "mod_path": "${mod_path_to_use}",
    "model": "${MODEL:-""}",
    "experiments": "${experiments_comma}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${CURRENT_REGION_VARIABLES_FOR_JSON}",
    "plot_region": "${CURRENT_REGION_PLOT_REGION:-""}",
    "station_radius_deg": ${CURRENT_REGION_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG:-0.5}},
    "use_uniform_time_grid": ${USE_UNIFORM_TIME_GRID:-false},
    "spatial_interp_method": "${SPATIAL_INTERP_METHOD:-nearest}",
    "temporal_interp_method": "${TEMPORAL_INTERP_METHOD:-}",
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_network": "${STATION_NETWORK:-""}",
    "station_suffix": "${STATION_SUFFIX:-""}",
    "station_type": "${STATION_TYPE:-concentration}",
    "plot_mode": "${PLOT_MODE:-grouped}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": ${SHOW_STATIONS:-false},
    "show_min_max": ${SHOW_MIN_MAX:-true},
    "log_y_axis": ${LOG_Y_AXIS:-false},
    "fix_y_axis": ${FIX_Y_AXIS:-true},
    "force_full_year": ${FORCE_FULL_YEAR:-true},
    "show_station_map": ${SHOW_STATION_MAP:-false},
    "use_obs": ${use_obs},
    "use_mod": ${use_mod},
    "use_com": ${use_com},
    "load_station_timeseries_obs": ${use_obs},
    "show_station_timeseries_obs": ${show_obs_flag},
    "show_station_timeseries_mod": ${show_mod_flag},
    "show_station_timeseries_com": ${show_com_flag},
    "unit_to": "${UNIT_TO:-}",
    "save_plot_format": "${SAVE_PLOT_FORMAT:-pdf}",
    "save_data_format": "${SAVE_DATA_FORMAT:-nc}",
    "read_data_format": "${READ_DATA_FORMAT:-nc}",
    "lazy_load_nc": ${LAZY_LOAD_NC:-true},
    "map_colormap": "${MAP_COLORMAP:-turbo}",
    "map_colormap_diff": "${MAP_COLORMAP_DIFF:-RdBu_r}",
    "enable_diff_plots": ${ENABLE_DIFF_PLOTS:-true},
    "use_log_scale": ${USE_LOG_SCALE:-true},
    "use_normalized_scale": ${USE_NORMALIZED_SCALE:-true},
    "map_show_stats": ${MAP_SHOW_STATS:-true},
    "map_projection": "${MAP_PROJECTION:-PlateCarree}",
    "publication_style": ${PUBLICATION_STYLE:-true},
    "plot_dpi": ${PLOT_DPI:-null},
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": "${N_THREADS:-1}",
    "debug": ${DEBUG:-false},
    "debug_extended": ${DEBUG_EXTENDED:-false},
    "global_attributes": {
      "title": "Air pollutants over ${CURRENT_REGION_PLOT_REGION:-""}, ${CURRENT_REGION_VARIABLES_FOR_JSON}",
      "summary": "${global_summary}",
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
    
    return 0
}

# Function to execute qlc-py for a region
execute_qlc_py_for_region() {
    log "Executing qlc-py for region ${CURRENT_REGION_NAME}..."
    log "Config file: ${CURRENT_REGION_CONFIG_FILE}"
    
    # CRITICAL: Set Cartopy data directory BEFORE Python starts
    # This ensures Cartopy uses venv data, not ~/.local/share/cartopy
    export CARTOPY_DATA_DIR="${VIRTUAL_ENV}/share/cartopy"
    export CARTOPY_OFFLINE_MODE="1"
    export CARTOPY_USER_BACKGROUNDS="false"
    
    # Execute qlc-py using configured Python interpreter
    # Note: HDF5-DIAG warnings about missing optional attributes are harmless
    "$PYTHON_CMD" -m qlc.cli.qlc_main --config "${CURRENT_REGION_CONFIG_FILE}"
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log "Error: qlc-py execution failed for region ${CURRENT_REGION_NAME} with exit code ${exit_code}"
        return 1
    fi
    
    log "qlc-py execution completed successfully for ${CURRENT_REGION_NAME}"
    return 0
}

# Function to generate TeX file for region (per-variable and combined)
generate_region_tex() {
    log "Generating TeX files for region ${CURRENT_REGION_NAME}..."
    
    local tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
    local tREGION=$(echo "${CURRENT_REGION_NAME}" | sed 's/_/\\_/g')
    
    # Use only the first plot format for TeX files
    local tex_plot_format="${PLOT_FORMATS[0]}"
    log "Using plot format for TeX: ${tex_plot_format}"
    
    # Arrays to store per-variable tex files for later combination
    local per_variable_tex_files=()
    
    # Helper function to find and add plots for a specific format
    add_plot_if_found() {
        local plot_pattern=$1
        local target_list=$2
        find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f -name "${plot_pattern}" 2>/dev/null | sort | while IFS= read -r plot_file; do
            if [ -n "$plot_file" ] && ! grep -qF "$plot_file" "${target_list}"; then
                echo "$plot_file" >> "${target_list}"
                log "Added plot to TeX list: $plot_file"
            fi
        done
    }
    
    # Helper function to generate TeX frames for a plot list
    generate_tex_frames() {
        local plot_list_file=$1
        local output_tex_file=$2
        local var_name_for_title=$3
        
        if [ -s "${plot_list_file}" ]; then
            while IFS= read -r plot_path; do
                plot_filename=$(basename -- "$plot_path")
                var_name_tex=$(format_var_name_tex "$var_name_for_title")
                title_prefix=""
                
                # Determine title prefix based on plot type
                case "$plot_filename" in
                    *_Station_*)
                        # Extract station ID from filename if possible
                        station_id=$(echo "$plot_filename" | grep -oP '_Station_\K[^_]+' || echo "")
                        if [ -n "$station_id" ]; then
                            title_prefix="Station time series: ${station_id}"
                        else
                            title_prefix="Station time series"
                        fi
                        ;;
                    *regional_bias*)
                        title_prefix="Collocation time series bias" ;;
                    *regional_mean*)
                        title_prefix="Collocation time series" ;;
                    *scatter*)
                        title_prefix="Collocation scatter plot" ;;
                    *taylor*)
                        title_prefix="Collocation Taylor diagram" ;;
                    *stats_plot_Error_Metrics*)
                        title_prefix="Collocation error metrics" ;;
                    *stats_plot_Correlation_Metrics*)
                        title_prefix="Collocation correlation metrics" ;;
                    *stats_plot_Descriptive_Statistics*)
                        title_prefix="Collocation descriptive statistics" ;;
                    *_map_*)
                        # Distinguish between _collocated_ and _mod_diff_
                        if [[ "$plot_filename" == *"_mod_diff_"* ]]; then
                            title_prefix="Model difference spatial map"
                        else
                            title_prefix="Collocation spatial map"
                        fi
                        ;;
                    *burden*)
                        if [[ "$plot_filename" == *"_mod_diff_"* ]]; then
                            title_prefix="Model difference column burden"
                        else
                            title_prefix="Collocation column burden"
                        fi
                        ;;
                    *zonal*)
                        if [[ "$plot_filename" == *"_mod_diff_"* ]]; then
                            title_prefix="Model difference zonal mean"
                        else
                            title_prefix="Collocation zonal mean"
                        fi
                        ;;
                    *meridional*)
                        if [[ "$plot_filename" == *"_mod_diff_"* ]]; then
                            title_prefix="Model difference meridional mean"
                        else
                            title_prefix="Collocation meridional mean"
                        fi
                        ;;
                    *)
                        title_prefix="Collocation plot" ;;
                esac
                
                # Build experiment list for title
                exp_labels_array=""
                for i in "${!experiments[@]}"; do
                    exp_escaped=$(echo "${experiments[$i]}" | sed 's/_/\\_/g')
                    if [ $i -eq 0 ]; then
                        exp_labels_array="$exp_escaped"
                    elif [ $i -eq $((${#experiments[@]} - 1)) ]; then
                        exp_labels_array="${exp_labels_array} vs ${exp_escaped}"
                    else
                        exp_labels_array="${exp_labels_array}, ${exp_escaped}"
                    fi
                done
                
#               title_final="${title_prefix} for ${var_name_tex} of ${exp_labels_array}"
                title_final="${title_prefix} of ${exp_labels_array}"
#               title_final="${title_prefix} of ${exp_labels_array} (${tREGION})"
                
                # Determine image width based on plot type
                # Scatter and taylor plots need smaller width to fit in TeX window
                local image_width="0.95"
                if [[ "$plot_filename" =~ (taylor) ]]; then
                    image_width="${D1_TEX_SCATTER_TAYLOR_WIDTH:-0.7}"
                fi
                if [[ "$plot_filename" =~ (scatter) ]]; then
                    image_width="${D1_TEX_SCATTER_TAYLOR_WIDTH:-0.6}"
                fi
                
                # Append frame to TeX file
                cat >> "${output_tex_file}" <<EOF
%===============================================================================
\frame{
%\frametitle{${title_final}}
\vspace{0mm}
\centering
\includegraphics[width=${image_width}\textwidth]{${plot_path}}
}
EOF


                log "Generated TeX frame for $plot_filename"
            done < "${plot_list_file}"
        fi
    }
    
    # Loop through each variable to create per-variable TeX files
    for var_full in "${CURRENT_REGION_VARIABLES_ARRAY[@]}"; do
        # Extract just the variable name (without levtype prefix)
        local levtype="${var_full%%_*}"
        local varname="${var_full#${levtype}_}"
        
        log "Processing variable: ${varname} for region ${CURRENT_REGION_NAME}"
        
        # Create per-variable tex and list files in base directory
        local var_texfile="${base_hpath}/texPlotfiles_${QLTYPE}_${CURRENT_REGION_NAME}_${varname}.tex"
        local var_plotlist="${base_hpath}/texPlotfiles_${QLTYPE}_${CURRENT_REGION_NAME}_${varname}.list"
        
        rm -f "${var_plotlist}" "${var_texfile}"
        touch "${var_plotlist}"
        
        # Add ALL plots of the first format in predefined order
        # Predefined order: map, burden, zonal, meridional, scatter, taylor
        # Use only first plot format for TeX files
        # Include only plots matching specific patterns:
        #   ${QLTYPE}_${MODEL}_${CURRENT_REGION_NAME}_*_collocated_*.${tex_plot_format}
        #   ${QLTYPE}_${MODEL}_${CURRENT_REGION_NAME}_*_mod_diff_*.${tex_plot_format}
        #   ${QLTYPE}_${MODEL}_${CURRENT_REGION_NAME}_*_mod_<exp>_*.${tex_plot_format} (for each experiment)
        #   ${QLTYPE}_${OBS_DATASET_TYPE}_${CURRENT_REGION_NAME}_*_map.${tex_plot_format}
        log "  Processing all ${tex_plot_format} plots for variable ${varname}"
        
        # Build base prefix patterns
        # Python uses region + station_suffix, not CURRENT_REGION_NAME
        # Pattern: {QLTYPE}_{MODEL}_*_stations_ to match Python output
        local model_prefix="${QLTYPE}_${MODEL}_"
        local obs_prefix="${QLTYPE}_${CURRENT_REGION_OBS_DATASET_TYPE}_"
        
        # Helper function to add plots for a specific plot type
        add_plots_by_type() {
            local plot_type=$1
            # Model-based plots: collocated, mod_diff, and mod_<exp> for each experiment
            add_plot_if_found "${model_prefix}*${varname}*_collocated_*${plot_type}*.${tex_plot_format}" "${var_plotlist}"
            add_plot_if_found "${model_prefix}*${varname}*_mod_diff_*${plot_type}*.${tex_plot_format}" "${var_plotlist}"
            # Add mod_<exp> pattern for each experiment dynamically
            for exp in "${experiments[@]}"; do
                add_plot_if_found "${model_prefix}*${varname}*_mod_${exp}_*${plot_type}*.${tex_plot_format}" "${var_plotlist}"
            done
        }
        
        # 1. MAP plots
        add_plots_by_type "map"
        # Obs-only plots (specific pattern: ends with _map.pdf)
        add_plot_if_found "${obs_prefix}*${varname}*_map.${tex_plot_format}" "${var_plotlist}"
        
        # 2. BURDEN plots (model-based only)
        add_plots_by_type "burden"
        
        # 3. ZONAL plots (model-based only)
        add_plots_by_type "zonal"
        
        # 4. MERIDIONAL plots (model-based only)
        add_plots_by_type "meridional"
        
        # 5. SCATTER plots (model-based only)
        add_plots_by_type "scatter"
        
        # 6. TAYLOR plots (model-based only)
        add_plots_by_type "taylor"
        
        # 7. Station location maps and averages (filtered by variable name)
        # Pattern: qlc_D1-ANAL_AIFS-COMPO_US_Airnow_stations-test_NH3_..._avg_mod_b2ro_map.png
        # Pattern: qlc_D1-ANAL_US_Airnow_stations-test.png (no variable, include for all)
        # Filter by variable name to avoid mixing variables
        add_plot_if_found "${QLTYPE}_${MODEL}_*stations-*${varname}*.${tex_plot_format}" "${var_plotlist}"
        add_plot_if_found "${QLTYPE}_${CURRENT_REGION_OBS_DATASET_TYPE}_*stations-*${varname}*.${tex_plot_format}" "${var_plotlist}"
        # Add generic station location map (no variable in filename) if exists
        add_plot_if_found "${QLTYPE}_${MODEL}_*stations-test.${tex_plot_format}" "${var_plotlist}"
        add_plot_if_found "${QLTYPE}_${CURRENT_REGION_OBS_DATASET_TYPE}_*stations-test.${tex_plot_format}" "${var_plotlist}"
        
        # 8. Collocation overview plots (general collocation time series without specific keywords)
        # Pattern: ..._O3_..._3hourly_collocated_obs_mod_9191.png
        # These are general collocation visualizations (not scatter/taylor/stats)
        # Exclude files with: _map, _scatter, _taylor, _stats_plot, _bias, _minmax, _surface_
        for exp in "${experiments[@]}"; do
            while IFS= read -r plot_file; do
                local basename_plot=$(basename "$plot_file")
                # Only add if it doesn't contain specific plot type keywords
                if [[ ! "$basename_plot" =~ (_map|_scatter|_taylor|_stats_plot|_bias|_minmax|_surface_|_regional_) ]]; then
                    if ! grep -qF "$plot_file" "${var_plotlist}"; then
                        echo "$plot_file" >> "${var_plotlist}"
                        log "Added collocation overview plot: $(basename "$plot_file")"
                    fi
                fi
            done < <(find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f -name "${model_prefix}*${varname}*_collocated_obs_mod_${exp}.${tex_plot_format}" 2>/dev/null | sort)
        done
        
        # 9. Regional time series and statistics (in order of preference)
        # a) Collocated regional time series (model vs obs comparison)
        add_plot_if_found "${model_prefix}*${varname}*_collocated_*regional_mean*.${tex_plot_format}" "${var_plotlist}"
        add_plot_if_found "${model_prefix}*${varname}*_collocated_*regional_bias*.${tex_plot_format}" "${var_plotlist}"
        
        # b) Collocated statistics plots (correlation, descriptive, error metrics)
        add_plot_if_found "${model_prefix}*${varname}*_collocated_*stats_plot*.${tex_plot_format}" "${var_plotlist}"
        
        # c) Model-only regional time series (for each experiment)
        for exp in "${experiments[@]}"; do
            add_plot_if_found "${model_prefix}*${varname}*_mod_${exp}_regional_mean*.${tex_plot_format}" "${var_plotlist}"
        done
        
        # d) Obs-only regional time series
        add_plot_if_found "${obs_prefix}*${varname}*regional_mean*.${tex_plot_format}" "${var_plotlist}"
        
        # 10. Individual STATION time series plots - ALWAYS LAST
        # Find all individual station plots (with station names in filename)
        # Pattern: ..._Las_Vegas_bias.png or ..._Los_Angeles_minmax_yfixed.png
        # Sort alphabetically and limit to first 10 stations (2 plots per station = 20 plots max)
        local station_pattern_bias="${model_prefix}*${varname}*_collocated_*_bias.${tex_plot_format}"
        local station_pattern_minmax="${model_prefix}*${varname}*_collocated_*_minmax*.${tex_plot_format}"
        local max_stations=10  # Limit to first 10 stations (bias + minmax per station)
        
        # Get unique station names from bias plots, sort alphabetically
        # Pattern: ..._collocated_obs_mod_9191_Las_Vegas_bias.png
        # Extract: Las_Vegas (between last exp ID and _bias)
        declare -a station_names=()
        while IFS= read -r station_bias_plot; do
            if [ -n "$station_bias_plot" ]; then
                local basename_plot=$(basename "$station_bias_plot")
                # Extract station name: everything between last digit (exp ID) and _bias
                # Example: ...9191_Las_Vegas_bias.png -> Las_Vegas
                local station_name=$(echo "$basename_plot" | sed -E 's/.*[0-9]_([^_]+(_[^_]+)*)_bias\..*/\1/')
                
                # Validate extraction (should contain at least one character)
                if [[ -n "$station_name" ]] && [[ "$station_name" != "$basename_plot" ]]; then
                    # Add to array if not already present and under limit
                    if [[ ! " ${station_names[@]} " =~ " ${station_name} " ]] && [ ${#station_names[@]} -lt $max_stations ]; then
                        station_names+=("$station_name")
                        log "Found station: $station_name"
                    fi
                fi
            fi
        done < <(find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f -name "${station_pattern_bias}" 2>/dev/null | sort)
        
        # Now add both bias and minmax plots for each station (in order)
        for station_name in "${station_names[@]}"; do
            # Add bias plot first (exact match for station name)
            while IFS= read -r bias_plot; do
                if [ -n "$bias_plot" ] && ! grep -qF "$bias_plot" "${var_plotlist}"; then
                    echo "$bias_plot" >> "${var_plotlist}"
                    log "Added station bias plot: $(basename "$bias_plot")"
                fi
            done < <(find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f -name "${model_prefix}*${varname}*_${station_name}_bias.${tex_plot_format}" 2>/dev/null)
            
            # Add minmax plot second (exact match for station name)
            while IFS= read -r minmax_plot; do
                if [ -n "$minmax_plot" ] && ! grep -qF "$minmax_plot" "${var_plotlist}"; then
                    echo "$minmax_plot" >> "${var_plotlist}"
                    log "Added station minmax plot: $(basename "$minmax_plot")"
                fi
            done < <(find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f -name "${model_prefix}*${varname}*_${station_name}_minmax*.${tex_plot_format}" 2>/dev/null)
        done
        
        # Log station plot summary
        local total_station_plots=$(find "${CURRENT_REGION_HPATH}" -maxdepth 1 -type f \( -name "${station_pattern_bias}" -o -name "${station_pattern_minmax}" \) 2>/dev/null | wc -l)
        local added_station_plots=$((${#station_names[@]} * 2))  # 2 plots per station
        if [ "$total_station_plots" -gt "$added_station_plots" ]; then
            local total_stations=$((total_station_plots / 2))
            log "Limited station plots to first ${#station_names[@]} stations (${added_station_plots} plots) out of ${total_stations} total stations"
        elif [ ${#station_names[@]} -gt 0 ]; then
            log "Added station plots for ${#station_names[@]} stations (${added_station_plots} plots)"
        fi
        
        # Generate per-variable TeX file header
        if [ -s "${var_plotlist}" ]; then
            # Format variable name with LaTeX math subscripts
            varname_tex=$(format_var_name_tex "${varname}")
            cat > "${var_texfile}" <<EOF
%===============================================================================
\section{Regional Analysis -- ${tREGION}}
\subsection{${varname_tex} -- ${mDate} (${TIME_AVERAGE})}
EOF
            
            # Generate frames for this variable
            generate_tex_frames "${var_plotlist}" "${var_texfile}" "${varname}"
            
            per_variable_tex_files+=("${var_texfile}")
            log "Generated per-variable TeX file: ${var_texfile}"
        else
            log "No plots found for variable ${varname} in region ${CURRENT_REGION_NAME}"
        fi
    done
    
    return 0
}

# Function to process a single region
process_single_region() {
    local region_code=$1
    
    log "========================================" 
    log "Processing region: ${region_code}"
    log "========================================"
    
    # Clean up region directory to start from scratch
    local region_hpath="${base_hpath}/${region_code}"
    if [ -d "$region_hpath" ]; then
        log "Caution: Previous region directory exits: ${region_hpath}"
        log "Clean up manually if need: rm -rf $region_hpath"
#       log "Cleaning up previous region directory: ${region_hpath}"
#       rm -rf "$region_hpath"
    fi
    
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
    
    # Validate that actual data output files were created (not just station location files)
    # For variables to be successfully processed, we expect variable-specific files
    # Pattern: *_{VARIABLE}_{DATES}_*.nc (e.g., qlc_D1-ANAL_US_..._O3_20251101-20251103_3hourly.nc)
    local region_output_dir="${base_hpath}/${region_code}"
    local data_file_count=0
    
    if [ -d "${region_output_dir}" ]; then
        # Count variable-specific data files (files with variable names and dates in the filename)
        # These contain actual time series data, not just station coordinates
        data_file_count=$(find "${region_output_dir}" -type f -name "*_[A-Z0-9]*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*.nc" | wc -l | tr -d ' ')
        
        if [ "${data_file_count}" -eq 0 ]; then
            log "Warning: No variable data files were generated for region ${region_code}"
            log "  Station location files may exist, but no time series data was extracted"
            log "  This usually means no observation data was available for the selected variables and date range"
            # Don't treat as failure if obs-only mode with no data - this is expected behavior
            # But log it clearly so user knows what happened
            return 1
        else
            log "Generated ${data_file_count} variable data files for region ${region_code}"
        fi
    else
        log "Warning: Output directory not created for region ${region_code}"
        return 1
    fi
    
    # Generate TeX file
    generate_region_tex
    
    log "Completed processing region: ${region_code}"
    return 0
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
        # Process region (discovery happens in load_region_config if needed)
        if process_single_region "${region_code}"; then
            success_count=$((success_count + 1))
            processed_regions+=("${region_code}")
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
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
    
    if [ ${fail_count} -gt 0 ]; then
        log "Warning: Some regions failed to process (${fail_count} failures)"
        exit 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# ============================================================================
# CLI-BASED SYNTHETIC REGION CREATION
# ============================================================================
# Create synthetic regions from command-line overrides when specified
# This allows flexible region creation without modifying workflow configs
# Precedence: CLI parameters > Workflow config > qlc.conf defaults
# ============================================================================

if [ -n "${QLC_CLI_REGION:-}" ]; then
    log "CLI region override detected: ${QLC_CLI_REGION}"
    
    # Strategy 1: Match existing workflow region by PLOT_REGION
    # Find all regions with matching PLOT_REGION (e.g., PLOT_REGION="US")
    # Also check if --observation matches (if specified) to ensure consistency
    matching_regions=()
    for region_var in $(compgen -A variable | grep '^REGION_.*_PLOT_REGION$'); do
        region_code=$(echo "$region_var" | sed 's/REGION_\(.*\)_PLOT_REGION/\1/')
        plot_region_value=$(eval echo \${${region_var}})
        
        if [ "$plot_region_value" = "${QLC_CLI_REGION}" ]; then
            # Check if --observation was specified and matches this region's obs_dataset_type
            if [ -n "${QLC_CLI_OBSERVATION:-}" ]; then
                obs_dataset_var="REGION_${region_code}_OBS_DATASET_TYPE"
                obs_dataset_value=$(eval echo \${${obs_dataset_var}:-})
                
                # Only add to matching regions if observation types match
                if [ "$obs_dataset_value" = "${QLC_CLI_OBSERVATION}" ]; then
                    matching_regions+=("$region_code")
                    log "Region ${region_code} matches both PLOT_REGION='${QLC_CLI_REGION}' and OBS_DATASET_TYPE='${QLC_CLI_OBSERVATION}'"
                else
                    log "Region ${region_code} has PLOT_REGION='${QLC_CLI_REGION}' but OBS_DATASET_TYPE='${obs_dataset_value}' (skipped, CLI wants '${QLC_CLI_OBSERVATION}')"
                fi
            else
                # No --observation specified, accept any matching PLOT_REGION
                matching_regions+=("$region_code")
            fi
        fi
    done
    
    # If matching workflow regions found, use the first one from ACTIVE_REGIONS or first match
    if [ ${#matching_regions[@]} -gt 0 ]; then
        log "Found ${#matching_regions[@]} workflow region(s) matching CLI criteria: ${matching_regions[*]}"
        
        # Check if any matching region is in ACTIVE_REGIONS
        selected_region=""
        if [ ${#ACTIVE_REGIONS[@]} -gt 0 ]; then
            for active_region in "${ACTIVE_REGIONS[@]}"; do
                if [[ " ${matching_regions[*]} " =~ " ${active_region} " ]]; then
                    selected_region="$active_region"
                    break
                fi
            done
        fi
        
        # If no active match, use first matching region
        if [ -z "$selected_region" ]; then
            selected_region="${matching_regions[0]}"
            log "No matching region in ACTIVE_REGIONS, using first match: ${selected_region}"
        else
            log "Using active workflow region: ${selected_region}"
        fi
        
        # Override ACTIVE_REGIONS to process only this region
        ACTIVE_REGIONS=("$selected_region")
        
    else
        # Strategy 2: No matching workflow region - create synthetic region
        log "No workflow regions match PLOT_REGION='${QLC_CLI_REGION}'"
        
        # Determine observation dataset type
        if [ -n "${QLC_CLI_OBSERVATION:-}" ]; then
            obs_type_original="${QLC_CLI_OBSERVATION}"
            # Normalize to lowercase for obs_dataset_type (directory structure convention)
            obs_type_lower=$(echo "${obs_type_original}" | tr '[:upper:]' '[:lower:]')
        else
            log "ERROR: --region specified without matching workflow region and no --observation provided"
            log "Please specify --observation to create a synthetic region, or use a workflow-defined region"
            log "Available workflow regions (by PLOT_REGION):"
            for region_var in $(compgen -A variable | grep '^REGION_.*_PLOT_REGION$'); do
                region_code=$(echo "$region_var" | sed 's/REGION_\(.*\)_PLOT_REGION/\1/')
                plot_region_value=$(eval echo \${${region_var}})
                log "  ${region_code}: PLOT_REGION=${plot_region_value}"
            done
            exit 1
        fi
        
        # Create synthetic region name: REGION_OBSERVATION (e.g., EU_EBAS_DAILY)
        # Use tr for bash 3.2 compatibility (${VAR^^} requires bash 4.0+)
        region_upper=$(echo "${QLC_CLI_REGION}" | tr '[:lower:]' '[:upper:]')
        obs_upper=$(echo "${obs_type_original}" | tr '[:lower:]' '[:upper:]')
        synthetic_region="${region_upper}_${obs_upper}"
        log "Creating synthetic region from CLI: ${synthetic_region}"
        
        # Define synthetic region with CLI parameters + defaults
        # Note: obs_dataset_type uses lowercase for directory structure compatibility
        eval "REGION_${synthetic_region}_NAME='${synthetic_region}'"
        eval "REGION_${synthetic_region}_OBS_DATASET_TYPE='${obs_type_lower}'"
        log "  OBS_DATASET_TYPE: ${obs_type_lower} (normalized to lowercase)"
        eval "REGION_${synthetic_region}_PLOT_REGION='${QLC_CLI_REGION}'"
        
        # Set obs_path (CLI > workflow default > qlc.conf default)
        obs_path_value="${QLC_CLI_OBS_PATH:-${DEFAULT_OBS_PATH:-${QLC_HOME}/obs/data/ver0d}}"
        eval "REGION_${synthetic_region}_OBS_PATH='${obs_path_value}'"
        log "  OBS_PATH: ${obs_path_value}"
        
        # Set obs_dataset_version (CLI > workflow default > qlc.conf default)
        obs_version_value="${QLC_CLI_OBS_DATASET_VERSION:-${DEFAULT_OBS_DATASET_VERSION:-latest}}"
        eval "REGION_${synthetic_region}_OBS_DATASET_VERSION='${obs_version_value}'"
        log "  OBS_DATASET_VERSION: ${obs_version_value}"
        
        # Set station file (CLI > none, will use discovery if not set)
        if [ -n "${QLC_CLI_STATION_SELECTION:-}" ]; then
            station_file_value="${QLC_CLI_STATION_SELECTION/#\~/$HOME}"
            eval "REGION_${synthetic_region}_STATION_FILE='${station_file_value}'"
            log "  STATION_FILE: ${station_file_value}"
        else
            eval "REGION_${synthetic_region}_STATION_FILE=''"
            log "  STATION_FILE: (not set, will use region discovery)"
        fi
        
        # Set station radius (CLI > workflow default > qlc.conf default)
        radius_value="${DEFAULT_STATION_RADIUS_DEG:-${STATION_RADIUS_DEG:-0.5}}"
        eval "REGION_${synthetic_region}_STATION_RADIUS_DEG='${radius_value}'"
        log "  STATION_RADIUS_DEG: ${radius_value}"
        
        # Set ACTIVE_REGIONS to process only this synthetic region
        ACTIVE_REGIONS=("$synthetic_region")
        log "Synthetic region created and activated: ${synthetic_region}"
    fi
    
    log "Final ACTIVE_REGIONS for CLI override: ${ACTIVE_REGIONS[*]}"
    log "Note: Multi-region support via command line is limited to single region"
    log "      For multi-region processing, define ACTIVE_REGIONS in workflow config"
fi

# Process all configured regions
log "Starting multi-region processing..."
process_multi_region

# ----------------------------------------------------------------------------------------
# End of script
# ----------------------------------------------------------------------------------------

log "$ANALYSIS_DIRECTORY"
log "$PLOTS_DIRECTORY"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
