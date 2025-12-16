#!/bin/bash

# ============================================================================
# QLC Generate Station Locations
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/user-guide/workflows/
#
# Description:
#   Generates station location CSV files for all available observation types
#   including NetCDF-based, GHOST networks, and CSV-based observations.
#   Creates complete station lists and urban/rural subsets.
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_generate_station_locations.sh
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Configuration
OUTPUT_DIR="${HOME}/qlc/config/station_locations"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "========================================================================"
echo "QLC Station Location Generator"
echo "========================================================================"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Define observation types with their specific configurations
# Format: OBS_TYPE OBS_PATH OBS_VERSION

declare -A OBS_CONFIGS=(
    # NetCDF-based observations (working)
    ["AirBase"]="ver0d:latest/2018"
    ["AirNow"]="ver0d:latest/202511"
    ["Ebas_hourly"]="ver0d:latest/201812"
    ["Ebas_daily"]="ver0d:latest/201812"
    ["China_AQ"]="ver0d:latest/201812"
    ["China_GSV"]="ver0d:latest/201812"
    
    # GHOST networks (v1.0.1 beta)
    ["GHOST_EBAS"]="ghost/ebas:v_20251206"
    ["GHOST_AQS"]="ghost/aqs:v_20251206"
    ["GHOST_AIRBASE"]="ghost/airbase:v_20251206"
    ["GHOST_CASTNET"]="ghost/castnet:v_20251206"
    ["GHOST_NAPS"]="ghost/naps:v_20251206"
    ["GHOST_UK_AIR"]="ghost/uk_air:v_20251206"
    
    # CSV-based observations (v1.0.1 beta)
    ["AMoN"]="AMoN:latest/2018"
    ["CastNet"]="CastNet:latest/198701-202207"
    ["NNDMN"]="NNDMN:latest/2018"
)

# Station type cases to generate
CASES="urban rural all"

# Processing counter
total_processed=0
total_success=0
total_failed=0

# Process each observation type
for OBS_TYPE in "${!OBS_CONFIGS[@]}"; do
    # Parse configuration
    IFS=':' read -r OBS_BASE OBS_VERSION <<< "${OBS_CONFIGS[$OBS_TYPE]}"
    
    # Build observation path
    if [ "$OBS_BASE" == "ver0d" ]; then
        OBS_PATH="${HOME}/qlc/obs/data/ver0d"
    else
        OBS_PATH="${HOME}/qlc/obs/data/${OBS_BASE}"
    fi
    
    echo "------------------------------------------------------------------------"
    echo "Processing: $OBS_TYPE"
    echo "  Path:    $OBS_PATH"
    echo "  Version: $OBS_VERSION"
    echo "------------------------------------------------------------------------"
    
    # Check if observation data exists
    if [ ! -d "$OBS_PATH" ]; then
        echo "  [WARNING] Observation data path does not exist: $OBS_PATH"
        echo "  Skipping $OBS_TYPE"
        echo ""
        continue
    fi
    
    # Process each station type case
    for CASE in $CASES; do
        total_processed=$((total_processed + 1))
        
        OUTPUT_FILE="$OUTPUT_DIR/${OBS_TYPE}_stations-${CASE}.csv"
        
        echo "  Generating: ${OBS_TYPE}_stations-${CASE}.csv"
        
        # Run qlc-extract-stations
        if qlc-extract-stations \
            --obs-path "$OBS_PATH" \
            --obs-type "$OBS_TYPE" \
            --obs-version "$OBS_VERSION" \
            --station-type "$CASE" \
            --urban-radius-km "50.0" \
            --output "$OUTPUT_FILE" 2>&1 | grep -q "Successfully"; then
            
            # Check if output file was created
            if [ -f "$OUTPUT_FILE" ]; then
                station_count=$(tail -n +2 "$OUTPUT_FILE" | wc -l | tr -d ' ')
                echo "    ✓ Success: $station_count stations"
                total_success=$((total_success + 1))
            else
                echo "    ✗ Failed: Output file not created"
                total_failed=$((total_failed + 1))
            fi
        else
            echo "    ✗ Failed: qlc-extract-stations error"
            total_failed=$((total_failed + 1))
        fi
    done
    
    echo ""
done

echo "========================================================================"
echo "Station Location Generation Complete"
echo "========================================================================"
echo "Total processed: $total_processed"
echo "Successful:      $total_success"
echo "Failed:          $total_failed"
echo ""
echo "Generated files location: $OUTPUT_DIR"
echo ""
echo "To use these station files in workflows, set:"
echo "  STATION_FILE=\"$OUTPUT_DIR/<observation>_stations-<type>.csv\""
echo "========================================================================"

exit 0
