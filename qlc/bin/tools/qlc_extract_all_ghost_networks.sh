#!/bin/bash

#SBATCH --job-name=ghost_extract
#SBATCH --time=24:00:00
#SBATCH --mem=64GB
#SBATCH --cpus-per-task=8
#SBATCH --output=ghost_extract_%j.log
#SBATCH --error=ghost_extract_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=$USER@ecmwf.int

# ============================================================================
# QLC Extract All GHOST Networks
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/user-guide/variable-system/
#
# Description:
#   Batch processor for extracting data from all GHOST (Globally Harmonised
#   Observations in Space and Time) networks. Automates the extraction of
#   observation data across multiple networks for QLC analysis.
#   This tool is NOT part of the GHOST project.
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_extract_all_ghost_networks.sh
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
#==============================================================================
# GHOST Data Citation (REQUIRED when using GHOST data):
#   Bowdalo, D. R., Mozaffar, A., Witt, M. L. I., et al. (2024)
#   Globally Harmonised Observations in Space and Time (GHOST)
#   Earth System Science Data, 16, 4417-4441
#   https://doi.org/10.5194/essd-16-4417-2024
#   Data: https://zenodo.org/records/15075961
#
# GHOST Data License: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)
# Users must comply with GHOST data license terms when using the data.
#==============================================================================

umask 0022
SCRIPT="$0"
ARCH="`uname -m`"
myOS="`uname -s`"
HOST=`hostname -s`
CUSR="`echo $USER`"

#==============================================================================
# CONFIGURATION
#==============================================================================

# Zenodo configuration
ZENODO_RECORD="15075961"
ZENODO_URL="https://zenodo.org/records/${ZENODO_RECORD}"
ZENODO_GHOST="GHOST_data_${ZENODO_RECORD}"

# Directory configuration
VERSION="v_20251206"
QLC_DIR="$HOME/qlc"
ZIP_DIR="${QLC_DIR}/obs/data/src/GHOST/zip"
SOURCE_DIR="${QLC_DIR}/obs/data/src/GHOST/networks/${VERSION}"
TARGET_DIR="${QLC_DIR}/obs/data/ghost"
BIN_DIR="${QLC_DIR}/bin/tools"

# Extraction configuration
FREQUENCIES="hourly_instantaneous hourly daily monthly"
FREQUENCIES="hourly daily monthly"
#FREQUENCIES="hourly_instantaneous"

# Workflow control (which steps to run)
RUN_DOWNLOAD=false
RUN_UNZIP=false
RUN_EXTRACT=true    # Default: just extract (most common use case)
FORCE_MODE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --download-only)
            RUN_DOWNLOAD=true
            RUN_UNZIP=false
            RUN_EXTRACT=false
            shift
            ;;
        --unzip-only)
            RUN_DOWNLOAD=false
            RUN_UNZIP=true
            RUN_EXTRACT=false
            shift
            ;;
        --extract-only)
            RUN_DOWNLOAD=false
            RUN_UNZIP=false
            RUN_EXTRACT=true
            shift
            ;;
        --download-unzip)
            RUN_DOWNLOAD=true
            RUN_UNZIP=true
            RUN_EXTRACT=false
            shift
            ;;
        --all)
            RUN_DOWNLOAD=true
            RUN_UNZIP=true
            RUN_EXTRACT=true
            shift
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Workflow Control (choose one, default: --extract-only):"
            echo "  --download-only     Download from Zenodo only"
            echo "  --unzip-only        Extract ZIP files only"
            echo "  --extract-only      Extract GHOST networks only (default)"
            echo "  --download-unzip    Download and extract ZIP, skip network extraction"
            echo "  --all               Run all steps (download, unzip, extract)"
            echo ""
            echo "Processing Mode:"
            echo "  --force             Force overwrite existing files (default: UPDATE mode)"
            echo ""
            echo "Examples:"
            echo "  $0                           # Extract networks (default)"
            echo "  $0 --download-only           # Just download from Zenodo"
            echo "  $0 --unzip-only              # Just extract ZIP files"
            echo "  $0 --all                     # Complete workflow"
            echo "  $0 --extract-only --force    # Force re-extract all networks"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

#==============================================================================
# ENVIRONMENT SETUP
#==============================================================================

# Detect if running on HPC
if [[ -n "$SLURM_JOB_ID" ]]; then
    RUNNING_ON_HPC=true
    echo "Running on HPC (SLURM Job ID: $SLURM_JOB_ID)"
else
    RUNNING_ON_HPC=false
fi

# Load required modules (HPC only)
if [[ "$RUNNING_ON_HPC" == true ]] && command -v module &> /dev/null; then
    module load python3 2>/dev/null || true
    module load netcdf4 2>/dev/null || true
fi

# Activate QLC environment
if [ -f    $HOME/venv/qlc-dev/bin/activate ]; then
    source $HOME/venv/qlc-dev/bin/activate
elif [ -f  $HOME/venv/qlc/bin/activate ]; then
    source $HOME/venv/qlc/bin/activate
else
    echo "WARNING: QLC virtual environment not found"
fi

#==============================================================================
# MAIN EXECUTION
#==============================================================================

for FREQUENCY in $FREQUENCIES ; do

# Log file
LOG_FILE="${QLC_DIR}/log/qlc_ghost_extraction_$(date +%Y%m%d_%H%M%S)_${FREQUENCY}.log"
mkdir -p "${QLC_DIR}/log"

echo "========================================================================"               | tee "$LOG_FILE"
echo "Start $SCRIPT at $(date)"                                                               | tee -a "$LOG_FILE"
echo "GHOST Network Extraction - ARCH: ${ARCH} | OS: ${myOS} | HOST: ${HOST} | USER: ${CUSR}" | tee -a "$LOG_FILE"
if [[ "$RUNNING_ON_HPC" == true ]]; then
    echo "Running mode: HPC Batch (SLURM Job ID: $SLURM_JOB_ID)"                              | tee -a "$LOG_FILE"
else
    echo "Running mode: Interactive (Mac/Linux)"                                              | tee -a "$LOG_FILE"
fi
echo "========================================================================"               | tee -a "$LOG_FILE"
echo "GHOST Network Extraction Log - $(date)"                                                 | tee -a "$LOG_FILE"
echo "Source: ${SOURCE_DIR}"                                                                  | tee -a "$LOG_FILE"
echo "Version: ${VERSION}"                                                                    | tee -a "$LOG_FILE"
echo "Frequency: ${FREQUENCY}"                                                                | tee -a "$LOG_FILE"
echo "Workflow: Download=${RUN_DOWNLOAD} | Unzip=${RUN_UNZIP} | Extract=${RUN_EXTRACT}"       | tee -a "$LOG_FILE"
if [[ "$FORCE_MODE" == true ]]; then
    echo "Mode: FORCE (will overwrite existing files)"                                        | tee -a "$LOG_FILE"
else
    echo "Mode: UPDATE (will skip existing files)"                                            | tee -a "$LOG_FILE"
fi
echo "========================================================================"               | tee -a "$LOG_FILE"

#==============================================================================
# STEP 1: DOWNLOAD FROM ZENODO (OPTIONAL)
#==============================================================================

if [ "$RUN_DOWNLOAD" = true ]; then
    echo ""                                                                                 | tee -a "$LOG_FILE"
    echo "========================================================================"         | tee -a "$LOG_FILE"
    echo "STEP 1: Downloading GHOST data from Zenodo"                                       | tee -a "$LOG_FILE"
    echo "========================================================================"         | tee -a "$LOG_FILE"
    echo "Record: ${ZENODO_RECORD}"                                                         | tee -a "$LOG_FILE"
    echo "URL: ${ZENODO_URL}"                                                               | tee -a "$LOG_FILE"
    echo ""                                                                                 | tee -a "$LOG_FILE"
    

    mkdir -p "${ZIP_DIR}"
    cd "${ZIP_DIR}"
    
    # Download all files from Zenodo record
    # Note: You need to add the actual download URLs from the Zenodo page
    echo "NOTICE: Automatic Zenodo download requires individual file URLs"                  | tee -a "$LOG_FILE"
    echo "Please download manually from: ${ZENODO_URL}"                                     | tee -a "$LOG_FILE"
    echo "Save to: ${ZIP_DIR}/${ZENODO_GHOST}"                                              | tee -a "$LOG_FILE"
    echo ""                                                                                 | tee -a "$LOG_FILE"
    echo "For automated download, add file URLs below:"                                     | tee -a "$LOG_FILE"
    echo "Example:"                                                                         | tee -a "$LOG_FILE"
    echo "  wget https://zenodo.org/records/15075961/files/Networks.zip -O Networks.zip"    | tee -a "$LOG_FILE"
    echo "  # or"                                                                           | tee -a "$LOG_FILE"
    echo "  curl -L -o Networks.zip https://zenodo.org/records/15075961/files/Networks.zip" | tee -a "$LOG_FILE"
    echo "  curl -L -o Networks.zip https://zenodo.org/records/15075961/files/Networks.zip" | tee -a "$LOG_FILE"
    echo ""                                                                                 | tee -a "$LOG_FILE"
else
    echo ""                                                                                 | tee -a "$LOG_FILE"
    echo "STEP 1: Download from Zenodo - SKIPPED"                                           | tee -a "$LOG_FILE"
    echo "Using existing data"                                                              | tee -a "$LOG_FILE"
    echo ""                                                                                 | tee -a "$LOG_FILE"
fi

#==============================================================================
# STEP 2: EXTRACT ZIP ARCHIVE (OPTIONAL)
#==============================================================================

if [ "$RUN_UNZIP" = true ]; then
    echo ""                                                                         | tee -a "$LOG_FILE"
    echo "========================================================================" | tee -a "$LOG_FILE"
    echo "STEP 2: Extracting ZIP archives"                                          | tee -a "$LOG_FILE"
    echo "========================================================================" | tee -a "$LOG_FILE"
    
    mkdir -p "${SOURCE_DIR}"
    cd "${ZIP_DIR}"
    
    # Find main GHOST zip file
    MAIN_ZIP="${ZENODO_GHOST}.zip"
    
    if [ ! -f "$MAIN_ZIP" ]; then
        echo "ERROR: Main GHOST zip file not found: ${ZIP_DIR}/${MAIN_ZIP}"     | tee -a "$LOG_FILE"
        echo "Please download GHOST data first from:"                           | tee -a "$LOG_FILE"
        echo "  ${ZENODO_URL}"                                                  | tee -a "$LOG_FILE"
        echo "Save as: ${ZIP_DIR}/${MAIN_ZIP}"                                  | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Step 2a: Extract main ZIP (contains network-specific ZIP files)
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "Step 2a: Extracting main GHOST archive..."                            | tee -a "$LOG_FILE"
    echo "  File: ${MAIN_ZIP}"                                                  | tee -a "$LOG_FILE"
    
    TEMP_EXTRACT="${ZIP_DIR}/temp_extract"
    mkdir -p "${TEMP_EXTRACT}"
    
    unzip -q "${MAIN_ZIP}" -d "${TEMP_EXTRACT}" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        echo "  ✓ SUCCESS: Extracted main archive"                              | tee -a "$LOG_FILE"
    else
        echo "  ✗ FAILED: Could not extract main archive"                       | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Step 2b: Extract individual network ZIP files
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "Step 2b: Extracting individual network archives..."                   | tee -a "$LOG_FILE"
    
    # Find all network ZIP files in the extracted content
    NETWORK_ZIPS=$(find "${TEMP_EXTRACT}" -name "*.zip" -type f 2>/dev/null)
    
    if [ -z "$NETWORK_ZIPS" ]; then
        echo "  WARNING: No network ZIP files found in main archive"            | tee -a "$LOG_FILE"
        echo "  Checking for direct network directories..."                     | tee -a "$LOG_FILE"
        
        # Maybe the main ZIP already contains the directory structure
        # Move extracted content to SOURCE_DIR
        if [ -d "${TEMP_EXTRACT}/Networks" ]; then
            mv "${TEMP_EXTRACT}/Networks"/* "${SOURCE_DIR}/" 2>/dev/null || true
            echo "  ✓ Found Networks directory, moved to ${SOURCE_DIR}"         | tee -a "$LOG_FILE"
        else
            mv "${TEMP_EXTRACT}"/* "${SOURCE_DIR}/" 2>/dev/null || true
            echo "  ✓ Moved extracted content to ${SOURCE_DIR}"                 | tee -a "$LOG_FILE"
        fi
    else
        # Extract each network ZIP file
        network_count=0
        for network_zip in $NETWORK_ZIPS; do
            network_name=$(basename "${network_zip}" .zip)
            echo "  Extracting network: ${network_name}"                        | tee -a "$LOG_FILE"
            
            unzip -q "${network_zip}" -d "${SOURCE_DIR}" 2>&1 | tee -a "$LOG_FILE"
            
            if [ $? -eq 0 ]; then
                echo "    ✓ SUCCESS: ${network_name}"                           | tee -a "$LOG_FILE"
                ((network_count++))
            else
                echo "    ✗ FAILED: ${network_name}"                            | tee -a "$LOG_FILE"
            fi
        done
        
        echo ""                                                                 | tee -a "$LOG_FILE"
        echo "  Extracted ${network_count} network archives"                    | tee -a "$LOG_FILE"
    fi
    
    # Cleanup temp directory
    rm -rf "${TEMP_EXTRACT}"
    
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "Final data location: ${SOURCE_DIR}"                                   | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "Available networks:"                                                  | tee -a "$LOG_FILE"
    ls -1 "${SOURCE_DIR}" 2>/dev/null | head -20                       v        | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
    
else
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "STEP 2: Extract ZIP archives - SKIPPED"                               | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
fi

#==============================================================================
# STEP 3: EXTRACT GHOST NETWORKS TO QLC FORMAT
#==============================================================================

if [ "$RUN_EXTRACT" = true ]; then

echo ""                                                                         | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "STEP 3: Extracting GHOST Networks to QLC Format"                          | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo ""                                                                         | tee -a "$LOG_FILE"

# Priority networks
PRIORITY_NETWORKS=(
    "GHOST"                 # Main harmonized network (200+ variables) - CRITICAL!
    "US_EPA_AQS"            # US EPA Air Quality
    "US_EPA_CASTNET"        # US CASTNET
    "CANADA_NAPS"           # Canadian NAPS
    "UK_AIR"                # UK AIR
    "EEA"                   # European Airbase
)

# All EBAS networks (combine into ghost-ebas)
EBAS_NETWORKS=(
    "EBAS-EUCAARI"
    "EBAS-EUSAAR"
    "EBAS-GUAN"
    "EBAS-HELCOM"
    "EBAS-IMPACTS"
    "EBAS-IMPROVE"
    "EBAS-Independent"
    "EBAS-NILU"
    "EBAS-NOAA_ESRL"
    "EBAS-OECD"
    "EBAS-RI_URBANS"
    "EBAS-WMO_WDCA"
)

# Additional networks
ADDITIONAL_NETWORKS=(
    "US_NADP_AIRMoN"
    "US_NADP_MDN"
    "US_NADP_NTN"
    "AERONET_v3_lev1.5"
    "AERONET_v3_lev2.0"
    "INDAAF"
    "WMO_WDCPC"
)

# Function to extract network
extract_network() {
    local network=$1
    local desc=$2
    
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "========================================"                             | tee -a "$LOG_FILE"
    echo "Extracting: ${network}"                                               | tee -a "$LOG_FILE"
    echo "Description: ${desc}"                                                 | tee -a "$LOG_FILE"
    echo "Time: $(date)"                                                        | tee -a "$LOG_FILE"
    echo "========================================"                             | tee -a "$LOG_FILE"
    
    # Build command with --force if enabled
    CMD="python3 ${BIN_DIR}/qlc_extract_ghost_data.py \
        --source ${SOURCE_DIR} \
        --network ${network} \
        --frequencies ${FREQUENCY} \
        --version ${VERSION} \
        --verbose"
    
    if [[ "$FORCE_MODE" == true ]]; then
        CMD="$CMD --force"
    fi
    
    eval "$CMD" 2>&1                                                            | tee -a "$LOG_FILE"
    
    local status=$?
    if [ $status -eq 0 ]; then
        echo "✓ SUCCESS: ${network}"                                            | tee -a "$LOG_FILE"
    else
        echo "✗ FAILED: ${network} (exit code: $status)"                        | tee -a "$LOG_FILE"
    fi
    
    # Show size
    local qlc_name=$(python3 -c "
mapping = {
    'GHOST': 'ghost_harmonized',
    'US_EPA_AQS': 'aqs',
    'US_EPA_CASTNET': 'castnet',
    'CANADA_NAPS': 'naps',
    'UK_AIR': 'uk_air',
    'EEA': 'airbase',
    'US_NADP_AIRMoN': 'nadp_airmon',
    'US_NADP_MDN': 'nadp_mdn',
    'US_NADP_NTN': 'nadp_ntn',
    'AERONET_v3_lev1.5': 'aeronet_lev15',
    'AERONET_v3_lev2.0': 'aeronet_lev20',
    'INDAAF': 'indaaf',
    'WMO_WDCPC': 'wmo_wdcpc',
}
print(mapping.get('${network}', 'ebas'))
")
    
    if [ -d "${TARGET_DIR}/${qlc_name}/${VERSION}" ]; then
        local size=$(du -sh "${TARGET_DIR}/${qlc_name}/${VERSION}" 2>/dev/null  | cut -f1)
        echo "  Size: ${size}"                                                  | tee -a "$LOG_FILE"
    fi
    
    return $status
}

# Extract priority networks first
echo ""                                                                         | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "PHASE 1: Priority Networks (Essential for testing)"                       | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"

success_count=0
fail_count=0

for network in "${PRIORITY_NETWORKS[@]}"; do
    if extract_network "${network}" "Priority network"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
    sleep 2  # Brief pause between extractions
done

# Extract EBAS networks
echo ""                                                                         | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "PHASE 2: EBAS Networks (European Monitoring)"                             | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"

for network in "${EBAS_NETWORKS[@]}"; do
    if extract_network "${network}" "EBAS sub-network"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
    sleep 1
done

# Extract additional networks
if [ ${#ADDITIONAL_NETWORKS[@]} -gt 0 ]; then
    echo ""                                                                         | tee -a "$LOG_FILE"
    echo "========================================================================" | tee -a "$LOG_FILE"
    echo "PHASE 3: Additional Networks"                                             | tee -a "$LOG_FILE"
    echo "========================================================================" | tee -a "$LOG_FILE"
    
    for network in "${ADDITIONAL_NETWORKS[@]}"; do
        if extract_network "${network}" "Additional network"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        sleep 1
    done
fi

# Summary for this frequency
echo ""                                                                         | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "EXTRACTION COMPLETE FOR FREQUENCY: ${FREQUENCY}"                          | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "Success: ${success_count}"                                                | tee -a "$LOG_FILE"
echo "Failed: ${fail_count}"                                                    | tee -a "$LOG_FILE"
echo "Log file: ${LOG_FILE}"                                                    | tee -a "$LOG_FILE"
echo ""                                                                         | tee -a "$LOG_FILE"

else
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "STEP 3: Extract GHOST Networks - SKIPPED"                             | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
fi # RUN_EXTRACT

done # FREQUENCY loop

#==============================================================================
# FINAL SUMMARY
#==============================================================================

echo ""                                                                         | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "WORKFLOW COMPLETE"                                                        | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"
echo "Steps completed:"                                                         | tee -a "$LOG_FILE"
if [ "$RUN_DOWNLOAD" = true ]; then
    echo "  ✓ Download from Zenodo"                                             | tee -a "$LOG_FILE"
fi
if [ "$RUN_UNZIP" = true ]; then
    echo "  ✓ Extract ZIP archives"                                             | tee -a "$LOG_FILE"
fi
if [ "$RUN_EXTRACT" = true ]; then
    echo "  ✓ Extract GHOST networks"                                           | tee -a "$LOG_FILE"
fi
echo ""                                                                         | tee -a "$LOG_FILE"

# Show disk usage if extraction was run
if [ "$RUN_EXTRACT" = true ]; then
    echo "Extracted data location: ${TARGET_DIR}"                               | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "Disk usage by network:"                                               | tee -a "$LOG_FILE"
    du -sh ${TARGET_DIR}/* 2>/dev/null                                          | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "Total disk usage:"                                                    | tee -a "$LOG_FILE"
    du -sh ${TARGET_DIR}/ 2>/dev/null                                           | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
fi

echo "Next steps:"                                                              | tee -a "$LOG_FILE"
if [ "$RUN_DOWNLOAD" = true ] && [ "$RUN_UNZIP" = false ] && [ "$RUN_EXTRACT" = false ]; then
    echo "  1. Extract ZIP files:"                                              | tee -a "$LOG_FILE"
    echo "     $0 --unzip-only"                                                 | tee -a "$LOG_FILE"
elif [ "$RUN_UNZIP" = true ] && [ "$RUN_EXTRACT" = false ]; then
    echo "  1. Extract GHOST networks:"                                         | tee -a "$LOG_FILE"
    echo "     $0 --extract-only"                                               | tee -a "$LOG_FILE"
elif [ "$RUN_EXTRACT" = true ]; then
    echo "  1. Extract station locations:"                                      | tee -a "$LOG_FILE"
    if [[ "$RUNNING_ON_HPC" == true ]]; then
        echo "     sbatch ${BIN_DIR}/qlc_extract_ghost_stations.sh"             | tee -a "$LOG_FILE"
    else
        echo "       bash ${BIN_DIR}/qlc_extract_ghost_stations.sh"             | tee -a "$LOG_FILE"
    fi
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "  2. Test with QLC:"                                                  | tee -a "$LOG_FILE"
    echo "     qlc exp1 exp2 2008-01-01 2008-01-31 aifs --observation=ghost_harmonized --region=EU" | tee -a "$LOG_FILE"
    echo ""                                                                     | tee -a "$LOG_FILE"
    echo "  3. Validate variables:"                                             | tee -a "$LOG_FILE"
    echo "     qlc-vars search pm2.5"                                           | tee -a "$LOG_FILE"
fi
echo "========================================================================" | tee -a "$LOG_FILE"
echo "END   $SCRIPT at $(date)"                                                 | tee -a "$LOG_FILE"
echo "========================================================================" | tee -a "$LOG_FILE"

exit 0
