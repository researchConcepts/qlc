#!/bin/bash
#
# QLC Station Extraction - Example Usage
#
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
#log  "----------------------------------------------------------------------------------------"
#
# This script demonstrates common usage patterns for qlc-extract-stations.
# Uncomment and modify the examples you need.
#
# Requirements:
#   - qlc-extract-stations must be installed (pip install rc-qlc)
#   - Observation data must be available in ~/qlc/obs/data/
#

# Set common variables
OBS_PATH="${HOME}/qlc/obs/data/ver0d"
OBS_TYPE="ebas_daily"
OBS_VERSION="v_20240216/201801"  # Adjust to your data version
OUTPUT_DIR="${HOME}/qlc/obs/data"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

echo "QLC Station Extraction Examples"
echo "================================"
echo ""
echo "Observation path: $OBS_PATH"
echo "Observation type: $OBS_TYPE"
echo "Version: $OBS_VERSION"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Example 1: Extract all stations
echo "Example 1: Extracting all stations..."
qlc-extract-stations \
    --obs-path "$OBS_PATH" \
    --obs-type "$OBS_TYPE" \
    --obs-version "$OBS_VERSION" \
    --output "$OUTPUT_DIR/ebas_station-locations-201801.csv"

echo ""

# Example 2: Extract urban stations only (within 50km of major cities)
echo "Example 2: Extracting urban stations..."
qlc-extract-stations \
    --obs-path "$OBS_PATH" \
    --obs-type "$OBS_TYPE" \
    --obs-version "$OBS_VERSION" \
    --station-type urban \
    --urban-radius-km 50.0 \
    --output "$OUTPUT_DIR/ebas_station-locations-201801-urban.csv"

echo ""

# Example 3: Extract rural stations only
echo "Example 3: Extracting rural stations..."
qlc-extract-stations \
    --obs-path "$OBS_PATH" \
    --obs-type "$OBS_TYPE" \
    --obs-version "$OBS_VERSION" \
    --station-type rural \
    --output "$OUTPUT_DIR/ebas_station-locations-201801-rural.csv"

echo ""

# Example 4: Extract with custom urban radius (e.g., 100km)
# echo "Example 4: Extracting urban stations with 100km radius..."
# qlc-extract-stations \
#     --obs-path "$OBS_PATH" \
#     --obs-type "$OBS_TYPE" \
#     --obs-version "$OBS_VERSION" \
#     --station-type urban \
#     --urban-radius-km 100.0 \
#     --output "$OUTPUT_DIR/ebas_station-locations-201801-urban-100km.csv"

# Example 5: Extract with date filtering
# echo "Example 5: Extracting stations with date filter..."
# qlc-extract-stations \
#     --obs-path "$OBS_PATH" \
#     --obs-type "$OBS_TYPE" \
#     --start-date 2018-01-01 \
#     --end-date 2018-01-31 \
#     --output "$OUTPUT_DIR/ebas_station-locations-201801-filtered.csv"

# Example 6: Extract from different data version
# echo "Example 6: Extracting from different version..."
# qlc-extract-stations \
#     --obs-path "$OBS_PATH" \
#     --obs-type "$OBS_TYPE" \
#     --obs-version "latest/202301" \
#     --output "$OUTPUT_DIR/ebas_station-locations-202301.csv"

# Example 7: Extract with debug mode
# echo "Example 7: Extracting with debug output..."
# qlc-extract-stations \
#     --obs-path "$OBS_PATH" \
#     --obs-type "$OBS_TYPE" \
#     --obs-version "$OBS_VERSION" \
#     --debug \
#     --output "$OUTPUT_DIR/ebas_station-locations-debug.csv"

echo "================================"
echo "Extraction complete!"
echo ""
echo "Output files created in: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"/ebas_station-locations*.csv 2>/dev/null
echo ""
echo "To use these station files in QLC:"
echo "  1. Edit ~/qlc/config/qlc.conf"
echo "  2. Set STATION_FILE to the desired output file"
echo "  3. Run: qlc b2ro b2rn 2018-12-01 2018-12-21 qpy"
echo ""
