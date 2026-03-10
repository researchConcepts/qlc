#!/usr/bin/env bash

# ============================================================================
# QLC Generate All Station Locations
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Description:
#   Unified station location extraction tool for ALL observation networks.
#   Reads network definitions from obs_networks.conf and generates station
#   location CSV files in parallel for maximum efficiency.
#
# Parallelization Strategy:
#   - Network level: Multiple networks processed simultaneously
#   - Configurable parallelism with auto CPU core detection
#   - Status tracking for reliable statistics
#   - Real-time progress reporting
#
# Usage:
#   bash qlc_generate_all_station_locations.sh [OPTIONS]
#
#   Options:
#     --networks "net1,net2"  Only process specified networks (comma-separated)
#     --include-test          Also generate test files (10 randomly sampled stations)
#     --start-date DATE       Start date for filtering (YYYY-MM-DD, default: 2018-12-01)
#     --end-date DATE         End date for filtering (YYYY-MM-DD, default: 2018-12-31)
#     --sample-size N         Limit number of files to process per network (default: all files)
#                             Station locations change over time, so processing all files is recommended
#     --max-parallel N        Maximum parallel jobs (default: auto-detect CPU cores)
#     --help                  Show this help message
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
# ============================================================================

# Configuration
QLC_HOME="${HOME}/qlc"
OBS_NETWORKS_CONF="${QLC_HOME}/config/obs_networks.conf"
OUTPUT_DIR="${QLC_HOME}/config/station_locations"
STATUS_DIR="${OUTPUT_DIR}/.status"
INCLUDE_TEST=false
START_DATE="2018-12-01"
END_DATE="2018-12-31"
SPECIFIC_NETWORKS=""
SAMPLE_SIZE=""
MAX_PARALLEL=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --networks)
            SPECIFIC_NETWORKS="$2"
            shift 2
            ;;
        --include-test)
            INCLUDE_TEST=true
            shift
            ;;
        --start-date)
            START_DATE="$2"
            shift 2
            ;;
        --end-date)
            END_DATE="$2"
            shift 2
            ;;
        --sample-size)
            SAMPLE_SIZE="$2"
            shift 2
            ;;
        --max-parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --help)
            sed -n '3,32p' "$0" | sed 's/^# //' | sed 's/^#//'
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

# Create output directory
mkdir -p "$OUTPUT_DIR"
mkdir -p "$STATUS_DIR"

# Clean up old status files
rm -f "$STATUS_DIR"/*.status 2>/dev/null

echo "========================================================================"
echo "QLC Station Location Generator (Parallel)"
echo "========================================================================"
echo "Config file:      $OBS_NETWORKS_CONF"
echo "Output directory: $OUTPUT_DIR"
echo "Date range:       $START_DATE to $END_DATE"
echo "Include test:     $INCLUDE_TEST"
if [ -n "$SAMPLE_SIZE" ]; then
    echo "Sample size:      $SAMPLE_SIZE files per network"
else
    echo "Sample size:      ALL files (recommended for complete station coverage)"
fi
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

# Function to resolve version directory (replace "latest" with actual latest version)
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
    local network_key=$1
    local data_path=$2
    local version_dir=$3
    local metadata_source=$4
    
    echo "------------------------------------------------------------------------"
    echo "[$network_key] Starting processing"
    echo "------------------------------------------------------------------------"
    
    # Build full observation path
    # IMPORTANT: Use version_dir as-is (typically "latest" symlink), do NOT resolve to actual version
    # The "latest" symlink always points to correct data; resolved versions may be outdated or missing
    local obs_path="${HOME}/qlc/obs/data/${data_path}"
    if [ -n "$version_dir" ]; then
        obs_path="${obs_path}/${version_dir}"
    fi
    
    # Check if path exists
    if [ ! -d "$obs_path" ]; then
        echo "[$network_key] [SKIP] Path not found: $obs_path"
        update_status "$network_key" "skipped" "Path not found" 0
        return 1
    fi
    
    echo "[$network_key] Path: $obs_path"
    
    # Define station types to process
    local station_types="all urban rural"
    if [ "$INCLUDE_TEST" = true ]; then
        station_types="all urban rural test"
    fi
    
    local success_count=0
    local fail_count=0
    local total_stations=0
    
    for station_type in $station_types; do
        # Set max-stations for test files
        local max_stations_arg=""
        if [ "$station_type" = "test" ]; then
            max_stations_arg="--max-stations 10"
        fi
        
        local output_file="${OUTPUT_DIR}/${network_key}_stations-${station_type}.csv"
        
        # Determine obs_type for qlc-extract-stations
        # Keep network_key as-is (lowercase with underscores)
        local obs_type="$network_key"
        
        # Determine metadata file based on metadata_source from obs_networks.conf
        local metadata_arg=""
        local metadata_dir="${HOME}/qlc/config/station_locations/metadata"
        local metadata_file=""
        
        case "$metadata_source" in
            ebas_shared)
                # EBAS daily/hourly share unified metadata file
                metadata_file="${metadata_dir}/ver0d_ebas_metadata.csv"
                ;;
            ghost_airbase)
                # ver0d_airbase uses ghost_airbase metadata
                metadata_file="${metadata_dir}/ghost_airbase_metadata.csv"
                ;;
            ghost_ebas)
                # ver0d networks that use GHOST EBAS as source
                metadata_file="${metadata_dir}/ghost_ebas_metadata.csv"
                ;;
            ghost_aqs)
                # ver0d networks that use GHOST AQS as source  
                metadata_file="${metadata_dir}/ghost_aqs_metadata.csv"
                ;;
            netcdf|brazil_data|china|csv|aqs|airnow|ghost|ghost_*)
                # All other networks use network_key_metadata.csv
                metadata_file="${metadata_dir}/${network_key}_metadata.csv"
                ;;
            *)
                # Unknown metadata source - use network_key_metadata.csv as fallback
                metadata_file="${metadata_dir}/${network_key}_metadata.csv"
                ;;
        esac
        
        if [ -f "$metadata_file" ]; then
            metadata_arg="--metadata-file $metadata_file"
        elif [ "$metadata_source" = "netcdf" ]; then
            # NetCDF sources can extract metadata on-the-fly, so no warning needed
            :
        else
            # Metadata file should exist for non-netcdf sources
            echo "[$network_key] [WARNING] Metadata file not found: $metadata_file"
        fi
        
        # Run extraction - capture output and status separately
        # Note: Pass complete path in --obs-path, no --obs-version needed (following qlc_extract_all_station_metadata.sh logic)
        local sample_size_arg=""
        if [ -n "$SAMPLE_SIZE" ]; then
            sample_size_arg="--sample-size $SAMPLE_SIZE"
        fi
        
        local extract_output
        extract_output=$(qlc-extract-stations \
            --obs-path "$obs_path" \
            --obs-type "$obs_type" \
            --station-type "${station_type/test/all}" \
            --start-date "$START_DATE" \
            --end-date "$END_DATE" \
            $max_stations_arg \
            $sample_size_arg \
            $metadata_arg \
            --output "$output_file" 2>&1)
        local extract_status=$?
        
        # Check if extraction succeeded by verifying output file exists and has content
        if [ $extract_status -eq 0 ] && [ -f "$output_file" ] && [ -s "$output_file" ]; then
            local count=$(tail -n +2 "$output_file" 2>/dev/null | wc -l | tr -d ' ')
            if [ -n "$count" ] && [ "$count" -gt 0 ]; then
                echo "[$network_key] [SUCCESS] stations-${station_type}.csv: $count stations"
                success_count=$((success_count + 1))
                total_stations=$((total_stations + count))
            else
                echo "[$network_key] [FAILED] stations-${station_type}.csv: empty file"
                # Remove empty file to avoid confusion
                rm -f "$output_file"
                fail_count=$((fail_count + 1))
            fi
        else
            echo "[$network_key] [FAILED] stations-${station_type}.csv (exit code: $extract_status)"
            # Show first error line from output for debugging
            local error_msg=$(echo "$extract_output" | grep -i "error\|failed\|exception" | head -1)
            if [ -n "$error_msg" ]; then
                echo "[$network_key]   Error: $error_msg"
            fi
            # Remove failed output file if it exists
            rm -f "$output_file"
            fail_count=$((fail_count + 1))
        fi
    done
    
    # Determine overall status based on actual extraction results, not leftover files
    if [ $success_count -gt 0 ] && [ $total_stations -gt 0 ]; then
        # At least some files were successfully generated in this run
        local all_file="${OUTPUT_DIR}/${network_key}_stations-all.csv"
        if [ -f "$all_file" ] && [ -s "$all_file" ]; then
            # Main "all" file exists with data
            echo "[$network_key] [SUCCESS] Generated station files: $total_stations total stations ($success_count files)"
            update_status "$network_key" "success" "Generated" "$total_stations"
            return 0
        else
            # Some files generated but not the main "all" file
            echo "[$network_key] [PARTIAL] Generated $success_count files: $total_stations total stations"
            update_status "$network_key" "success" "Partial" "$total_stations"
            return 0
        fi
    else
        # No files successfully generated in this run
        echo "[$network_key] [FAILED] No station files generated"
        update_status "$network_key" "failed" "Generation failed" 0
        return 1
    fi
}

# Export functions and variables for parallel execution
export -f process_network
export -f resolve_version
export -f wait_for_slot
export -f update_status
export -f aggregate_stats
export INCLUDE_TEST
export START_DATE
export END_DATE
export SAMPLE_SIZE
export OUTPUT_DIR
export STATUS_DIR
export HOME
export MAX_PARALLEL

# Parse obs_networks.conf and launch processing
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
    process_network "$network_key" "$data_path" "$version_dir" "$metadata_source" &
    
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
echo "Station Location Generation Summary (Parallel Processing)"
echo "========================================================================"
echo "Networks processed: $total"
echo "  Successful:       $success"
echo "  Skipped:          $skipped"
echo "  Failed:           $failed"
echo ""
echo "Output directory:   $OUTPUT_DIR"
echo ""
echo "Generated files:"
ls -1 "$OUTPUT_DIR"/*_stations-*.csv 2>/dev/null | wc -l | xargs echo "  Total files:"
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
            echo "  [SUCCESS] $network: $count stations ($message)"
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
if [ "$INCLUDE_TEST" = true ]; then
    echo "File types per network: all, urban, rural, test"
else
    echo "File types per network: all, urban, rural"
fi
echo ""
echo "To use these files in workflows, set:"
echo "  STATION_FILE=\"$OUTPUT_DIR/<network>_stations-<type>.csv\""
echo "========================================================================"

# Clean up status directory
rm -rf "$STATUS_DIR"

exit 0

