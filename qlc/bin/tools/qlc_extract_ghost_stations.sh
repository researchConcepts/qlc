#!/bin/bash

# ============================================================================
# QLC Extract GHOST Station Locations
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/user-guide/variable-system/
#
# Description:
#   Extracts station location information from GHOST (Globally Harmonised
#   Observations in Space and Time) network data files. Processes multiple
#   GHOST networks and generates CSV files for use in QLC workflows.
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_extract_ghost_stations.sh
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

umask 0022
source ~/venv/qlc/bin/activate

OUTPUT_DIR="${HOME}/qlc/config/station_locations"
mkdir -p "${OUTPUT_DIR}"

VERSION="v_20251206"
LOG_FILE="${HOME}/qlc_stations_extraction_$(date +%Y%m%d_%H%M%S).log"

echo "GHOST Station Extraction Log - $(date)" | tee "$LOG_FILE"
echo "Output directory: ${OUTPUT_DIR}" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Define networks to extract stations from
declare -A NETWORKS=(
    ["ghost_harmonized"]="GHOST harmonized network (main)"
    ["ghost-aqs"]="US EPA AQS"
    ["ghost-castnet"]="US CASTNET"
    ["ghost-naps"]="Canadian NAPS"
    ["ghost-uk_air"]="UK AIR"
    ["ghost-airbase"]="European Airbase"
    ["ghost-ebas"]="European EBAS combined"
)

# Station types to extract
TYPES="all urban rural"

success_count=0
fail_count=0

for network in "${!NETWORKS[@]}"; do
    desc="${NETWORKS[$network]}"
    
    echo "" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "Network: ${network}" | tee -a "$LOG_FILE"
    echo "Description: ${desc}" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    
    # Check if network data exists
    if [ ! -d "${HOME}/qlc/obs/data/ghost/${network}/${VERSION}" ] && \
       [ ! -d "${HOME}/qlc/obs/data/ghost/${network/ghost-/}/${VERSION}" ]; then
        echo "  WARNING: Network data not found, skipping..." | tee -a "$LOG_FILE"
        ((fail_count++))
        continue
    fi
    
    for type in $TYPES; do
        output_file="${OUTPUT_DIR}/${network}_stations-${type}.csv"
        
        echo "  Extracting ${type} stations..." | tee -a "$LOG_FILE"
        
        qlc-extract-stations \
            --obs-path ~/qlc/obs/data/ghost \
            --obs-type "${network}" \
            --obs-version "${VERSION}" \
            --station-type "${type}" \
            --urban-radius-km 50 \
            --output "${output_file}" 2>&1 | tee -a "$LOG_FILE"
        
        if [ -f "${output_file}" ]; then
            count=$(tail -n +2 "${output_file}" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$count" -gt 0 ]; then
                echo "    ✓ ${count} stations extracted to ${output_file##*/}" | tee -a "$LOG_FILE"
                ((success_count++))
            else
                echo "    WARNING: File created but empty" | tee -a "$LOG_FILE"
                ((fail_count++))
            fi
        else
            echo "    ✗ Failed to create file" | tee -a "$LOG_FILE"
            ((fail_count++))
        fi
    done
done

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "STATION EXTRACTION COMPLETE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Success: ${success_count} files" | tee -a "$LOG_FILE"
echo "Failed: ${fail_count} attempts" | tee -a "$LOG_FILE"
echo "Log: ${LOG_FILE}" | tee -a "$LOG_FILE"
echo "Location: ${OUTPUT_DIR}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Summary
echo "Created station files:" | tee -a "$LOG_FILE"
ls -lh "${OUTPUT_DIR}"/ghost*.csv 2>/dev/null | tee -a "$LOG_FILE"

total_files=$(ls -1 "${OUTPUT_DIR}"/ghost*.csv 2>/dev/null | wc -l | tr -d ' ')
echo "" | tee -a "$LOG_FILE"
echo "Total: ${total_files} station CSV files" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Next steps:" | tee -a "$LOG_FILE"
echo "  1. Test station file:" | tee -a "$LOG_FILE"
echo "     head ~/qlc/config/station_locations/ghost_harmonized_stations-all.csv" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "  2. Run QLC with GHOST:" | tee -a "$LOG_FILE"
echo "     qlc 9191 0001 2008-01-01 2008-01-31 aifs \\" | tee -a "$LOG_FILE"
echo "         --observation=ghost_harmonized \\" | tee -a "$LOG_FILE"
echo "         --region=EU \\" | tee -a "$LOG_FILE"
echo "         --station_selection=~/qlc/config/station_locations/ghost_harmonized_stations-all.csv" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

