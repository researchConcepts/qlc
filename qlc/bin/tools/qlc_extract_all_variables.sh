#!/usr/bin/env bash

# ============================================================================
# QLC Extract All Variables
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/user-guide/variable-system/
#
# Description:
#   Extracts variable metadata from observation NetCDF files and creates
#   variable mapping CSV files for all available observation types.
#   Uses central obs_networks.conf for consistent network definitions.
#
# Parallelization Strategy:
#   - Network level: Multiple networks processed simultaneously
#   - Configurable parallelism with auto CPU core detection
#   - Status tracking for reliable statistics
#   - Real-time progress reporting
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_extract_all_variables.sh [OPTIONS]
#
#   Options:
#     --networks "net1,net2"  Only process specified networks (comma-separated)
#     --year YYYY             Filter by specific year (default: 2019, or latest available)
#     --all-years             Process all available years (extensive, takes longer)
#     --sample-size N         Number of files to sample per network (default: 50)
#     --output-dir DIR        Output directory (default: ~/qlc/config/tables/obs_database)
#     --max-parallel N        Maximum parallel jobs (default: auto-detect CPU cores)
#     --force                 Overwrite existing CSV files
#     --help                  Show this help message
#
# Examples:
#   # Extract all networks
#   bash qlc_extract_all_variables.sh
#
#   # Extract specific networks only
#   bash qlc_extract_all_variables.sh --networks "ebas_daily,brazil_inmet"
#
#   # Use specific year for filtering
#   bash qlc_extract_all_variables.sh --year 2019
#
#   # Force overwrite existing files
#   bash qlc_extract_all_variables.sh --force
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Configuration
QLC_HOME="${HOME}/qlc"
OBS_NETWORKS_CONF="${QLC_HOME}/config/obs_networks.conf"
OUTPUT_DIR="${QLC_HOME}/config/tables/obs_database"
STATUS_DIR="${OUTPUT_DIR}/.status"
FORCE_OVERWRITE=false
SPECIFIC_NETWORKS=""
YEAR_FILTER="2019"
SAMPLE_SIZE="50"
ALL_YEARS=false
MAX_PARALLEL=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --networks)
            SPECIFIC_NETWORKS="$2"
            shift 2
            ;;
        --year)
            YEAR_FILTER="$2"
            shift 2
            ;;
        --all-years)
            ALL_YEARS=true
            shift
            ;;
        --sample-size)
            SAMPLE_SIZE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --max-parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        --help)
            sed -n '3,48p' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Auto-detect CPU cores if not specified
if [ -z "$MAX_PARALLEL" ]; then
    if command -v nproc &> /dev/null; then
        MAX_PARALLEL=$(nproc)
    elif command -v sysctl &> /dev/null; then
        MAX_PARALLEL=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
    else
        MAX_PARALLEL=4
    fi
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$STATUS_DIR"

# Clean up old status files
rm -f "$STATUS_DIR"/*.status 2>/dev/null

echo "========================================================================"
echo "QLC Variable Extraction Tool (Parallel)"
echo "========================================================================"
echo "Config file:      $OBS_NETWORKS_CONF"
echo "Output directory: $OUTPUT_DIR"
if [ "$ALL_YEARS" = true ]; then
    echo "Year filter:      ALL available years (extensive mode)"
else
    echo "Year filter:      $YEAR_FILTER (or latest available)"
fi
echo "Sample size:      $SAMPLE_SIZE files"
echo "Force overwrite:  $FORCE_OVERWRITE"
echo "Max parallel:     $MAX_PARALLEL"
if [ -n "$SPECIFIC_NETWORKS" ]; then
    echo "Networks filter:  $SPECIFIC_NETWORKS"
else
    echo "Networks filter:  ALL"
fi
echo ""

# Check if config file exists
if [ ! -f "$OBS_NETWORKS_CONF" ]; then
    echo "ERROR: Network configuration file not found: $OBS_NETWORKS_CONF"
    exit 1
fi

# Function to resolve version directory
resolve_version() {
    local base_path="$1"
    local version_dir="$2"
    
    if [ "$version_dir" == "latest" ] && [ -d "$base_path" ]; then
        # Find latest version directory (format: v_YYYYMMDD)
        local latest=$(ls -1d "$base_path"/v_* 2>/dev/null | sort -V | tail -1)
        if [ -n "$latest" ]; then
            echo "$(basename "$latest")"
        else
            echo "latest"
        fi
    else
        echo "$version_dir"
    fi
}

# Function to wait for job slots
wait_for_slot() {
    local max_jobs="$1"
    while [ $(jobs -r | wc -l) -ge "$max_jobs" ]; do
        sleep 0.1
    done
}

# Function to update status file
update_status() {
    local network_key="$1"
    local status="$2"
    local message="$3"
    local count="${4:-0}"
    
    local status_file="${STATUS_DIR}/${network_key}.status"
    echo "status=$status" > "$status_file"
    echo "message=$message" >> "$status_file"
    echo "count=$count" >> "$status_file"
    echo "timestamp=$(date +%s)" >> "$status_file"
}

# Function to aggregate statistics from status files
aggregate_stats() {
    local total=0
    local success=0
    local skipped=0
    local failed=0
    
    for status_file in "$STATUS_DIR"/*.status; do
        [ -f "$status_file" ] || continue
        
        local status_value=$(grep "^status=" "$status_file" | cut -d'=' -f2)
        
        ((total++))
        case "$status_value" in
            success) ((success++)) ;;
            skipped) ((skipped++)) ;;
            failed) ((failed++)) ;;
        esac
    done
    
    echo "$total $success $skipped $failed"
}

# Function to process a single network
process_network() {
    local network_key="$1"
    local data_path="$2"
    local version_dir="$3"
    local metadata_source="$4"
    local description="$5"
    
    # Build full observation path
    # IMPORTANT: Use version_dir as-is (typically "latest" symlink), do NOT resolve to actual version
    # The "latest" symlink always points to correct data; resolved versions may be outdated or missing
    local obs_path="${HOME}/qlc/obs/data/${data_path}"
    if [ -n "$version_dir" ]; then
        obs_path="${obs_path}/${version_dir}"
    fi
    
    local output_file="$OUTPUT_DIR/${network_key}_variables.csv"
    
    # Build year argument for qlc-extract-variables
    # Auto-detect available data and adjust year filter accordingly
    local year_arg=""
    if [ "$ALL_YEARS" = true ]; then
        year_arg=""
        local year_display="ALL available years"
    else
        # Check if data exists and find appropriate year
        local found_year="$YEAR_FILTER"
        local use_year_filter=true
        
        if [ -d "$obs_path" ]; then
            # Count YYYYMM directories (GHOST networks) vs YYYY directories (other networks)
            # Use -L to follow symlinks (e.g., latest -> v_YYYYMMDD)
            local yyyymm_count=$(find -L "$obs_path" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9][0-9][0-9]" 2>/dev/null | wc -l)
            local yyyy_count=$(find -L "$obs_path" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9]" 2>/dev/null | wc -l)
            local other_count=$(find -L "$obs_path" -maxdepth 1 -type d ! -name ".*" ! -name "[0-9]*" 2>/dev/null | wc -l)
            
            # For GHOST networks (YYYYMM directories)
            if [ $yyyymm_count -gt 0 ]; then
                local year_dirs=$(find -L "$obs_path" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9][0-9][0-9]" 2>/dev/null | xargs -n1 basename | sort -u)
                local years=$(echo "$year_dirs" | sed 's/^\([0-9][0-9][0-9][0-9]\).*/\1/' | sort -u)
                
                # Check if default year exists
                if ! echo "$years" | grep -q "^${YEAR_FILTER}$"; then
                    # Use latest available year
                    found_year=$(echo "$years" | tail -1)
                    echo "[$network_key] Note: Year $YEAR_FILTER not found, using latest available: $found_year"
                fi
            
            # For networks with YYYY directories
            elif [ $yyyy_count -gt 0 ]; then
                local years=$(find -L "$obs_path" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9]" 2>/dev/null | xargs -n1 basename | sort -u)
                
                if ! echo "$years" | grep -q "^${YEAR_FILTER}$"; then
                    found_year=$(echo "$years" | tail -1)
                    echo "[$network_key] Note: Year $YEAR_FILTER not found, using latest available: $found_year"
                fi
            
            # For networks with non-year directories (e.g., csv_castnet with "198701-202207")
            elif [ $other_count -gt 0 ]; then
                echo "[$network_key] Note: Non-year-based directory structure detected, omitting year filter"
                use_year_filter=false
            fi
        fi
        
        if [ "$use_year_filter" = true ]; then
            year_arg="--year $found_year"
            local year_display="$found_year (or latest available)"
        else
            year_arg=""
            local year_display="ALL available data (non-year structure)"
        fi
    fi
    
    echo "------------------------------------------------------------------------"
    echo "[$network_key] Starting processing"
    echo "  Description:  $description"
    echo "  Data path:    $obs_path"
    echo "  Year filter:  $year_display"
    echo "  Output:       ${network_key}_variables.csv"
    echo "------------------------------------------------------------------------"
    
    # Check if output file exists and force flag is not set
    if [ -f "$output_file" ] && [ "$FORCE_OVERWRITE" = false ]; then
        echo "[$network_key] [SKIP] File already exists (use --force to overwrite)"
        update_status "$network_key" "skipped" "Already exists" 0
        return 0
    fi
    
    # Check if observation data path exists
    if [ ! -d "$obs_path" ]; then
        echo "[$network_key] [SKIP] Data path does not exist: $obs_path"
        update_status "$network_key" "skipped" "Path not found" 0
        return 1
    fi
    
    # Run qlc-extract-variables
    echo "[$network_key] Extracting variables..."
    # For GHOST networks, use monthly frequency by default for consistency
    if qlc-extract-variables \
        --obs-path "$obs_path" \
        --obs-type "$network_key" \
        $year_arg \
        --sample-size "$SAMPLE_SIZE" \
        --frequency monthly \
        --output "$output_file" 2>&1 | grep -q "successfully"; then
        
        # Count variables in output file
        if [ -f "$output_file" ]; then
            var_count=$(($(wc -l < "$output_file") - 1))
            echo "[$network_key] [SUCCESS] Extracted $var_count variables"
            update_status "$network_key" "success" "Extracted" "$var_count"
            return 0
        else
            echo "[$network_key] [FAILED] Output file not created"
            update_status "$network_key" "failed" "Output not created" 0
            return 1
        fi
    else
        echo "[$network_key] [FAILED] Variable extraction failed"
        update_status "$network_key" "failed" "Extraction failed" 0
        return 1
    fi
}

# Export functions and variables for parallel execution
export -f process_network
export -f resolve_version
export -f wait_for_slot
export -f update_status
export -f aggregate_stats
export OUTPUT_DIR
export STATUS_DIR
export FORCE_OVERWRITE
export YEAR_FILTER
export SAMPLE_SIZE
export ALL_YEARS
export HOME
export MAX_PARALLEL

# Parse obs_networks.conf and process networks in parallel
echo "Processing networks in parallel (max: $MAX_PARALLEL)..."
echo ""

total_networks=0

while IFS='|' read -r network_key data_path version_dir metadata_source description; do
    # Skip comments and empty lines
    [[ "$network_key" =~ ^#.*$ ]] && continue
    [[ -z "$network_key" ]] && continue
    
    # Filter by specific networks if requested
    if [ -n "$SPECIFIC_NETWORKS" ]; then
        if ! echo ",$SPECIFIC_NETWORKS," | grep -q ",$network_key,"; then
            continue
        fi
    fi
    
    ((total_networks++))
    
    # Wait for available slot
    wait_for_slot "$MAX_PARALLEL"
    
    # Launch in background
    process_network "$network_key" "$data_path" "$version_dir" "$metadata_source" "$description" &
    
done < "$OBS_NETWORKS_CONF"

# Wait for all background jobs
echo ""
echo "[INFO] Waiting for all $total_networks networks to complete..."
wait
echo "[INFO] All networks completed"
echo ""

# Aggregate statistics from status files
read total success skipped failed <<< "$(aggregate_stats)"

echo "========================================================================"
echo "Variable Extraction Summary (Parallel Processing)"
echo "========================================================================"
echo "Networks processed: $total"
echo "  Successful:       $success"
echo "  Skipped:          $skipped"
echo "  Failed:           $failed"
echo ""
echo "Output directory:   $OUTPUT_DIR"
echo ""

# Show detailed per-network statistics
echo "Per-network status:"
for status_file in "$STATUS_DIR"/*.status; do
    [ -f "$status_file" ] || continue
    
    network=$(basename "$status_file" .status)
    status=$(grep "^status=" "$status_file" | cut -d'=' -f2)
    count=$(grep "^count=" "$status_file" | cut -d'=' -f2)
    message=$(grep "^message=" "$status_file" | cut -d'=' -f2)
    
    case "$status" in
        success)
            echo "  [SUCCESS] $network: $count variables ($message)"
            ;;
        skipped)
            echo "  [SKIP] $network: $message"
            ;;
        failed)
            echo "  [FAILED] $network: $message"
            ;;
    esac
done | sort

echo ""
echo "Parallelization:"
echo "  Max parallel jobs: $MAX_PARALLEL"
echo "  Processing mode:   Network level"
echo ""
echo "Next steps:"
echo "  1. Verify extracted variables:"
echo "     qlc-vars search PM2.5"
echo ""
echo "  2. Extract station metadata:"
echo "     ~/qlc/bin/tools/qlc_extract_all_station_metadata.sh"
echo ""
echo "  3. Generate station location files:"
echo "     ~/qlc/bin/tools/qlc_generate_all_station_locations.sh"
echo "========================================================================"

# Clean up status directory
rm -rf "$STATUS_DIR"

# Exit with error code if any failed
if [ $failed -gt 0 ]; then
    exit 1
else
    exit 0
fi
