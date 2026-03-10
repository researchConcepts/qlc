#!/usr/bin/env bash

# ============================================================================
# QLC Extract All Station Metadata
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
#
# Description:
#   Extracts station metadata from pre-defined networks
#   Parses additional site info for certain networks from ~/qlc/obs/data/site-infos
#   Uses central ~/qlc/config/obs_networks.conf for consistent network definitions
#   Features parallel processing at network, sub-network, and year levels
#
# Parallelization Strategy:
#   - Network level: Multiple networks processed simultaneously
#   - Year level: Within GHOST networks, year directories processed in parallel
#   - Temporary files: Each year writes to {network}_metadata.tmp{year}
#   - Merge on success: Deduplicate and merge all .tmp files to final .csv
#   - Statistics tracking: Per-network status files for reliable progress tracking
#   - Two-pass processing: GHOST networks complete before dependent networks
#   - Crash-safe: Progress saved in .tmp files, survives process interruption
#
# Usage:
#   bash qlc_extract_all_station_metadata.sh [OPTIONS]
#
#   Options:
#     --networks "net1,net2"  Only process specified networks (comma-separated)
#     --force                 Overwrite existing metadata files
#     --year YYYY or YYYYMM   Filter by year (YYYY, e.g., 2024) or date (YYYYMM, e.g., 202410)
#                             YYYY: processes ALL files from all months in that year
#                             YYYYMM: processes ALL files from that specific month
#                             If not specified, processes ALL files from entire database
#     --sample-size N         TESTING ONLY: Limit number of files to process
#                             Default: process ALL files (recommended for production)
#     --max-parallel N        Maximum parallel jobs (default: auto-detect CPU cores)
#     --help                  Show this help message
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
# ============================================================================

# Configuration
QLC_HOME="${HOME}/qlc"
OBS_NETWORKS_CONF="${QLC_HOME}/config/obs_networks.conf"
OUTPUT_DIR="${QLC_HOME}/config/station_locations/metadata"
STATUS_DIR="${OUTPUT_DIR}/.status"
FORCE=false
SPECIFIC_NETWORKS=""
YEAR_FILTER=""
SAMPLE_SIZE=""
MAX_PARALLEL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --networks)
            SPECIFIC_NETWORKS="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --year)
            YEAR_FILTER="$2"
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
            # Show only the header documentation (lines 3-35)
            sed -n '3,35p' "$0" | sed 's/^# //' | sed 's/^#//'
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

mkdir -p "$OUTPUT_DIR"
mkdir -p "$STATUS_DIR"

# Clean up old status files
rm -f "$STATUS_DIR"/*.status 2>/dev/null

echo "========================================================================"
echo "QLC Station Metadata Extractor (Parallel)"
echo "========================================================================"
echo "Config file:      $OBS_NETWORKS_CONF"
echo "Output directory: $OUTPUT_DIR"
echo "Force overwrite:  $FORCE"
echo "Max parallel:     $MAX_PARALLEL"
if [ -n "$SPECIFIC_NETWORKS" ]; then
    echo "Networks filter:  $SPECIFIC_NETWORKS"
else
    echo "Networks filter:  ALL"
fi
if [ -n "$YEAR_FILTER" ]; then
    echo "Year/date filter: $YEAR_FILTER"
else
    echo "Year/date filter: ALL (entire database)"
fi
if [ -n "$SAMPLE_SIZE" ]; then
    echo "Sample size:      $SAMPLE_SIZE (TESTING MODE)"
else
    echo "Sample size:      ALL files (production mode)"
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

# Export functions for use in subshells
export -f resolve_version

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

# Function to merge temporary files and remove duplicates
merge_tmp_files() {
    local network_key="$1"
    local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
    local tmp_pattern="${OUTPUT_DIR}/${network_key}_metadata.tmp*"
    
    local tmp_files=($(ls $tmp_pattern 2>/dev/null))
    
    if [ ${#tmp_files[@]} -eq 0 ]; then
        echo "  [ERROR] No temporary files found matching: $tmp_pattern"
        return 1
    fi
    
    echo "  [INFO] Merging ${#tmp_files[@]} temporary files..."
    
    # Create temporary merge file
    local merge_file="${OUTPUT_DIR}/.merge_${network_key}_$$"
    
    # Extract header from first file
    if [ ! -f "${tmp_files[0]}" ] || [ ! -s "${tmp_files[0]}" ]; then
        echo "  [ERROR] First tmp file is empty or missing: ${tmp_files[0]}"
        return 1
    fi
    
    head -n 1 "${tmp_files[0]}" > "$merge_file"
    
    # Merge all data lines, skip headers
    local total_lines=0
    for tmp_file in "${tmp_files[@]}"; do
        local lines=$(($(wc -l < "$tmp_file" 2>/dev/null || echo "1") - 1))
        total_lines=$((total_lines + lines))
        tail -n +2 "$tmp_file" >> "$merge_file"
    done
    
    echo "  [INFO] Combined $total_lines rows from ${#tmp_files[@]} files"
    
    # Remove duplicates based on first column (site_id), keep first occurrence
    awk -F',' 'NR==1 {print; next} !seen[$1]++ {print}' "$merge_file" > "${merge_file}.dedup"
    
    local dedup_lines=$(($(wc -l < "${merge_file}.dedup") - 1))
    local duplicates=$((total_lines - dedup_lines))
    if [ $duplicates -gt 0 ]; then
        echo "  [INFO] Removed $duplicates duplicate station(s)"
    fi
    
    # Sort by site_id (skip header)
    (head -n 1 "${merge_file}.dedup" && tail -n +2 "${merge_file}.dedup" | sort -t',' -k1,1) > "$output_file"
    
    # Clean up
    rm -f "$merge_file" "${merge_file}.dedup"
    rm -f $tmp_pattern
    
    return 0
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

# Export all functions for use in background jobs
export -f wait_for_slot
export -f update_status
export -f merge_tmp_files
export -f aggregate_stats

# Function to process GHOST network with year-level parallelization
process_ghost_network() {
    local network_key="$1"
    local obs_path="$2"
    local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
    
    echo "------------------------------------------------------------------------"
    echo "Network: $network_key (parallel year processing)"
    echo "  Source:  GHOST NetCDF"
    echo "  Path:    $obs_path"
    echo "------------------------------------------------------------------------"
    
    # Check if path exists
    if [ ! -d "$obs_path" ]; then
        echo "  [SKIP] Path not found"
        update_status "$network_key" "skipped" "Path not found" 0
        return 0
    fi
    
    # Check if output exists and not forcing
    if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
        echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
        update_status "$network_key" "skipped" "Already exists" 0
        return 0
    fi
    
    # Clean up old tmp files for this network
    rm -f "${OUTPUT_DIR}/${network_key}_metadata.tmp"* 2>/dev/null
    
    # Find all year/month subdirectories
    local subdirs=()
    if [ -n "$YEAR_FILTER" ]; then
        # Filter by specific year or year-month
        for subdir in "$obs_path"/*; do
            [ -d "$subdir" ] || continue
            local dirname=$(basename "$subdir")
            if [[ "$dirname" =~ ^[0-9]{4}$ ]] || [[ "$dirname" =~ ^[0-9]{6}$ ]]; then
                if [[ "$dirname" == ${YEAR_FILTER}* ]]; then
                    subdirs+=("$subdir")
                fi
            fi
        done
    else
        # Process all subdirectories
        for subdir in "$obs_path"/*; do
            [ -d "$subdir" ] || continue
            local dirname=$(basename "$subdir")
            if [[ "$dirname" =~ ^[0-9]{4}$ ]] || [[ "$dirname" =~ ^[0-9]{6}$ ]]; then
                subdirs+=("$subdir")
            fi
        done
    fi
    
    if [ ${#subdirs[@]} -eq 0 ]; then
        echo "  [SKIP] No year/month directories found"
        update_status "$network_key" "skipped" "No directories" 0
        return 0
    fi
    
    # Limit subdirectories if sample-size is set (for testing)
    # Note: --sample-size N limits FILES processed per subdirectory
    # For faster testing, also limit NUMBER of subdirectories to sample-size/10
    if [ -n "$SAMPLE_SIZE" ]; then
        local max_subdirs=$((SAMPLE_SIZE / 10))
        [ "$max_subdirs" -lt 1 ] && max_subdirs=1
        if [ ${#subdirs[@]} -gt $max_subdirs ]; then
            echo "  [INFO] TESTING MODE: Processing $max_subdirs of ${#subdirs[@]} subdirectories, $SAMPLE_SIZE files each"
            subdirs=("${subdirs[@]:0:$max_subdirs}")
        fi
    fi
    
    echo "  [INFO] Processing ${#subdirs[@]} subdirectories in parallel (max: $MAX_PARALLEL)"
    
    # Create progress tracking directory
    local progress_dir="${STATUS_DIR}/${network_key}_progress"
    mkdir -p "$progress_dir"
    
    # Process subdirectories in parallel with progress tracking
    local job_count=0
    local total_subdirs=${#subdirs[@]}
    for subdir in "${subdirs[@]}"; do
        local dirname=$(basename "$subdir")
        local tmp_file="${OUTPUT_DIR}/${network_key}_metadata.tmp${dirname}"
        local progress_file="${progress_dir}/${dirname}.done"
        
        # Wait for available slot
        wait_for_slot "$MAX_PARALLEL"
        
        # Process this subdirectory in background
        (
            cmd_args=(
                --obs-path "$subdir"
                --obs-type "$network_key"
                --output "$tmp_file"
            )
            if [ -n "$SAMPLE_SIZE" ]; then
                cmd_args+=(--sample-size "$SAMPLE_SIZE")
            fi
            
            if qlc-extract-station-metadata "${cmd_args[@]}" > /dev/null 2>&1; then
                local stations=$(($(wc -l < "$tmp_file" 2>/dev/null || echo "1") - 1))
                echo "$stations" > "$progress_file"
                local completed=$(ls -1 "$progress_dir"/*.done 2>/dev/null | wc -l)
                echo "    [$completed/$total_subdirs] Completed $dirname: $stations stations"
            else
                echo "0" > "$progress_file"
                local completed=$(ls -1 "$progress_dir"/*.done 2>/dev/null | wc -l)
                echo "    [$completed/$total_subdirs] Failed $dirname"
            fi
        ) &
        
        ((job_count++))
    done
    
    # Wait for all subdirectory jobs to complete
    echo "  [INFO] Waiting for $job_count subdirectory jobs to complete..."
    wait
    
    # Count successful completions
    local completed_count=$(ls -1 "$progress_dir"/*.done 2>/dev/null | wc -l)
    echo "  [INFO] Completed $completed_count/$total_subdirs subdirectories, merging results..."
    
    # Clean up progress tracking
    rm -rf "$progress_dir"
    
    # Merge all temporary files
    if merge_tmp_files "$network_key"; then
        local stations=$(($(wc -l < "$output_file") - 1))
        echo "  [SUCCESS] Extracted metadata for $stations stations"
        update_status "$network_key" "success" "Extracted" "$stations"
        return 0
    else
        echo "  [FAILED] Could not merge temporary files"
        update_status "$network_key" "failed" "Merge failed" 0
        return 1
    fi
}

# Function to process a single network (called in parallel)
process_network() {
    local network_key="$1"
    local data_path="$2"
    local version_dir="$3"
    local metadata_source="$4"
    local description="$5"
    
    case "$metadata_source" in
        ghost)
            # Build obs path
            local obs_path="${HOME}/qlc/obs/data/${data_path}"
            local resolved_version=$(resolve_version "$obs_path" "$version_dir")
            if [ -n "$resolved_version" ]; then
                obs_path="${obs_path}/${resolved_version}"
            fi
            
            # Process with year-level parallelization
            process_ghost_network "$network_key" "$obs_path"
            ;;
            
        ebas_shared)
            # Special handling for EBAS shared metadata
            local shared_metadata="${OUTPUT_DIR}/ver0d_ebas_metadata.csv"
            local marker_file="${OUTPUT_DIR}/.ebas_metadata_generated"
            
            # Only first EBAS network generates, others skip
            if [ "$network_key" != "ver0d_ebas_daily" ]; then
                echo "------------------------------------------------------------------------"
                echo "Network: $network_key"
                echo "  Source:  EBAS shared metadata (generated by ver0d_ebas_daily)"
                echo "------------------------------------------------------------------------"
                echo "  [SKIP] Using shared EBAS metadata file"
                update_status "$network_key" "skipped" "Uses shared metadata" 0
                return 0
            fi
            
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key (EBAS shared)"
            echo "  Source:  EBAS website CSV + Ver0d NetCDF enrichment"
            echo "------------------------------------------------------------------------"
            
            local ver0d_base_path="${HOME}/qlc/obs/data/ver0d"
            
            if [ ! -d "$ver0d_base_path" ]; then
                echo "  [SKIP] Ver0d base path not found"
                update_status "$network_key" "skipped" "Path not found" 0
                return 0
            fi
            
            if [ -f "$shared_metadata" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Shared metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if qlc-generate-ebas-metadata \
                --ver0d-path "$ver0d_base_path" \
                --output "$shared_metadata" 2>&1 | grep -q "Metadata generation complete"; then
                
                local stations=$(($(wc -l < "$shared_metadata") - 1))
                echo "  [SUCCESS] Generated shared EBAS metadata: $stations stations"
                update_status "$network_key" "success" "Generated shared" "$stations"
                return 0
            else
                echo "  [FAILED] Could not generate EBAS metadata"
                update_status "$network_key" "failed" "Generation failed" 0
                return 1
            fi
            ;;
            
        csv)
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key"
            echo "  Source:  Native CSV"
            echo "------------------------------------------------------------------------"
            
            local site_infos_dir="${HOME}/qlc/obs/data/site-infos"
            local base_network="${network_key#csv_}"
            local input_file=""
            local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
            
            case "$base_network" in
                castnet) input_file="${site_infos_dir}/castnet_site-info.csv" ;;
                amon) input_file="${site_infos_dir}/amon-site-info.csv" ;;
                nndmn) input_file="${site_infos_dir}/nndmn_site-info.csv" ;;
                *)
                    echo "  [SKIP] No CSV metadata parser defined"
                    update_status "$network_key" "skipped" "No parser defined" 0
                    return 0
                    ;;
            esac
            
            if [ -z "$input_file" ] || [ ! -f "$input_file" ]; then
                echo "  [SKIP] Input CSV not found"
                update_status "$network_key" "skipped" "Input not found" 0
                return 0
            fi
            
            if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if qlc-parse-csv-metadata \
                --input "$input_file" \
                --network "$base_network" \
                --output "$output_file" 2>&1 | grep -q "Saved"; then
                
                local stations=$(($(wc -l < "$output_file") - 1))
                echo "  [SUCCESS] Parsed $stations stations"
                update_status "$network_key" "success" "Parsed" "$stations"
                return 0
            else
                echo "  [FAILED] Could not parse metadata"
                update_status "$network_key" "failed" "Parse failed" 0
                return 1
            fi
            ;;
            
        aqs|airnow)
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key"
            echo "  Source:  EPA AQS Database"
            echo "------------------------------------------------------------------------"
            
            local input_file="${HOME}/qlc/obs/data/site-infos/aqs_site-info.csv"
            local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
            
            if [ ! -f "$input_file" ]; then
                echo "  [SKIP] AQS database not found"
                update_status "$network_key" "skipped" "Database not found" 0
                return 0
            fi
            
            if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if qlc-parse-aqs-metadata \
                --input "$input_file" \
                --output "$output_file" 2>&1 | grep -q "Successfully"; then
                
                local stations=$(($(wc -l < "$output_file") - 1))
                echo "  [SUCCESS] Extracted $stations active AQS stations"
                update_status "$network_key" "success" "Extracted" "$stations"
                return 0
            else
                echo "  [FAILED] Could not extract AQS metadata"
                update_status "$network_key" "failed" "Extraction failed" 0
                return 1
            fi
            ;;
            
        brazil_data)
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key"
            echo "  Source:  Brazil site-info CSV"
            echo "------------------------------------------------------------------------"
            
            local site_info_file="${HOME}/qlc/obs/data/site-infos/brazil_data_site-info.csv"
            local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
            
            if [ ! -f "$site_info_file" ]; then
                echo "  [SKIP] Brazil site-info not found"
                update_status "$network_key" "skipped" "Site-info not found" 0
                return 0
            fi
            
            if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if qlc-parse-csv-metadata \
                --input "$site_info_file" \
                --network brazil_data \
                --filter-network "$network_key" \
                --output "$output_file" 2>&1 | grep -q "Saved"; then
                
                local stations=$(($(wc -l < "$output_file") - 1))
                echo "  [SUCCESS] Created metadata for $stations stations"
                update_status "$network_key" "success" "Created" "$stations"
                return 0
            else
                echo "  [FAILED] Could not create metadata"
                update_status "$network_key" "failed" "Creation failed" 0
                return 1
            fi
            ;;
            
        china)
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key"
            echo "  Source:  China CNEMC site-info CSV"
            echo "------------------------------------------------------------------------"
            
            local site_info_file="${HOME}/qlc/obs/data/site-infos/china_site-info.csv"
            local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
            
            if [ ! -f "$site_info_file" ]; then
                echo "  [SKIP] China site-info not found"
                update_status "$network_key" "skipped" "Site-info not found" 0
                return 0
            fi
            
            if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if qlc-parse-csv-metadata \
                --input "$site_info_file" \
                --network china \
                --output "$output_file" 2>&1 | grep -q "Saved"; then
                
                local stations=$(($(wc -l < "$output_file") - 1))
                echo "  [SUCCESS] Created metadata for $stations stations"
                update_status "$network_key" "success" "Created" "$stations"
                return 0
            else
                echo "  [FAILED] Could not create metadata"
                update_status "$network_key" "failed" "Creation failed" 0
                return 1
            fi
            ;;
            
        eea)
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key"
            echo "  Source:  EEA Airbase Database"
            echo "------------------------------------------------------------------------"
            
            local input_file="${HOME}/qlc/obs/data/site-infos/eea_site-info.csv"
            local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
            
            if [ ! -f "$input_file" ]; then
                echo "  [SKIP] EEA site database not found: $input_file"
                update_status "$network_key" "skipped" "Database not found" 0
                return 0
            fi
            
            if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if qlc-parse-eea-metadata \
                --input "$input_file" \
                --output "$output_file" 2>&1 | grep -q "Successfully"; then
                
                local stations=$(($(wc -l < "$output_file") - 1))
                echo "  [SUCCESS] Extracted $stations stations"
                update_status "$network_key" "success" "Extracted" "$stations"
                return 0
            else
                echo "  [FAILED] EEA metadata extraction failed"
                update_status "$network_key" "failed" "Extraction failed" 0
                return 1
            fi
            ;;
            
        ghost_*)
            echo "------------------------------------------------------------------------"
            echo "Network: $network_key"
            echo "  Source:  GHOST metadata ($metadata_source)"
            echo "------------------------------------------------------------------------"
            
            local source_metadata="${OUTPUT_DIR}/${metadata_source}_metadata.csv"
            local output_file="${OUTPUT_DIR}/${network_key}_metadata.csv"
            
            if [ ! -f "$source_metadata" ]; then
                echo "  [SKIP] Source GHOST metadata not found"
                update_status "$network_key" "skipped" "Source not found" 0
                return 0
            fi
            
            if [ -f "$output_file" ] && [ "$FORCE" = false ]; then
                echo "  [SKIP] Metadata file already exists (use --force to overwrite)"
                update_status "$network_key" "skipped" "Already exists" 0
                return 0
            fi
            
            if cp "$source_metadata" "$output_file" 2>/dev/null; then
                local stations=$(($(wc -l < "$output_file") - 1))
                echo "  [SUCCESS] Created metadata from GHOST source: $stations stations"
                update_status "$network_key" "success" "Copied from GHOST" "$stations"
                return 0
            else
                echo "  [FAILED] Could not copy metadata"
                update_status "$network_key" "failed" "Copy failed" 0
                return 1
            fi
            ;;
            
        *)
            echo "  [SKIP] Unknown metadata source: $metadata_source"
            update_status "$network_key" "skipped" "Unknown source" 0
            return 0
            ;;
    esac
    
    echo ""
}

# Export main processing functions
export -f process_ghost_network
export -f process_network

# Export key variables for subshells
export OUTPUT_DIR
export STATUS_DIR
export FORCE
export YEAR_FILTER
export SAMPLE_SIZE
export MAX_PARALLEL

# Process networks in two passes (strict two-pass for dependencies):
# Pass 1: Process all 'ghost' networks first (so their metadata is available for ghost_* sources)
# Pass 2: Process all other networks
# Within each pass, networks are processed in parallel

echo "========================================================================"
echo "PASS 1: Processing GHOST networks (parallel)"
echo "========================================================================"
echo ""

# Array to store networks for Pass 1
declare -a pass1_networks=()

while IFS='|' read -r network_key data_path version_dir metadata_source description; do
    # Skip comments and empty lines
    [[ "$network_key" =~ ^#.*$ ]] && continue
    [[ -z "$network_key" ]] && continue
    
    # Pass 1: Only process ghost networks
    [ "$metadata_source" != "ghost" ] && continue
    
    # Filter by specific networks if requested
    if [ -n "$SPECIFIC_NETWORKS" ]; then
        if ! echo ",$SPECIFIC_NETWORKS," | grep -q ",$network_key,"; then
            continue
        fi
    fi
    
    # Add to Pass 1 networks array
    pass1_networks+=("$network_key|$data_path|$version_dir|$metadata_source|$description")
done < "$OBS_NETWORKS_CONF"

# Process Pass 1 networks in parallel
for network_line in "${pass1_networks[@]}"; do
    IFS='|' read -r network_key data_path version_dir metadata_source description <<< "$network_line"
    
    # Wait for available slot
    wait_for_slot "$MAX_PARALLEL"
    
    # Process network in background
    process_network "$network_key" "$data_path" "$version_dir" "$metadata_source" "$description" &
done

# Wait for all Pass 1 jobs to complete before starting Pass 2
echo ""
echo "[INFO] Waiting for all GHOST networks to complete..."
wait
echo "[INFO] Pass 1 complete"
echo ""

echo "========================================================================"
echo "PASS 2: Processing all other networks (parallel)"
echo "========================================================================"
echo ""

# Array to store networks for Pass 2
declare -a pass2_networks=()

while IFS='|' read -r network_key data_path version_dir metadata_source description; do
    # Skip comments and empty lines
    [[ "$network_key" =~ ^#.*$ ]] && continue
    [[ -z "$network_key" ]] && continue
    
    # Pass 2: Skip ghost networks (already processed)
    [ "$metadata_source" = "ghost" ] && continue
    
    # Filter by specific networks if requested
    if [ -n "$SPECIFIC_NETWORKS" ]; then
        if ! echo ",$SPECIFIC_NETWORKS," | grep -q ",$network_key,"; then
            continue
        fi
    fi
    
    # Add to Pass 2 networks array
    pass2_networks+=("$network_key|$data_path|$version_dir|$metadata_source|$description")
done < "$OBS_NETWORKS_CONF"

# Process Pass 2 networks in parallel
for network_line in "${pass2_networks[@]}"; do
    IFS='|' read -r network_key data_path version_dir metadata_source description <<< "$network_line"
    
    # Wait for available slot
    wait_for_slot "$MAX_PARALLEL"
    
    # Process network in background
    process_network "$network_key" "$data_path" "$version_dir" "$metadata_source" "$description" &
done

# Wait for all Pass 2 jobs to complete
echo ""
echo "[INFO] Waiting for all other networks to complete..."
wait
echo "[INFO] Pass 2 complete"
echo ""

# Aggregate statistics from status files
read total success skipped failed <<< "$(aggregate_stats)"

echo "========================================================================"
echo "Metadata Extraction Summary (Parallel Processing)"
echo "========================================================================"
echo "Networks processed: $total"
echo "  Successful:       $success"
echo "  Skipped:          $skipped"
echo "  Failed:           $failed"
echo ""
echo "Output directory:   $OUTPUT_DIR"
echo ""
echo "Metadata files created:"
ls -1 "$OUTPUT_DIR"/*.csv 2>/dev/null | wc -l | xargs echo "  Total files:"
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
echo "  Processing mode:   Network + Year level"
echo ""
echo "Next step:"
echo "  Generate station location files:"
echo "    ~/qlc/bin/tools/qlc_generate_all_station_locations.sh --include-test"
echo "========================================================================"

# Clean up status directory
rm -rf "$STATUS_DIR"

exit 0
