#!/bin/bash -e
umask 0022

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
# --- End: Environment Setup ---

# --- Start: QLC Runtime Detection ---
# Detect QLC runtime directory with priority:
# 1. QLC_HOME environment variable (explicit override)
# 2. Auto-detection based on conda environment
# 3. Default to ~/qlc (production)
if [ -n "$QLC_HOME" ]; then
  echo "[QLC] Using explicit QLC_HOME: $QLC_HOME"
  QLCHOME="$QLC_HOME"
elif [ -n "$CONDA_DEFAULT_ENV" ] && [[ "$CONDA_DEFAULT_ENV" == *"qlc-dev"* ]]; then
  echo "[QLC-DEV] Auto-detected development environment"
  QLCHOME="$HOME/qlc-dev-run"
else
  QLCHOME="$HOME/qlc"
fi

# Verify runtime exists
if [ ! -d "$QLCHOME" ]; then
  echo "[ERROR] QLC runtime directory not found: $QLCHOME"
  echo "[ERROR] Please run: qlc-install --mode test (or --mode dev)"
  exit 1
fi

# Export for subscripts
export QLCHOME
# --- End: QLC Runtime Detection ---

# ----------------------------------------------------------------------------------------
# Check if help is needed first (before loading config)
# ----------------------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  echo "________________________________________________________________________________________"
  echo "SQLC - QLC Batch Submission to SLURM Scheduler"
  echo "----------------------------------------------------------------------------------------"
  echo ""
  echo "Usage:"
  echo "  sqlc <exp1> [exp2 ...] <start_date> <end_date> [config]"
  echo ""
  echo "Arguments:"
  echo "  <exp1> [exp2 ...]  One or more experiment identifiers (minimum 1)"
  echo "  <start_date>       Start date in YYYY-MM-DD format"
  echo "  <end_date>         End date in YYYY-MM-DD format"
  echo "  [config]           Configuration option (default: 'default')"
  echo ""
  echo "Configuration Options:"
  echo "  Each subdirectory in ~/qlc/config can be used as a config option:"
  echo ""
  echo "  default (or mars)  MARS data retrieval only"
  echo "  qpy                qlc-py collocation & time series plots"
  echo "  evaltools          Advanced statistics with Taylor diagrams"
  echo "  eac5               EAC5/CAMS reanalysis analysis (K1 namelist)"
  echo "  pyferret           PyFerret visualization integration"
  echo "  ver0d              Ver0D processing (ATOS/IDL-based)"
  echo ""
  echo "Multi-Experiment Support:"
  echo "  SQLC supports any number of experiments (N >= 1):"
  echo "  - Single:  sqlc exp1 2018-12-01 2018-12-21 qpy"
  echo "  - Two:     sqlc exp1 exp2 2018-12-01 2018-12-21 qpy"
  echo "  - Three+:  sqlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy"
  echo ""
  echo "Examples:"
  echo "  # Submit qlc-py collocation job (auto-retrieves data if needed)"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 qpy"
  echo ""
  echo "  # Submit three-experiment evaltools evaluation"
  echo "  sqlc exp1 exp2 exp3 2018-12-01 2018-12-21 evaltools"
  echo ""
  echo "  # Submit EAC5 reanalysis job (K1 namelist: 10 variables)"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 eac5"
  echo ""
  echo "  # MARS retrieval + processing (two-job dependent workflow)"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 mars"
  echo "  (Job 1: Retrieves data only, Job 2: Processes data after retrieval)"
  echo ""
  echo "  # Submit PyFerret visualization job"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 pyferret"
  echo ""
  echo "  # Submit Ver0D processing job"
  echo "  sqlc b2ro b2rn 2018-12-01 2018-12-21 ver0d"
  echo ""
  echo "Data Retrieval Behavior:"
  echo "  - Non-mars configs: Auto-retrieve data if qlc_A1.sh is active"
  echo "    (checks data_retrieval flag; only retrieves if needed)"
  echo "  - 'mars' config: Retrieves data ONLY, no analysis/processing"
  echo "  - Data based on MARS namelist (e.g., mars_K1_sfc.nml) and"
  echo "    parameter mapping (e.g., K1_sfc in MARS_RETRIEVALS)"
  echo ""
  echo "MARS Two-Job Workflow:"
  echo "  When using 'mars' config, sqlc creates two dependent jobs:"
  echo "  1. MARS retrieval (runs: qlc exp1 exp2 date1 date2 mars)"
  echo "  2. Processing with default config (runs after #1 completes)"
  echo "  3. Email notification sent to \$USER@ecmwf.int on completion"
  echo ""
  echo "Related Commands:"
  echo "  qlc       Interactive QLC execution (no batch submission)"
  echo "  squeue    Check your SLURM job queue status"
  echo "________________________________________________________________________________________"
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

# Parse arguments from the end to handle variable number of experiments
args=("$@")
num_args=$#

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
  echo "Usage: sqlc exp1 [exp2 ...] startDate endDate [config]"
  echo "Run 'sqlc' without arguments for detailed help."
  exit 1
fi

# Override USER_DIR for mars option
if [ "$config_arg" == "mars" ]; then
  USER_DIR="default"
fi

# User specific configuration file
QLC_DIR="$QLCHOME"
CONFIG_DIR="$QLC_DIR/config/$USER_DIR"
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
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"
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
log "----------------------------------------------------------------------------------------"

# Build the command line to pass all arguments
all_args="$@"

# Generate batch script
if [ "$config_arg" == "mars" ]; then
  # For MARS config: create two scripts - retrieval job and processing job
  jobid='${SLURM_JOB_ID}'
  
  # Create the processing job script (Job 2)
  cat > $QLC_DIR/run/qlc_processing.sh$$<<EOF
#!/bin/ksh -e
#SBATCH --job-name=qlc_processing
#SBATCH --output=log-processing-%J.out
#SBATCH --error=err-processing-%J.out
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=$USER@ecmwf.int
qlc ${experiments[*]} $start_date $end_date
EOF
  
  # Create the MARS retrieval job script (Job 1) that submits Job 2
  cat > $QLC_DIR/run/qlc_batch.sh$$<<EOF
#!/bin/ksh -e
#SBATCH --job-name=qlc_mars_retrieval
#SBATCH --output=log-retrieval-%J.out
#SBATCH --error=err-retrieval-%J.out
#SBATCH --export=ALL
qlc $all_args
echo "MARS retrieval job ID: \${jobid}"
sbatch --dependency=afterok:\${jobid} $QLC_DIR/run/qlc_processing.sh$$
EOF
else
  # For other configs: single job with email notification
  cat > $QLC_DIR/run/qlc_batch.sh$$<<EOF
#!/bin/ksh -e
#SBATCH --job-name=qlc_${config_arg:-default}
#SBATCH --output=log-%J.out
#SBATCH --error=err-%J.out
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=$USER@ecmwf.int
qlc $all_args
EOF
fi

log "Submitting batch job: $QLC_DIR/run/qlc_batch.sh$$"
sbatch $QLC_DIR/run/qlc_batch.sh$$
squeue -u "$USER"

log  "________________________________________________________________________________________"
log  "End   ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"
exit 0
