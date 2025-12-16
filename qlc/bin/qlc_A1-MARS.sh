#!/bin/bash -e

# ============================================================================
# QLC A1-MARS: MARS Data Retrieval
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   This script executes pre-generated MARS request files created by the 
#   Python wrapper. Python generates all MARS requests upfront for maximum 
#   speed and simplicity.
#
# Usage:
#   Called automatically by qlc_main.sh - Do not call directly
#   For help: qlc -h
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Retrieve grib data from MARS archive using pre-generated requests"
 log  "----------------------------------------------------------------------------------------"

# Log MARS request generation details (from Python wrapper)
if [ -n "${QLC_MARS_VARIABLES_DETAIL:-}" ]; then
    log "MARS variables: ${QLC_MARS_VARIABLES_DETAIL}"
fi
if [ -n "${QLC_WORKFLOW_OVERRIDES:-}" ]; then
    log "Workflow overrides:"
    # Parse semicolon-separated KEY=VALUE pairs
    IFS=';' read -ra OVERRIDES <<< "$QLC_WORKFLOW_OVERRIDES"
    for override in "${OVERRIDES[@]}"; do
        log "  ${override}"
    done
fi
if [ -n "${QLC_TOTAL_MARS_REQUESTS:-}" ]; then
    log "Generated ${QLC_TOTAL_MARS_REQUESTS} MARS request file(s)"
fi

# Parse command line arguments for experiments, dates, and config
parse_qlc_arguments "$@" || exit 1

# Early return if no experiments specified (obs-only mode)
# A1-MARS only retrieves experiment data, not observations
if [ ${#experiments[@]} -eq 0 ]; then
    log "No experiments specified - skipping MARS retrieval (obs-only mode)"
    log "End ${SCRIPT} at `date`"
    log "________________________________________________________________________________________"
    exit 0
fi

# Track whether any MARS jobs are submitted
# This is needed for batch dependency management in qlc_batch.sh
total_submitted_jobs=0

# Check if Python wrapper prepared MARS requests
if [ -z "$QLC_MARS_REQUESTS_READY" ]; then
    log "ERROR: MARS requests not prepared by Python wrapper"
    log "ERROR: QLC_MARS_REQUESTS_READY not set"
    log "ERROR: Python wrapper should generate MARS requests before calling bash scripts"
    exit 1
fi

log "Using pre-generated MARS requests from Python wrapper"
log "Variables: ${QLC_VARIABLES:-from workflow config}"

# Process each experiment
for exp in "${experiments[@]}"; do
    log "Processing experiment: $exp"
    
    # Create experiment directory if not existent
    mkdir -p "$MARS_RETRIEVAL_DIRECTORY/$exp"
    
    # MARS requests are in the experiment directory
    exp_dir="$MARS_RETRIEVAL_DIRECTORY/$exp"
    
    # Clean up stale .id files for completed jobs (where .flag file exists)
    # This prevents duplicate job IDs in batch dependency lists
    for id_file in "$exp_dir"/data_retrieved_*.id; do
        [ -f "$id_file" ] || continue  # Skip if no .id files exist
        flag_file="${id_file%.id}.flag"
        if [ -f "$flag_file" ]; then
            log "Removing completed job ID file: $(basename "$id_file")"
            rm -f "$id_file"
        fi
    done
    
    # Find MARS requests for this experiment
    exp_requests=$(ls -1 "$exp_dir"/mars_${exp}_*.req 2>/dev/null || echo "")
    
    if [ -z "$exp_requests" ]; then
        log "WARNING: No MARS request files found for experiment: $exp in $exp_dir"
        continue
    fi
    
    request_count=$(echo "$exp_requests" | wc -l | tr -d ' ')
    log "Found $request_count MARS request file(s) for experiment: $exp"
    
    # Execute each MARS request
    for request_file in $exp_requests; do
        # Extract variable name from filename (mars_EXPID_LEVTYPE_VARNAME.req)
        # Example: mars_b2ro_pl_NH3.req -> pl_NH3
        basename=$(basename "$request_file" .req)
        # Remove "mars_EXPID_" prefix to get "LEVTYPE_VARNAME"
        var_name=${basename#mars_${exp}_}
        
        # Convert dates to compact format (consistent with other scripts)
        sDate="${sDat//[-:]/}"
        eDate="${eDat//[-:]/}"
        mDate="$sDate-$eDate"
        
        # Expected output file
        output_prefix="${exp}_${mDate}"
        target="$MARS_RETRIEVAL_DIRECTORY/$exp/${output_prefix}_${var_name}.grb"
        
        # Flag files for tracking (use compact date format to match Python wrapper)
        flag_base="$MARS_RETRIEVAL_DIRECTORY/$exp/data_retrieved_${exp}_${mDate}_${var_name}"
        completion_flag="${flag_base}.flag"
        download_flag="${flag_base}.download"
        
        # Check if already downloaded
        if [ -f "$completion_flag" ]; then
            log "Variable $var_name: already retrieved (skipping)"
            continue
        fi
        
        if [ -f "$download_flag" ]; then
            log "Variable $var_name: download in progress (skipping)"
            continue
        fi
        
        # Process MARS retrieval
        # Check if request file was just created or already existed
        # Simple approach: use find to check if file modified in last 2 minutes
        if find "$request_file" -mmin -2 2>/dev/null | grep -q .; then
            log "MARS request created: $request_file"
        else
            log "MARS request found: $request_file"
        fi
        log "  Target: $target"
        
        # Always generate batch script with complete flag management logic
        batch_script="${request_file%.req}.sh"
        cat > "$batch_script" << EOF
#!/bin/bash
#SBATCH --job-name=mars_${exp}_${var_name}
#SBATCH --output=log-mars_${exp}_${var_name}-%J.out
#SBATCH --error=err-mars_${exp}_${var_name}-%J.out
#SBATCH --mail-type=FAIL

# MARS Data Retrieval for ${var_name}
# Experiment: ${exp}
# Date range: ${sDat} to ${eDat}
# Generated: \$(date)

echo "================================================================"
echo "MARS Retrieval: ${var_name}"
echo "Experiment: ${exp}"
echo "Started: \$(date)"
echo "================================================================"

# Create download flag
touch "$download_flag"

# Execute MARS (full path already in request file)
if mars < $request_file; then
    # Verify target file exists
    if [ -f "$target" ]; then
        echo "Target file created: $target"
        ls -lh "$target"
        
        # Remove download flag and create completion flag
        rm -f "$download_flag"
        touch "$completion_flag"
        echo "Created completion flag: $completion_flag"
    else
        echo "ERROR: MARS completed but target file not found: $target"
        rm -f "$download_flag"
        exit 1
    fi
else
    echo "ERROR: MARS retrieval failed"
    rm -f "$download_flag"
    exit 1
fi

echo "================================================================"
echo "MARS Retrieval completed: \$(date)"
echo "================================================================"
EOF
        chmod +x "$batch_script"
        
        # Submit to batch queue if sbatch is available (HPC environment)
        if command -v sbatch >/dev/null 2>&1; then
            log "Submitting to batch queue: sbatch $batch_script"
            
            # Clean up old job ID file if it exists (from previous failed/cancelled runs)
            job_id_file="${flag_base}.id"
            if [ -f "$job_id_file" ]; then
                old_job_id=$(cat "$job_id_file" 2>/dev/null || echo "unknown")
                log "Removing stale job ID file: $job_id_file (old job: $old_job_id)"
                rm -f "$job_id_file"
            fi
            
            if sbatch_output=$(sbatch "$batch_script" 2>&1); then
                job_id=$(echo "$sbatch_output" | awk '{print $NF}')
                log "Batch job submitted: $job_id"
                # Store job ID using consistent naming with flag files (for sqlc dependency tracking)
                echo "$job_id" > "$job_id_file"
                log "Job ID stored: $job_id_file"
                # Track successful submission
                total_submitted_jobs=$((total_submitted_jobs + 1))
            else
                log "ERROR: Failed to submit batch job: $sbatch_output"
                exit 1
            fi
        else
            # No sbatch - provide instructions (macOS or non-HPC environment)
            log "Batch script ready: $batch_script"
            log "Transfer to HPC and submit: sbatch $(basename $batch_script)"
        fi
    done
    
    log "Completed processing for experiment: $exp"
done

log "----------------------------------------------------------------------------------------"
log "Summary: $total_submitted_jobs MARS job(s) submitted"

# Signal to qlc_main.sh and qlc_batch.sh whether any jobs were submitted
# This is critical for batch dependency management
if [ $total_submitted_jobs -eq 0 ]; then
    log "========================================================================================"
    log "No MARS jobs submitted - all data already present"
    log "========================================================================================"
    log "All required data files have already been retrieved"
    log "Skipping MARS retrieval and ready for processing"
    log "========================================================================================"
    # Export flag for batch system to detect zero-job scenario
    export QLC_A1_MARS_NO_JOBS=1
else
    log "MARS jobs submitted successfully - processing will start after completion"
fi

log "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

