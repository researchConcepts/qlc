#!/bin/bash
# Test script to verify qlc_evaltools.conf properly loads base configuration
#
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
#log  "----------------------------------------------------------------------------------------"
#
echo "=========================================="
echo "Testing Config Loading for evaltools task"
echo "=========================================="

# Simulate qlc_main.sh environment
export QLC_DIR="$HOME/qlc"
export USER_DIR="evaltools"
export CONFIG_DIR="$QLC_DIR/config/$USER_DIR"
export CONFIG_FILE="$CONFIG_DIR/qlc_evaltools.conf"

echo ""
echo "Environment:"
echo "  QLC_DIR=$QLC_DIR"
echo "  CONFIG_DIR=$CONFIG_DIR"
echo "  CONFIG_FILE=$CONFIG_FILE"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

echo ""
echo "Config file exists: ✓"

# Source the config with auto-export
set -a
source "$CONFIG_FILE"
set +a

echo ""
echo "=========================================="
echo "Path Definitions (from base qlc.conf):"
echo "=========================================="
echo "  QLC_HOME=$QLC_HOME"
echo "  ANALYSIS_DIRECTORY=$ANALYSIS_DIRECTORY"
echo "  PLOTS_DIRECTORY=$PLOTS_DIRECTORY"
echo "  MARS_RETRIEVAL_DIRECTORY=$MARS_RETRIEVAL_DIRECTORY"

echo ""
echo "=========================================="
echo "Evaltools-Specific Settings:"
echo "=========================================="
echo "  SUBSCRIPT_NAMES=${SUBSCRIPT_NAMES[@]}"
echo "  MARS_RETRIEVALS=${MARS_RETRIEVALS[@]}"
echo "  EVALTOOLS_OUTPUT_DIR=$EVALTOOLS_OUTPUT_DIR"
echo "  EVALTOOLS_OBS_DIR=$EVALTOOLS_OBS_DIR"
echo "  EVALTOOLS_STATION_DIR=$EVALTOOLS_STATION_DIR"
echo "  EVALTOOLS_STATION_LISTING=$EVALTOOLS_STATION_LISTING"
echo "  EVALTOOLS_REGION=$EVALTOOLS_REGION"

echo ""
echo "=========================================="
echo "Variable Mappings:"
echo "=========================================="
for name in "${MARS_RETRIEVALS[@]}"; do
    myvar_array_name="myvar_${name}[@]"
    myvars=("${!myvar_array_name}")
    echo "  $name: ${myvars[@]}"
done

echo ""
echo "=========================================="
echo "Verification:"
echo "=========================================="

# Check critical paths
if [ -z "$QLC_HOME" ]; then
    echo "  ✗ QLC_HOME not set"
else
    echo "  ✓ QLC_HOME set"
fi

if [ -z "$ANALYSIS_DIRECTORY" ]; then
    echo "  ✗ ANALYSIS_DIRECTORY not set"
else
    echo "  ✓ ANALYSIS_DIRECTORY set"
fi

if [ -z "$EVALTOOLS_OUTPUT_DIR" ]; then
    echo "  ✗ EVALTOOLS_OUTPUT_DIR not set"
else
    echo "  ✓ EVALTOOLS_OUTPUT_DIR set"
fi

if [ ${#SUBSCRIPT_NAMES[@]} -eq 0 ]; then
    echo "  ✗ SUBSCRIPT_NAMES empty"
else
    echo "  ✓ SUBSCRIPT_NAMES contains ${#SUBSCRIPT_NAMES[@]} entries"
fi

if [ ${#MARS_RETRIEVALS[@]} -eq 0 ]; then
    echo "  ✗ MARS_RETRIEVALS empty"
else
    echo "  ✓ MARS_RETRIEVALS contains ${#MARS_RETRIEVALS[@]} entries"
fi

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="

