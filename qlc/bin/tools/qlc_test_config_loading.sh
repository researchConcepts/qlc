#!/bin/bash

# ============================================================================
# QLC Configuration Loading Test
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/user-guide/configuration/
#
# Description:
#   Test script to verify that workflow configurations properly load and
#   inherit from the base qlc.conf configuration. Useful for debugging
#   configuration issues.
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_test_config_loading.sh
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================
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
echo "Variable Mappings (LEGACY - for reference):"
echo "=========================================="
echo "NOTE: This tests legacy MARS_RETRIEVALS syntax."
echo "      New workflows should use Variable Registry System."
echo ""
if [ ${#MARS_RETRIEVALS[@]} -gt 0 ]; then
    for name in "${MARS_RETRIEVALS[@]}"; do
        # Check if this is a legacy namelist name
        if [[ "$name" =~ ^[A-Z][0-9]+_(sfc|pl|ml)$ ]] || [[ "$name" =~ ^[A-Z]$ ]]; then
            echo "  $name (LEGACY format)"
            myvar_array_name="myvar_${name}[@]"
            if compgen -v | grep -q "^myvar_${name}$"; then
                myvars=("${!myvar_array_name}")
                echo "    Variables: ${myvars[@]}"
            else
                echo "    WARNING: myvar_${name} array not defined"
            fi
        else
            echo "  $name (NEW format - registry variable or group)"
        fi
    done
else
    echo "  (No MARS_RETRIEVALS defined)"
fi

echo ""
echo "=========================================="
echo "New Variable Registry System:"
echo "=========================================="
echo "The new system uses:"
echo "  - Individual variables: PM2p5_sfc, O3_pl, etc."
echo "  - Variable groups: @EAC5_SFC, @EAC5_PL, etc."
echo "  - Expert mode: -param=X -myvar=Y -levtype=Z"
echo ""
echo "For details, see:"
echo "  ~/qlc/config/variables_registry.conf"
echo "  ~/qlc/doc/QuickStart.md"
echo "  https://docs.researchconcepts.io/qlc/latest/"

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

