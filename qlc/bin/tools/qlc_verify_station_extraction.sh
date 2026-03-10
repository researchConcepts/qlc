#!/usr/bin/env bash

# ============================================================================
# QLC Verify Station Extraction Infrastructure
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
#
# Description:
#   Comprehensive verification script for station location extraction system.
#   Tests all components: metadata extraction, variable extraction, and
#   station generation for all networks defined in obs_networks.conf.
#
# Usage:
#   bash qlc_verify_station_extraction.sh [--full]
#
#   Options:
#     --full    Run full extraction (may take 30+ minutes)
#               Default: Quick verification only
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
# ============================================================================

QLC_HOME="${HOME}/qlc"
OBS_NETWORKS_CONF="${QLC_HOME}/config/obs_networks.conf"
FULL_TEST=false

# Parse arguments
if [ "$1" == "--full" ]; then
    FULL_TEST=true
fi

echo "========================================================================"
echo "QLC Station Extraction Infrastructure Verification"
echo "========================================================================"
echo "Mode: $([ "$FULL_TEST" = true ] && echo "FULL EXTRACTION" || echo "QUICK VERIFICATION")"
echo "Date: $(date)"
echo ""

# Test 1: Check configuration file
echo "------------------------------------------------------------------------"
echo "Test 1: Configuration File"
echo "------------------------------------------------------------------------"
if [ -f "$OBS_NETWORKS_CONF" ]; then
    network_count=$(grep -v "^#" "$OBS_NETWORKS_CONF" | grep -v "^$" | wc -l | xargs)
    echo "Configuration file exists: $OBS_NETWORKS_CONF"
    echo "Networks defined: $network_count"
    echo ""
    echo "Network breakdown:"
    echo "  Ver0d networks:   $(grep "^ebas\|^airbase\|^airnow\|^china" "$OBS_NETWORKS_CONF" | wc -l | xargs)"
    echo "  Brazil networks:  $(grep "^brazil" "$OBS_NETWORKS_CONF" | wc -l | xargs)"
    echo "  CSV networks:     $(grep "^amon\|^castnet\|^nndmn" "$OBS_NETWORKS_CONF" | wc -l | xargs)"
    echo "  GHOST networks:   $(grep "^ghost" "$OBS_NETWORKS_CONF" | wc -l | xargs)"
else
    echo "ERROR FAILED: Configuration file not found"
    exit 1
fi
echo ""

# Test 2: Check tools availability
echo "------------------------------------------------------------------------"
echo "Test 2: Tool Availability"
echo "------------------------------------------------------------------------"
tools=(
    "qlc-extract-variables"
    "qlc-extract-stations"
    "qlc-extract-station-metadata"
    "qlc-parse-csv-metadata"
    "qlc-parse-aqs-metadata"
)

all_tools_found=true
for tool in "${tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "$tool"
    else
        echo "ERROR $tool NOT FOUND"
        all_tools_found=false
    fi
done

if [ "$all_tools_found" = false ]; then
    echo ""
    echo "ERROR: Some tools are missing. Please reinstall:"
    echo "  cd ~/qlc_package_dev_pypi && pip install -e . --no-deps"
    exit 1
fi
echo ""

# Test 3: Check metadata directory
echo "------------------------------------------------------------------------"
echo "Test 3: Metadata Files"
echo "------------------------------------------------------------------------"
metadata_dir="${QLC_HOME}/config/station_locations/metadata"
if [ -d "$metadata_dir" ]; then
    metadata_count=$(ls -1 "$metadata_dir"/*.csv 2>/dev/null | wc -l | xargs)
    echo "Metadata directory exists: $metadata_dir"
    echo "Metadata files found: $metadata_count"
    
    # Check specific important metadata files
    echo ""
    echo "Key metadata files:"
    for meta in airnow ghost_aqs ghost_ebas castnet amon; do
        if [ -f "$metadata_dir/${meta}_metadata.csv" ]; then
            count=$(tail -n +2 "$metadata_dir/${meta}_metadata.csv" 2>/dev/null | wc -l | xargs)
            echo "  ${meta}: $count stations"
        else
            echo "  ○ ${meta}: not yet extracted"
        fi
    done
else
    echo "○ Metadata directory will be created"
fi
echo ""

# Test 4: Check station location files
echo "------------------------------------------------------------------------"
echo "Test 4: Station Location Files"
echo "------------------------------------------------------------------------"
station_dir="${QLC_HOME}/config/station_locations"
if [ -d "$station_dir" ]; then
    station_files=$(ls -1 "$station_dir"/*_stations-*.csv 2>/dev/null | wc -l | xargs)
    echo "Station directory exists: $station_dir"
    echo "Station files found: $station_files"
    
    # Count by type
    if [ $station_files -gt 0 ]; then
        echo ""
        echo "Station files by type:"
        echo "  -all files:   $(ls -1 "$station_dir"/*_stations-all.csv 2>/dev/null | wc -l | xargs)"
        echo "  -urban files: $(ls -1 "$station_dir"/*_stations-urban.csv 2>/dev/null | wc -l | xargs)"
        echo "  -rural files: $(ls -1 "$station_dir"/*_stations-rural.csv 2>/dev/null | wc -l | xargs)"
        echo "  -test files:  $(ls -1 "$station_dir"/*_stations-test.csv 2>/dev/null | wc -l | xargs)"
    fi
else
    echo "○ Station directory will be created"
fi
echo ""

# Test 5: Check variable CSV files
echo "------------------------------------------------------------------------"
echo "Test 5: Variable Mapping Files"
echo "------------------------------------------------------------------------"
variables_dir="${QLC_HOME}/config/tables/obs_database"
if [ -d "$variables_dir" ]; then
    variable_files=$(ls -1 "$variables_dir"/*_variables.csv 2>/dev/null | wc -l | xargs)
    echo "Variables directory exists: $variables_dir"
    echo "Variable files found: $variable_files"
    
    # Check key networks
    if [ $variable_files -gt 0 ]; then
        echo ""
        echo "Key variable files:"
        for net in ebas_daily airnow brazil_inmet ghost_harmonized; do
            if [ -f "$variables_dir/${net}_variables.csv" ]; then
                count=$(tail -n +2 "$variables_dir/${net}_variables.csv" 2>/dev/null | wc -l | xargs)
                echo "  ${net}: $count variables"
            else
                echo "  ○ ${net}: not yet extracted"
            fi
        done
    fi
else
    echo "○ Variables directory will be created"
fi
echo ""

# Test 6: Check site-infos directory
echo "------------------------------------------------------------------------"
echo "Test 6: Site Information Directory"
echo "------------------------------------------------------------------------"
siteinfos_dir="${QLC_HOME}/obs/data/site-infos"
if [ -d "$siteinfos_dir" ]; then
    echo "Site-infos directory exists: $siteinfos_dir"
    
    # Check for key files
    if [ -f "$siteinfos_dir/aqs_sites.csv" ]; then
        aqs_count=$(tail -n +2 "$siteinfos_dir/aqs_sites.csv" 2>/dev/null | wc -l | xargs)
        echo "  AQS database: $aqs_count total sites"
    else
        echo "  ERROR AQS database not found (needed for AirNow)"
    fi
    
    if [ -f "$siteinfos_dir/castnet_site_info.csv" ]; then
        echo "  CastNet site info found"
    fi
else
    echo "ERROR Site-infos directory not found: $siteinfos_dir"
    echo "  Please create and populate with metadata files"
fi
echo ""

# Optional: Run full extraction test
if [ "$FULL_TEST" = true ]; then
    echo "========================================================================"
    echo "FULL EXTRACTION TEST (This may take 30+ minutes)"
    echo "========================================================================"
    echo ""
    
    # Extract metadata for all networks
    echo "Step 1: Extracting metadata for all networks..."
    bash "${QLC_HOME}/bin/tools/qlc_extract_all_station_metadata.sh" --force
    echo ""
    
    # Extract variables for 3 test networks
    echo "Step 2: Extracting variables (sample networks)..."
    bash "${QLC_HOME}/bin/tools/qlc_extract_all_variables.sh" \
        --networks "ebas_daily,airnow,brazil_inmet" --force
    echo ""
    
    # Generate station locations (test mode)
    echo "Step 3: Generating station locations (test mode)..."
    bash "${QLC_HOME}/bin/tools/qlc_generate_all_station_locations.sh" \
        --networks "ebas_daily,airnow,brazil_inmet" --include-test
    echo ""
fi

# Summary
echo "========================================================================"
echo "Verification Summary"
echo "========================================================================"
echo ""

issues=0

# Check critical components
if [ ! -f "$OBS_NETWORKS_CONF" ]; then
    echo "ERROR Critical: obs_networks.conf missing"
    ((issues++))
fi

if [ ! -d "$siteinfos_dir" ] || [ ! -f "$siteinfos_dir/aqs_sites.csv" ]; then
    echo "⚠ Warning: AQS database missing (needed for AirNow metadata)"
    ((issues++))
fi

if [ $issues -eq 0 ]; then
    echo "All core components are in place"
    echo ""
    echo "System is ready. To extract all data, run:"
    echo ""
    echo "  1. Extract all metadata:"
    echo "     ~/qlc/bin/tools/qlc_extract_all_station_metadata.sh --force"
    echo ""
    echo "  2. Extract all variables:"
    echo "     ~/qlc/bin/tools/qlc_extract_all_variables.sh --force"
    echo ""
    echo "  3. Generate all station locations:"
    echo "     ~/qlc/bin/tools/qlc_generate_all_station_locations.sh --include-test"
    echo ""
    echo "Or run full verification test:"
    echo "     $0 --full"
else
    echo "⚠ Found $issues issue(s) that need attention"
fi

echo "========================================================================"

exit 0

