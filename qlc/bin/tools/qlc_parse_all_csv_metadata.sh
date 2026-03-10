#!/usr/bin/env bash

# ============================================================================
# QLC Parse All CSV Station Metadata
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
#
# Description:
#   Parses native CSV station metadata files from observation datasets
#   and converts them to standardized QLC format.
#
# Usage:
#   bash qlc_parse_all_csv_metadata.sh [--force]
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
# ============================================================================

OUTPUT_DIR="${HOME}/qlc/config/station_locations/metadata"
SITE_INFOS_DIR="${HOME}/qlc/obs/data/site-infos"
FORCE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE=true
fi

mkdir -p "$OUTPUT_DIR"

echo "========================================================================"
echo "QLC CSV Metadata Parser"
echo "========================================================================"
echo "Output directory: $OUTPUT_DIR"
echo "Force overwrite:  $FORCE"
echo ""

total=0
success=0
skipped=0
failed=0

# CastNet
total=$((total + 1))
echo "------------------------------------------------------------------------"
echo "Network: CastNet"
echo "------------------------------------------------------------------------"

input_file="${SITE_INFOS_DIR}/castnet_site-info.csv"
output_file="${OUTPUT_DIR}/castnet_metadata.csv"

if [ ! -f "$input_file" ]; then
    echo "  [SKIP] Input file not found: $input_file"
    skipped=$((skipped + 1))
elif [ -f "$output_file" ] && [ "$FORCE" = false ]; then
    echo "  [SKIP] Output file exists (use --force to overwrite)"
    skipped=$((skipped + 1))
else
    if qlc-parse-csv-metadata \
        --input "$input_file" \
        --network castnet \
        --output "$output_file" 2>&1 | grep -q "Saved"; then
        
        stations=$(wc -l < "$output_file" | xargs)
        stations=$((stations - 1))
        echo "  [SUCCESS] Parsed $stations stations"
        success=$((success + 1))
    else
        echo "  [FAILED] Could not parse metadata"
        failed=$((failed + 1))
    fi
fi
echo ""

# AMoN
total=$((total + 1))
echo "------------------------------------------------------------------------"
echo "Network: AMoN"
echo "------------------------------------------------------------------------"

input_file="${SITE_INFOS_DIR}/amon-site-info.csv"
output_file="${OUTPUT_DIR}/amon_metadata.csv"

if [ ! -f "$input_file" ]; then
    echo "  [SKIP] Input file not found: $input_file"
    skipped=$((skipped + 1))
elif [ -f "$output_file" ] && [ "$FORCE" = false ]; then
    echo "  [SKIP] Output file exists (use --force to overwrite)"
    skipped=$((skipped + 1))
else
    if qlc-parse-csv-metadata \
        --input "$input_file" \
        --network amon \
        --output "$output_file" 2>&1 | grep -q "Saved"; then
        
        stations=$(wc -l < "$output_file" | xargs)
        stations=$((stations - 1))
        echo "  [SUCCESS] Parsed $stations stations"
        success=$((success + 1))
    else
        echo "  [FAILED] Could not parse metadata"
        failed=$((failed + 1))
    fi
fi
echo ""

# NNDMN (if it has a metadata CSV)
total=$((total + 1))
echo "------------------------------------------------------------------------"
echo "Network: NNDMN"
echo "------------------------------------------------------------------------"

input_file="${SITE_INFOS_DIR}/nndmn_site-info.csv"
output_file="${OUTPUT_DIR}/nndmn_metadata.csv"

if [ ! -f "$input_file" ]; then
    echo "  [SKIP] No metadata CSV file found in ${OBS_DATA_DIR}/NNDMN/"
    skipped=$((skipped + 1))
elif [ -f "$output_file" ] && [ "$FORCE" = false ]; then
    echo "  [SKIP] Output file exists (use --force to overwrite)"
    skipped=$((skipped + 1))
else
    if qlc-parse-csv-metadata \
        --input "$input_file" \
        --network generic \
        --output "$output_file" 2>&1 | grep -q "Saved"; then
        
        stations=$(wc -l < "$output_file" | xargs)
        stations=$((stations - 1))
        echo "  [SUCCESS] Parsed $stations stations"
        success=$((success + 1))
    else
        echo "  [FAILED] Could not parse metadata"
        failed=$((failed + 1))
    fi
fi
echo ""

echo "========================================================================"
echo "CSV Metadata Parsing Summary"
echo "========================================================================"
echo "Networks processed: $total"
echo "  Successful:       $success"
echo "  Skipped:          $skipped"
echo "  Failed:           $failed"
echo ""
echo "Output directory:   $OUTPUT_DIR"
echo "========================================================================"

