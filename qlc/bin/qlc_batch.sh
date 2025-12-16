#!/bin/bash -e
umask 0022

# ============================================================================
# QLC Batch Job Submission for HPC Systems
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Submits QLC workflow as batch jobs to HPC systems (SLURM, PBS, LSF).
#   Automatically detects batch system and generates appropriate job scripts.
#   Supports automatic two-job workflow (data retrieval + processing) with
#   intelligent dependency management.
#
# Entry Point:
#   This script is called via the 'sqlc' command (Python entry point)
#   Users run: sqlc <exp1> [exp2 ...] <start_date> <end_date> <workflow>
#   Example:   sqlc 9191 0001 2025-11-01 2025-11-03 aifs
#
# Features:
#   - Automatic batch system detection (SLURM, PBS, LSF)
#   - Two-stage job workflow with dependencies
#   - Parallel MARS data retrieval
#   - Intelligent job status checking
#   - Same argument syntax as interactive 'qlc' command
#
# Usage:
#   Called automatically via 'sqlc' command - Do not call directly
#   For help: sqlc -h
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

SCRIPT="$0"

# --- Start: Environment Setup ---
# Find the Python executable that runs this tool.
# This ensures that any executables installed in the same environment (like pyferret) are found.
# Fallback to 'python3' if 'qlc' is not in the path (e.g., during development).
PYTHON_CMD=$(which python3)
if command -v qlc >/dev/null 2>&1; then
    QLC_PATH=$(which qlc)
    PYTHON_CMD=$(head -n 1 "$QLC_PATH" | sed 's/^#!//')
fi

# Get the directory of the Python executable.
PYTHON_BIN_DIR=$(dirname "$PYTHON_CMD")

# Prepend this directory to the PATH for this script and all subscripts.
export PATH="$PYTHON_BIN_DIR:$PATH"

# --- Start: QLC Environment Detection and Activation ---
# Detect and activate QLC virtual environment with HPC module support
# This replaces manual environment setup and ensures consistent behavior

# Determine environment mode from arguments or environment
QLC_MODE="auto"
if [[ "$*" =~ --dev ]] || [[ "$*" =~ -dev ]]; then
    QLC_MODE="dev"
elif [[ "$*" =~ --prod ]] || [[ "$*" =~ -prod ]]; then
    QLC_MODE="prod"
elif [[ "$*" =~ --version=([0-9.]+) ]]; then
    QLC_MODE="${BASH_REMATCH[1]}"
elif [[ "$*" =~ --version\ ([0-9.]+) ]]; then
    QLC_MODE="${BASH_REMATCH[1]}"
fi

# Source common functions for environment setup
# Try multiple locations for the common functions file
COMMON_FUNCTIONS=""

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"

# Try to find the common functions in standard locations
for location in \
    "${QLC_HOME:-$HOME/qlc}/bin/qlc_common_functions.sh" \
    "$HOME/qlc/bin/qlc_common_functions.sh"; do
    if [ -f "$location" ]; then
        COMMON_FUNCTIONS="$location"
        break
    fi
done

if [ -n "$COMMON_FUNCTIONS" ]; then
    source "$COMMON_FUNCTIONS"
    
    # Log start banner first
    log "________________________________________________________________________________________"
    log "Start $SCRIPT (SLURM Batch Submission) at $(date)"
    log "----------------------------------------------------------------------------------------"
    
    # Setup complete QLC environment
    if setup_qlc_complete "$QLC_MODE" "true"; then
        log "[QLC Batch]" "Environment setup completed successfully"
    else
        log "[QLC Batch]" "Warning: Environment setup had issues, continuing..."
    fi
else
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC Batch] ERROR: Common functions not found, cannot continue"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC Batch] Searched locations:"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC Batch]   - ${QLC_HOME:-$HOME/qlc}/bin/qlc_common_functions.sh"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC Batch]   - $HOME/qlc/bin/qlc_common_functions.sh"
    exit 1
fi
# --- End: QLC Environment Detection and Activation ---
# --- End: Environment Setup ---

# --- Start: QLC Runtime Detection ---
# Detect QLC runtime directory with priority:
# 1. QLC_HOME environment variable (explicit override)
# 2. Auto-detection for development (checks VIRTUAL_ENV path for qlc-dev)
# 3. Default to ~/qlc (production with venv)
if [ -n "$QLC_HOME" ]; then
  log "[QLC]" "Using explicit QLC_HOME: $QLC_HOME"
  QLCHOME="$QLC_HOME"
elif [ -n "$VIRTUAL_ENV" ] && [[ "$VIRTUAL_ENV" == *"qlc-dev"* ]]; then
  log "[QLC-DEV]" "Auto-detected development environment"
  QLCHOME="$HOME/qlc-dev-run"
else
  QLCHOME="$HOME/qlc"
fi

# Verify runtime exists
if [ ! -d "$QLCHOME" ]; then
  log "[QLC Batch]" "ERROR: QLC runtime directory not found: $QLCHOME"
  log "[QLC Batch]" "ERROR: Please run: qlc-install --mode test (or --mode dev)"
  exit 1
fi

# Export for subscripts
export QLCHOME
# --- End: QLC Runtime Detection ---

# ----------------------------------------------------------------------------------------
# Check if help is needed first (before loading config)
# ----------------------------------------------------------------------------------------
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "========================================================================================"
  echo "SQLC - QLC Batch Submission (HPC/SLURM)"
  echo "========================================================================================"
  echo ""
  echo "Usage:"
  echo "  sqlc <exp1> [exp2 ...] <start_date> <end_date> <workflow> [options]"
  echo ""
  echo "Arguments:"
  echo "  <exp1> [exp2 ...]  One or more experiment identifiers"
  echo "  <start_date>       Start date (YYYY-MM-DD)"
  echo "  <end_date>         End date (YYYY-MM-DD)"
  echo "  <workflow>         Workflow name: aifs, eac5, evaltools, mars, pyferret, qpy, test"
  echo ""
  echo "Common Options:"
  echo "  --obs-only         Analyze observations only"
  echo "  --mod-only         Analyze model results only"
  echo "  -class=xx          Override MARS class (e.g., -class=nl)"
  echo "  -vars=<spec>       Variable specification (e.g., -vars=\"go3,NH3,PM2.5\")"
  echo "  -region=<code>     Region override (e.g., -region=EU)"
  echo ""
  echo "Quick Examples:"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 test"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 test -obs-only -region=EU"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 test -class=nl,nl -vars=\"go3,nh3\""
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 test -class=nl,nl -param=210073,210203 -myvar=PM2p5,O3 -levtype=sfc,pl"
  echo ""
  echo "Variable Search:"
  echo "  qlc-vars search O3"
  echo "  qlc-vars info O3"
  echo ""
  echo "Check Job Status:"
  echo "  squeue -u \$USER"
  echo ""
  echo "View Results:"
  echo "  ls -lrth ~/qlc/Results        # GRIB data (MARS download)"
  echo "  ls -lrth ~/qlc/Analysis       # NetCDF processed data"
  echo "  ls -lrth ~/qlc/Plots          # Generated plots"
  echo "  ls -lrth ~/qlc/Presentations  # PDF reports"
  echo ""
  echo "For more information:"
  echo "  Quick Start    : ~/qlc/doc/QuickStart.md"
  echo "  Documentation  : https://docs.researchconcepts.io/qlc"
  echo "  Getting Started: https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/"
  echo ""
  echo "BETA RELEASE: Under development, requires further testing."
  echo "© 2018-2025 ResearchConcepts io GmbH. All Rights Reserved."
  echo "Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>"
  echo "========================================================================================"
  exit 0
fi

# ----------------------------------------------------------------------------------------
# Parse command line arguments dynamically to support variable number of experiments
# Format: sqlc exp1 [exp2 ...] startDate endDate [config]
# ----------------------------------------------------------------------------------------

# Function to check if argument is a date (matches YYYY-MM-DD pattern)
is_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# Parse arguments and extract options (like -class=)
# First pass: filter out options and build clean args array
args=()
class_option=""
for arg in "$@"; do
  if [[ "$arg" == -class=* ]]; then
    class_option="$arg"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Class override option: $class_option"
  else
    args+=("$arg")
  fi
done

num_args=${#args[@]}

# Determine if last argument is a config name (not a date)
if [ $num_args -ge 5 ] && ! is_date "${args[$((num_args-1))]}"; then
  # Last arg is config name
  config_arg="${args[$((num_args-1))]}"
  end_date="${args[$((num_args-2))]}"
  start_date="${args[$((num_args-3))]}"
  # Everything before start_date is experiments
  experiments=("${args[@]:0:$((num_args-3))}")
  USER_DIR="$config_arg"
elif [ $num_args -ge 4 ]; then
  # No config name, using default
  config_arg=""
  end_date="${args[$((num_args-1))]}"
  start_date="${args[$((num_args-2))]}"
  # Everything before start_date is experiments
  experiments=("${args[@]:0:$((num_args-2))}")
  USER_DIR="default"
else
  echo "Error: Insufficient arguments"
  echo "Usage: sqlc exp1 [exp2 ...] startDate endDate [config] [-class=xx|xx,yy,...]"
  echo "Run 'sqlc' without arguments for detailed help."
  exit 1
fi

# User specific configuration file
QLC_DIR="$QLCHOME"
CONFIG_DIR="$QLC_DIR/config/workflows/$USER_DIR"
CONFIG_FILE="$CONFIG_DIR/qlc_$USER_DIR.conf"

# Source the configuration file and automatically export all defined variables
# to make them available to any subscripts that are called.
set -a
. "$CONFIG_FILE"
set +a

# Source the common functions script to make the 'log' function available
. "$SCRIPTS_PATH/qlc_common_functions.sh"

 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "----------------------------------------------------------------------------------------"
 log  "Purpose: Submit QLC batch job to SLURM scheduler"
 log  "----------------------------------------------------------------------------------------"

# Validate dates
if ! is_date "$start_date" || ! is_date "$end_date"; then
  log "Error: Dates must be in YYYY-MM-DD format"
  log "Got start_date='$start_date', end_date='$end_date'"
  exit 1
fi

# Validate we have at least one experiment
if [ ${#experiments[@]} -eq 0 ]; then
  log "Error: At least one experiment must be specified"
  exit 1
fi

# Log parsed arguments
log "Parsed arguments for batch submission:"
log "  Experiments: ${experiments[*]} (${#experiments[@]} total)"
log "  Start date: $start_date"
log "  End date: $end_date"
log "  Config: ${config_arg:-default}"

# Provide guidance if no config specified
if [ -z "$config_arg" ]; then
  log ""
  log "========================================================================================"
  log "No workflow configuration specified"
  log "========================================================================================"
  log ""
  log "Quick examples:"
  log "  sqlc b2ro b2rn 2018-12-01 2018-12-21 mars      # retrieval only"
  log "  sqlc b2ro b2rn 2018-12-01 2018-12-21 test      # Test analysis"
  log "  sqlc b2ro b2rn 2018-12-01 2018-12-21 qpy       # Station analysis"
  log "  sqlc b2ro b2rn 2018-12-01 2018-12-21 eac5      # Production analysis"
  log ""
  log "For detailed help:"
  log "  Quick Start:   cat $HOME/qlc/doc/QuickStart.md"
  log "  Online Docs:   https://docs.researchconcepts.io/qlc/latest/"
  log "  Usage Guide:   https://docs.researchconcepts.io/qlc/latest/user-guide/usage/"
  log "========================================================================================"
  exit 0
fi

log "----------------------------------------------------------------------------------------"

# Build the command line to pass all arguments (experiments, dates, config, class_option)
all_args="${experiments[*]} $start_date $end_date"
[ -n "$config_arg" ] && all_args="$all_args $config_arg"
[ -n "$class_option" ] && all_args="$all_args $class_option"

# Determine if two-job workflow is needed
# If workflow contains both A1-MARS (data retrieval) and processing scripts,
# create two dependent jobs. Let qlc_main.sh handle the smart logic.
needs_two_jobs=false
data_already_complete=false

if [[ " ${SUBSCRIPT_NAMES[*]} " =~ " A1-MARS " ]] && [ ${#SUBSCRIPT_NAMES[@]} -gt 1 ]; then
  # Workflow has A1-MARS + processing scripts
  # Check if data is already complete (all .flag files exist)
  log "Workflow contains A1-MARS + processing scripts"
  log "Checking if MARS data is already complete..."
  
  # Get variables from Python wrapper (same logic as qlc_main.sh)
  load_variable_registry
  parse_variable_and_mars_options "$@"
  required_vars=()
  while IFS= read -r var; do
    required_vars+=("$var")
  done < <(get_required_mars_variables)
  
  # Convert dates to compact format
  sDate="${start_date//[-:]/}"
  eDate="${end_date//[-:]/}"
  mDate="$sDate-$eDate"
  
  # Check if all completion flags exist
  all_complete=true
  for exp in "${experiments[@]}"; do
    for var_name in "${required_vars[@]}"; do
      completion_flag="$MARS_RETRIEVAL_DIRECTORY/$exp/data_retrieved_${exp}_${mDate}_${var_name}.flag"
      if [ ! -f "$completion_flag" ]; then
        all_complete=false
        break 2
      fi
    done
  done
  
  if [ "$all_complete" = true ]; then
    log "All MARS data already present - using single-job workflow"
    data_already_complete=true
  else
    log "MARS data incomplete - using two-job workflow"
    log "  Job 1: Runs qlc (may submit MARS jobs, exits after A1-MARS)"
    log "  Job 2: Runs qlc again (depends on Job 1, processes data)"
    needs_two_jobs=true
  fi
else
  log "Single-job workflow (no A1-MARS in workflow)"
fi

# Generate batch script
if [ "$needs_two_jobs" = true ]; then
  # Two-job workflow: retrieval → processing
  jobid='${SLURM_JOB_ID}'
  
  # Create the processing job script (Job 2) - runs after MARS jobs complete (via SLURM dependency)
  cat > $QLC_DIR/run/qlc_processing.sh$$<<EOF
#!/bin/bash -e
#SBATCH --job-name=qlc_processing_${config_arg}
#SBATCH --output=log-qlc-processing-%J.out
#SBATCH --error=err-qlc-processing-%J.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=$USER@ecmwf.int
#SBATCH --export=ALL

# QLC Processing Job - starts after all MARS retrieval jobs complete
# SLURM dependency ensures this only runs when all MARS jobs finish successfully

echo "========================================================================================"
echo "QLC Processing Job Started: \$(date)"
echo "========================================================================================"
echo "Job ID: \$SLURM_JOB_ID"
echo "Node: \$SLURMD_NODENAME"
echo "Workflow: $config_arg"
echo " "

# Activate QLC venv
if [ -f "\$HOME/venv/qlc/bin/activate" ]; then
    source "\$HOME/venv/qlc/bin/activate"
    echo "Activated venv: \$HOME/venv/qlc"
else
    echo "Warning: venv not found at \$HOME/venv/qlc"
fi

# Source common functions for environment setup
if [ -f "\$HOME/qlc/bin/qlc_common_functions.sh" ]; then
    source "\$HOME/qlc/bin/qlc_common_functions.sh"
    setup_qlc_complete "auto" "true" || echo "Environment setup had warnings (continuing)"
fi

echo "========================================================================================"
echo "All MARS retrieval jobs completed successfully"
echo "Starting QLC processing: \$(date)"
echo "Command: qlc $all_args"
echo "========================================================================================"

set +e  # Disable exit-on-error for qlc command
qlc $all_args
qlc_exit_code=\$?
set -e  # Re-enable exit-on-error

if [ \$qlc_exit_code -eq 0 ]; then
    echo "========================================================================================"
    echo "QLC Processing Job Completed Successfully: \$(date)"
    echo "All processing tasks finished without errors"
    echo "========================================================================================"
else
    echo "========================================================================================"
    echo "QLC Processing Job Failed: \$(date)"
    echo "Exit code: \$qlc_exit_code"
    echo "========================================================================================"
    exit \$qlc_exit_code
fi
EOF
  
  # Create the data retrieval job script (Job 1) that submits Job 2 after completion
  cat > $QLC_DIR/run/qlc_batch.sh$$<<EOF
#!/bin/bash -e
#SBATCH --job-name=qlc_retrieval_${config_arg}
#SBATCH --output=log-qlc-retrieval-%J.out
#SBATCH --error=err-qlc-retrieval-%J.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=$USER@ecmwf.int
#SBATCH --export=ALL

# QLC Data Retrieval Job - submits MARS retrieval requests
# This job runs qlc_main.sh with A1-MARS script, which submits MARS jobs to the queue
# After submission, this job completes and hands over to the processing job

echo "========================================================================================"
echo "QLC Data Retrieval Job Started: \$(date)"
echo "========================================================================================"
echo "Job ID: \${jobid}"
echo "Node: \$SLURMD_NODENAME"
echo "Workflow: $config_arg"
echo "Purpose: Submit MARS retrieval jobs to the queue"
echo " "

# Activate QLC venv
if [ -f "\$HOME/venv/qlc/bin/activate" ]; then
    source "\$HOME/venv/qlc/bin/activate"
    echo "Activated venv: \$HOME/venv/qlc"
else
    echo "Warning: venv not found at \$HOME/venv/qlc"
fi

# Source common functions for environment setup
if [ -f "\$HOME/qlc/bin/qlc_common_functions.sh" ]; then
    source "\$HOME/qlc/bin/qlc_common_functions.sh"
    setup_qlc_complete "auto" "true" || echo "Environment setup had warnings (continuing)"
fi

echo "========================================================================================"
echo "Submitting MARS retrieval jobs..."
echo "Command: qlc $all_args"
echo "========================================================================================"

set +e  # Disable exit-on-error for qlc command
qlc $all_args
qlc_exit_code=\$?
set -e  # Re-enable exit-on-error

if [ \$qlc_exit_code -eq 0 ]; then
    echo "========================================================================================"
    echo "QLC Data Retrieval Job Completed Successfully: \$(date)"
    echo "========================================================================================"
    echo "Retrieval job ID: \${jobid}"
    
    # Check if A1-MARS was skipped because data was already present
    if [ "\${QLC_A1_MARS_SKIPPED}" == "1" ]; then
        echo "Status: MARS data was already present - all subscripts have been processed"
        echo " "
        echo "A1-MARS was skipped and remaining subscripts (B1-CONV, B2-PREP, etc.) completed"
        echo "No processing job needed - workflow is complete"
        echo "========================================================================================"
        exit 0
    fi
    
    # Check if A1-MARS ran but submitted zero jobs (all data already present)
    if [ "\${QLC_A1_MARS_NO_JOBS}" == "1" ]; then
        echo "Status: A1-MARS completed - no new MARS jobs needed (all data already present)"
        echo " "
        echo "All required MARS data files were already retrieved"
        echo "Submitting processing job immediately (no dependency needed)"
        echo "========================================================================================"
        
        # Submit processing job without dependencies
        if processing_output=\$(sbatch $QLC_DIR/run/qlc_processing.sh$$ 2>&1); then
            processing_job_id=\$(echo "\$processing_output" | awk '{print \$NF}')
            echo "Processing job submitted: \$processing_job_id"
            echo " "
            echo "Processing job will start immediately and run remaining subscripts"
            echo "(B1-CONV, B2-PREP, D1-ANAL, E1-ECOL, E2-EVAL, Z1-XPDF, etc.)"
            echo "========================================================================================"
            exit 0
        else
            echo "ERROR: Failed to submit processing job: \$processing_output"
            exit 1
        fi
    fi
    
    echo "Status: All MARS retrieval jobs have been submitted to the queue"
    echo " "
    
    # Collect all MARS job IDs from .id files (consistent with .flag/.download naming)
    # Note: .id files for completed jobs are cleaned up in qlc_A1-MARS.sh
    # Extract experiments from command line args (first N non-date, non-config args)
    exp_args=($all_args)
    exp_list=""
    for arg in "\${exp_args[@]}"; do
        # Skip dates (contain hyphens and numbers) and known config names
        if [[ "\$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\$ ]] || [[ "\$arg" == "test" ]] || [[ "\$arg" == "dev" ]]; then
            continue
        fi
        exp_list="\$exp_list \$arg"
    done
    
    echo "Experiments being processed: \$exp_list"
    
    mars_job_ids=""
    job_id_files=""
    # Only search in experiment directories being processed
    for exp in \$exp_list; do
        exp_dir="\$HOME/qlc/Results/\$exp"
        if [ -d "\$exp_dir" ]; then
            exp_id_files=\$(ls -1 "\$exp_dir"/data_retrieved_*.id 2>/dev/null || echo "")
            if [ -n "\$exp_id_files" ]; then
                job_id_files="\$job_id_files \$exp_id_files"
            fi
        fi
    done
    
    if [ -z "\$job_id_files" ]; then
        echo "WARNING: No MARS job ID files found in experiment directories"
        echo "Experiments searched: \$exp_list"
        echo "This may indicate no MARS jobs were submitted"
        echo "Submitting processing job without dependencies (will use flag checking)"
        dependency_arg=""
    else
        echo "Collecting MARS job IDs from .id files:"
        id_count=0
        for id_file in \$job_id_files; do
            job_id=\$(cat "\$id_file" 2>/dev/null | tr -d '[:space:]')
            if [ -n "\$job_id" ]; then
                id_count=\$((id_count + 1))
                if [ -z "\$mars_job_ids" ]; then
                    mars_job_ids="\$job_id"
                else
                    mars_job_ids="\${mars_job_ids}:\${job_id}"
                fi
                echo "  [\$id_count] \$(basename \$id_file): \$job_id"
            fi
        done
        
        if [ -n "\$mars_job_ids" ]; then
            echo " "
            echo "Total MARS jobs collected: \$id_count"
            echo "SLURM dependency string: afterok:\$mars_job_ids"
            dependency_arg="--dependency=afterok:\$mars_job_ids"
        else
            echo "WARNING: No valid MARS job IDs found in .id files"
            dependency_arg=""
        fi
    fi
    
    echo " "
    echo "Submitting dependent processing job..."
    if [ -n "\$dependency_arg" ]; then
        echo "Dependency: \$dependency_arg"
        if processing_output=\$(sbatch \$dependency_arg $QLC_DIR/run/qlc_processing.sh$$ 2>&1); then
            processing_job_id=\$(echo "\$processing_output" | awk '{print \$NF}')
            echo "Processing job submitted: \$processing_job_id"
        else
            echo "ERROR: Failed to submit processing job: \$processing_output"
            exit 1
        fi
    else
        echo "No dependency (processing job will check flags)"
        if processing_output=\$(sbatch $QLC_DIR/run/qlc_processing.sh$$ 2>&1); then
            processing_job_id=\$(echo "\$processing_output" | awk '{print \$NF}')
            echo "Processing job submitted: \$processing_job_id"
        else
            echo "ERROR: Failed to submit processing job: \$processing_output"
            exit 1
        fi
    fi
    
    echo " "
    echo "Processing job submitted successfully: \$processing_job_id"
    echo "Processing job will start when:"
    if [ -n "\$dependency_arg" ]; then
        echo "  - All MARS retrieval jobs complete successfully (SLURM dependency)"
    else
        echo "  - Immediately (no MARS jobs or fallback to flag checking)"
    fi
    echo "  - Then run remaining qlc subscripts (B1-CONV, B2-PREP, D1-ANAL, etc.)"
    echo "========================================================================================"
    exit 0  # Exit successfully after submitting processing job
else
    echo "========================================================================================"
    echo "QLC Data Retrieval Job Failed: \$(date)"
    echo "========================================================================================"
    echo "Exit code: \$qlc_exit_code"
    echo "Processing job will NOT be submitted due to retrieval job failure"
    echo "Please check the output above for error details"
    echo "========================================================================================"
    exit \$qlc_exit_code
fi
EOF
else
  # Single-job workflow: all processing in one job
  cat > $QLC_DIR/run/qlc_batch.sh$$<<EOF
#!/bin/bash -e
#SBATCH --job-name=qlc_processing_${config_arg:-workflow}
#SBATCH --output=log-qlc-%J.out
#SBATCH --error=err-qlc-%J.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=$USER@ecmwf.int
#SBATCH --export=ALL

# QLC Batch Job - single workflow execution
# Either data is already present, or only processing/analysis is needed

echo "QLC Batch Job Started: \$(date)"
echo "Job ID: \$SLURM_JOB_ID"
echo "Node: \$SLURMD_NODENAME"
echo "Workflow: $config_arg"

# Activate QLC venv
if [ -f "\$HOME/venv/qlc/bin/activate" ]; then
    source "\$HOME/venv/qlc/bin/activate"
    echo "Activated venv: \$HOME/venv/qlc"
else
    echo "Warning: venv not found at \$HOME/venv/qlc"
fi

# Source common functions for environment setup
if [ -f "\$HOME/qlc/bin/qlc_common_functions.sh" ]; then
    source "\$HOME/qlc/bin/qlc_common_functions.sh"
    setup_qlc_complete "auto" "true" || echo "Environment setup had warnings (continuing)"
fi

echo "Command: qlc $all_args"
set +e  # Disable exit-on-error for qlc command
qlc $all_args
qlc_exit_code=\$?
set -e  # Re-enable exit-on-error

if [ \$qlc_exit_code -eq 0 ]; then
    echo "QLC Batch Job Completed Successfully: \$(date)"
    echo "All tasks finished without errors"
else
    echo "QLC Batch Job Failed: \$(date)"
    echo "Exit code: \$qlc_exit_code"
    exit \$qlc_exit_code
fi
EOF
fi

if [ "$needs_two_jobs" = true ]; then
  log "Submitting two-job workflow: retrieval → processing"
  log "Retrieval job: $QLC_DIR/run/qlc_batch.sh$$"
elif [ "$data_already_complete" = true ]; then
  log "Submitting single-job workflow (data already complete)"
  log "Processing job: $QLC_DIR/run/qlc_batch.sh$$"
else
  log "Submitting single-job workflow (no MARS retrieval needed)"
  log "Batch job: $QLC_DIR/run/qlc_batch.sh$$"
fi

sbatch $QLC_DIR/run/qlc_batch.sh$$
log " "
log "Queue status:"
squeue -u "$USER"

log  "________________________________________________________________________________________"
log  "End   ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"
exit 0
