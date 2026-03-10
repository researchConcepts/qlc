#!/bin/bash
#
# Brazilian Data Conversion Wrapper Script
#
# Convenient wrapper for converting Brazilian monitoring network data to NetCDF format.
# Handles station extraction and data conversion for all three networks.
#
# Usage:
#   ./qlc_convert_brazil.sh [OPTIONS]
#
# Options:
#   --network NETWORK    Network to convert: inmet, state_aq, sao_paulo, or all (default: all)
#   --source DIR         Source data directory (required)
#   --output DIR         Output directory (default: ~/qlc/obs/data/nc)
#   --config DIR         QLC config directory (default: ~/qlc/config)
#   --version VERSION    Version identifier (default: v_YYYYMMDD)
#   --years YEARS        Comma-separated years to process (default: all)
#   --format FORMAT      NetCDF format: 2d=(time,station) or flat=(record) (default: 2d)
#   --extract-stations   Extract station locations before conversion
#   --force              Force reprocessing of existing NetCDF files
#   --debug              Enable debug logging
#   --help               Show this help message
#
# Examples:
#   # Convert all networks with automatic version
#   ./qlc_convert_brazil.sh --source /Volumes/Data/OBS/Brazil_AQ --extract-stations
#
#   # Convert only INMET data for specific years
#   ./qlc_convert_brazil.sh --network inmet --source /Volumes/Data/OBS/Brazil_AQ/Meteo_Data_Brazil_2000-2025 --years 2018,2019
#
#   # Convert with custom version identifier
#   ./qlc_convert_brazil.sh --source /Volumes/Data/OBS/Brazil_AQ --version v_20250119 --extract-stations
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
#

set -e  # Exit on error

# Default values
NETWORK="all"
SOURCE_DIR=""
OUTPUT_DIR="${HOME}/qlc/obs/data/nc"
CONFIG_DIR="${HOME}/qlc/config"
VERSION="v_$(date +%Y%m%d)"
YEARS=""
FORMAT="2d"
EXTRACT_STATIONS=false
FORCE=false
DEBUG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --config)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --years)
            YEARS="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --extract-stations)
            EXTRACT_STATIONS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$SOURCE_DIR" ]; then
    echo "Error: --source directory is required"
    echo "Use --help for usage information"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Expand paths
SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"

# Print configuration
echo "================================================================================"
echo "BRAZILIAN DATA CONVERSION"
echo "================================================================================"
echo "Network:          $NETWORK"
echo "Source:           $SOURCE_DIR"
echo "Output:           $OUTPUT_DIR"
echo "Config:           $CONFIG_DIR"
echo "Version:          $VERSION"
if [ -n "$YEARS" ]; then
    echo "Years:            $YEARS"
else
    echo "Years:            all available"
fi
echo "Extract stations: $EXTRACT_STATIONS"
echo "Force reprocess:  $FORCE"
echo "Debug mode:       $DEBUG"
echo "================================================================================"
echo ""

# Activate virtual environment if available
if [ -n "$VIRTUAL_ENV" ]; then
    echo "Using virtual environment: $VIRTUAL_ENV"
elif [ -f "${HOME}/venv/qlc-dev/bin/activate" ]; then
    echo "Activating qlc-dev virtual environment..."
    source "${HOME}/venv/qlc-dev/bin/activate"
else
    echo "Warning: No virtual environment detected"
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract station locations if requested
if [ "$EXTRACT_STATIONS" = true ]; then
    echo ""
    echo "================================================================================"
    echo "STEP 1: EXTRACTING STATION LOCATIONS"
    echo "================================================================================"
    echo ""
    
    EXTRACT_CMD="python3 ${SCRIPT_DIR}/qlc_extract_brazil_stations.py"
    EXTRACT_CMD="$EXTRACT_CMD --network $NETWORK"
    EXTRACT_CMD="$EXTRACT_CMD --source \"$SOURCE_DIR\""
    EXTRACT_CMD="$EXTRACT_CMD --output \"${CONFIG_DIR}/station_locations\""
    
    if [ "$DEBUG" = true ]; then
        EXTRACT_CMD="$EXTRACT_CMD --debug"
    fi
    
    echo "Running: $EXTRACT_CMD"
    echo ""
    
    eval $EXTRACT_CMD
    
    if [ $? -ne 0 ]; then
        echo "Error: Station extraction failed"
        exit 1
    fi
    
    echo ""
    echo "Station extraction completed successfully!"
    echo ""
fi

# Convert data to NetCDF
echo ""
echo "================================================================================"
echo "STEP 2: CONVERTING DATA TO NETCDF"
echo "================================================================================"
echo ""

CONVERT_CMD="qlc-convert-brazil-data"
CONVERT_CMD="$CONVERT_CMD --network $NETWORK"
CONVERT_CMD="$CONVERT_CMD --source \"$SOURCE_DIR\""
CONVERT_CMD="$CONVERT_CMD --output \"$OUTPUT_DIR\""
CONVERT_CMD="$CONVERT_CMD --config \"$CONFIG_DIR\""
CONVERT_CMD="$CONVERT_CMD --version $VERSION"
CONVERT_CMD="$CONVERT_CMD --format $FORMAT"

if [ -n "$YEARS" ]; then
    CONVERT_CMD="$CONVERT_CMD --years $YEARS"
fi

if [ "$FORCE" = true ]; then
    CONVERT_CMD="$CONVERT_CMD --force"
fi

if [ "$DEBUG" = true ]; then
    CONVERT_CMD="$CONVERT_CMD --debug"
fi

echo "Running: $CONVERT_CMD"
echo ""

eval $CONVERT_CMD

if [ $? -ne 0 ]; then
    echo "Error: Data conversion failed"
    exit 1
fi

echo ""
echo "================================================================================"
echo "CONVERSION COMPLETED SUCCESSFULLY"
echo "================================================================================"
echo ""
echo "Output location: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Verify NetCDF files in output directories"
echo "  2. Check station location files in ${CONFIG_DIR}/station_locations/"
echo "  3. Update QLC workflow configurations if needed"
echo "  4. Test with qlc-py using Brazilian data"
echo ""
echo "For more information, see:"
echo "  https://docs.researchconcepts.io/qlc/latest/"
echo ""

