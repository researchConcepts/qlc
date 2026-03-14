#!/bin/bash -e
umask 0022

# ============================================================================
# QLC Batch Job Submission for HPC Systems
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
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
#   Example:   sqlc aifs1 aifs2 2025-11-01 2025-11-03 aifs
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
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
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
  echo "Usage (positional):"
  echo "  sqlc <exp1> [exp2 ...] <start_date> <end_date> <workflow> [options]"
  echo ""
  echo "Usage (named arguments):"
  echo "  sqlc --exps=<exp1>[,exp2,...] --start_date=<date> --end_date=<date> --workflow=<name> [options]"
  echo ""
  echo "Both syntaxes can be mixed. Both - and -- prefixes are accepted for all options."
  echo ""
  echo "Arguments:"
  echo "  <exp1> [exp2 ...]          One or more experiment identifiers (positional)"
  echo "  --exps=exp1[,exp2,...]     Same as above using named syntax"
  echo "  <start_date>               Start date YYYY-MM-DD (positional)"
  echo "  --start_date=YYYY-MM-DD    Same using named syntax"
  echo "  <end_date>                 End date YYYY-MM-DD (positional)"
  echo "  --end_date=YYYY-MM-DD      Same using named syntax"
  echo "  <workflow>                 Workflow name, e.g. qpy, aifs, eac5 (positional)"
  echo "  --workflow=<name>          Same using named syntax"
  echo ""
  echo "Processing options:"
  echo "  --obs-only                 Analyse observations only (skip model download/processing)"
  echo "  --mod-only                 Analyse model results only (skip observation processing)"
  echo "  -class=xx[,yy]             Override MARS class per experiment (e.g. -class=nl or -class=nl,rd)"
  echo "  --exp_labels=L1[,L2,...]   Display labels for experiments (comma-separated, same order as exps)."
  echo "                             Quotes optional unless labels contain spaces: --exp_labels=\"Run 1,Run 2\""
  echo "  --scripts=S1[,S2,...]      Restrict which QLC scripts to run (e.g. --scripts=D1-ANAL,Z1-XPDF)"
  echo "  --user=<label>             Override system username in PDF report titles/footers."
  echo "                             Example: --user=cams"
  echo ""
  echo "Variable override — GRIB retrieval context (A1-MARS, eac5, aifs, pyferret):"
  echo "  --myvar=<spec>[;<spec>]    Override MARS_RETRIEVALS from workflow config."
  echo "                             Each spec: [level_type_]display_name,GRIB_param"
  echo "                             Multiple specs separated by semicolon."
  echo "                             IMPORTANT: quote the value when using semicolons in a shell:"
  echo "                               --myvar=\"sfc_T2m,167\""
  echo "                               --myvar=\"sfc_T2m,167;pl_T,130\""
  echo "  --param=<grib>[;<grib>]    Per-experiment GRIB param override (A1-MARS only)."
  echo "                             Use when experiments need different GRIB codes for the same variable."
  echo "                             ';' separates variables (same order as --myvar=),"
  echo "                             ',' separates experiments (same order as --exps=)."
  echo "                             Single entry broadcasts to all experiments."
  echo "                             Both GRIB notations accepted: 249.210 and 210249."
  echo "                             IMPORTANT: requires --myvar=; always quote the value:"
  echo "                               --myvar=\"pl_NH4_as;pl_NO3_as\" --param=\"35.212,249.210;36.212,247.210\""
  echo ""
  echo "Variable override — obs-mod mapping context (D1-ANAL / qpy, evaltools) [new in v1.0.2]:"
  echo "  --myvar=\"DisplayName|modVAR[,op,val]|obsVAR[,op,val]|targetUNIT[,unitFAC]\""
  echo "  Multiple variables separated by ';' inside the quoted string."
  echo "  Arithmetic operators: * / + -   applied at load time on model or obs side."
  echo "  unitFAC: explicit scale factor (alternative to automatic unit conversion)."
  echo "  Applied to all active networks (--network=) in one run."
  echo "  Use for variables not in qlc's built-in unit table, custom diagnostics, or quick tests."
  echo "  Examples:"
  echo "    --myvar=\"O3|go3|O3|ug/m3\"                     O3: automatic kg/kg -> ug/m3"
  echo "    --myvar=\"PM2.5|pm2p5|PM2.5|ug/m3\"             PM2.5: automatic kg/m3 -> ug/m3"
  echo "    --myvar=\"T2m|2t|temp|degC\"                    T2m: automatic K -> degC"
  echo "    --myvar=\"MyVar|myvar,*,0.001|obs|N/A\"          custom: scale model x0.001, no unit"
  echo "    --myvar=\"MyVar|myvar|obs|custom_unit,1e3\"      custom: unitFAC=1e3, unit label kept"
  echo "    --myvar=\"O3|go3|O3|ug/m3;PM2.5|pm2p5|PM2.5|ug/m3\"  multi-variable"
  echo ""
  echo "Network and region overrides (D1-ANAL only):"
  echo "  --network=CODE[,CODE2,...] Override ACTIVE_REGIONS — which station networks to process."
  echo "                             Network codes must match REGION_*_NAME entries in the workflow config."
  echo "                             Example: --network=BRAZIL_INMET,US_CASTNET"
  echo "  --region=GEO[,GEO2,...]   Override geographic plot extent for all active networks."
  echo "                             Comma-separated plot region codes (e.g., EU, SA, GLOBE, NH)."
  echo "                             Each active network is run once per listed plot region."
  echo "                             Example: --region=SA,GLOBE"
  echo "  --station_file=<path>      Override station CSV file for all active networks."
  echo "                             Tilde (~) is expanded to home directory."
  echo ""
  echo "MARS request overrides:"
  echo "  -grid=<value>              Override MARS GRID parameter"
  echo "  -step=<value>              Override MARS STEP"
  echo "  -time=<value>              Override MARS TIME"
  echo "  -levelist=<value>          Override MARS LEVELIST"
  echo ""
  echo "Examples:"
  echo "  # Positional syntax (classic)"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test --obs-only --network=EU_EBAS_Daily"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,nl"
  echo ""
  echo "  # Named syntax (both - and -- prefix accepted)"
  echo "  sqlc --exps=exp1,exp2 --start_date=2018-12-01 --end_date=2018-12-21 --workflow=test"
  echo "  sqlc --exps=exp1,exp2 --start_date=2018-12-01 --end_date=2018-12-21 --workflow=test --obs-only"
  echo ""
  echo "  # GRIB variable and region overrides (quotes required when using ; in shell)"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test --myvar=\"sfc_T2m,167;pl_T,130\""
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test --network=EU_EBAS_Daily,US_CASTNET"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test --network=BRAZIL_INMET --region=SA,GLOBE"
  echo ""
  echo "  # Obs-mod pipe-format (qpy / evaltools): one spec applied across all networks"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 qpy --myvar=\"O3|go3|O3|ug/m3;PM2.5|pm2p5|PM2.5|ug/m3\""
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 qpy --myvar=\"MyVar|myvar,*,0.001|obs|N/A\" --network=EU_AIRBASE -class=rd"
  echo ""
  echo "  # Per-experiment GRIB param override (e.g. AER vs HAMM7 comparison)"
  echo "  sqlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,rd \\"
  echo "       --myvar=\"pl_NH4_as;pl_NO3_as\" --param=\"35.212,249.210;36.212,247.210\""
  echo ""
  echo "  # Full named syntax"
  echo "  sqlc --exps=exp1,exp2 --start_date=2018-12-01 --end_date=2018-12-21 --workflow=test \\"
  echo "       --myvar=\"sfc_T2m,167;pl_T,130\" -class=nl,nl --network=EU_EBAS_Daily,US_CASTNET"
  echo ""
  echo "Other commands:"
  echo "  qlc-vars search O3         Search variable table"
  echo "  qlc ...                    Interactive mode, same options as sqlc"
  echo ""
  echo "Check Job Status:"
  echo "  squeue -u \$USER"
  echo ""
  echo "Results:"
  echo "  ~/qlc/Results        GRIB data (MARS download)"
  echo "  ~/qlc/Analysis       NetCDF processed data"
  echo "  ~/qlc/Plots          Generated plots"
  echo "  ~/qlc/Presentations  PDF reports"
  echo ""
  echo "For more information:"
  echo "  Quick Start    : ~/qlc/doc/QuickStart.md"
  echo "  Documentation  : https://docs.researchconcepts.io/qlc"
  echo "  Getting Started: https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/"
  echo ""
  echo "See: https://docs.researchconcepts.io/qlc/latest/reference/changelog"
  echo "© 2018-2026 ResearchConcepts io GmbH. All Rights Reserved."
  echo "Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>"
  echo "========================================================================================"
  exit 0
fi

# ----------------------------------------------------------------------------------------
# Parse command line arguments dynamically to support variable number of experiments
# Format: sqlc exp1 [exp2 ...] startDate endDate [config] [named-options...]
# ----------------------------------------------------------------------------------------

# Function to check if argument is a date (matches YYYY-MM-DD pattern)
is_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# Build a safely-quoted copy of the full argument list.
# This is embedded in generated batch scripts so that every 'qlc' invocation
# receives all CLI options intact — Python's argument parser (qlc_wrapper.py)
# then handles --myvar=, --scripts=, --mod-only, --network=, etc.
# The old approach reconstructed only positionals + class, silently dropping
# everything else and breaking any command that used additional CLI options.
all_args=$(printf '%q ' "$@")

# ─── First pass: separate positionals from named options ─────────────────────
# Positional args (exp IDs, dates, workflow config name) are needed locally for
# job naming, MARS flag checks, and sourcing the workflow config file.
# Named options starting with '-' are handled by Python; we only extract the
# well-known batch-scheduling ones (class, workflow, exps, dates) for local use.
positional_args=()
experiments=()
class_option=""
config_arg=""
start_date=""
end_date=""

for arg in "$@"; do
  if [[ "$arg" == --class=* ]] || [[ "$arg" == -class=* ]]; then
    class_option="-class=${arg##*=}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Class override option: $class_option"
  elif [[ "$arg" == --workflow=* ]]; then
    config_arg="${arg#--workflow=}"
  elif [[ "$arg" == --exps=* ]]; then
    IFS=',' read -ra experiments <<< "${arg#--exps=}"
  elif [[ "$arg" == --start_date=* ]] || [[ "$arg" == --start=* ]]; then
    start_date="${arg##*=}"
  elif [[ "$arg" == --end_date=* ]] || [[ "$arg" == --end=* ]]; then
    end_date="${arg##*=}"
  elif [[ "$arg" == -* ]]; then
    : # Other named option — forwarded to qlc via all_args; nothing to do here
  else
    positional_args+=("$arg")
  fi
done

# ─── Second pass: extract experiments / dates / config from positionals ───────
# Only runs when positional arguments are present (classic or mixed syntax).
num_positional=${#positional_args[@]}

if [ $num_positional -ge 3 ] && ! is_date "${positional_args[$((num_positional-1))]}"; then
  # Last positional is the workflow config name
  config_arg="${positional_args[$((num_positional-1))]}"
  end_date="${end_date:-${positional_args[$((num_positional-2))]}}"
  start_date="${start_date:-${positional_args[$((num_positional-3))]}}"
  if [ ${#experiments[@]} -eq 0 ]; then
    experiments=("${positional_args[@]:0:$((num_positional-3))}")
  fi
  USER_DIR="$config_arg"
elif [ $num_positional -ge 2 ]; then
  end_date="${end_date:-${positional_args[$((num_positional-1))]}}"
  start_date="${start_date:-${positional_args[$((num_positional-2))]}}"
  if [ ${#experiments[@]} -eq 0 ]; then
    experiments=("${positional_args[@]:0:$((num_positional-2))}")
  fi
  USER_DIR="${config_arg:-default}"
elif [ -n "$config_arg" ]; then
  # Fully named syntax (--exps= --start_date= --end_date= --workflow=)
  USER_DIR="$config_arg"
else
  echo "Error: Insufficient arguments"
  echo "Usage: sqlc exp1 [exp2 ...] startDate endDate [config] [options]"
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

# Export WORKFLOW_CONFIG so Python's VariableRegistry can load workflow-specific
# [VARIABLE_GROUPS] when expanding group refs (e.g. @TEST_VAR5, @AIFS_TESTS).
# qlc_main.sh does the same; without this the MARS completion check in
# get_required_mars_variables() fails to resolve group references.
export WORKFLOW_CONFIG="$CONFIG_FILE"

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
  log "  sqlc exp1 exp2 2018-12-01 2018-12-21 mars      # retrieval only"
  log "  sqlc exp1 exp2 2018-12-01 2018-12-21 test      # Test analysis"
  log "  sqlc exp1 exp2 2018-12-01 2018-12-21 qpy       # Station analysis"
  log "  sqlc exp1 exp2 2018-12-01 2018-12-21 eac5      # Production analysis"
  log ""
  log "For detailed help:"
  log "  Quick Start:   cat $HOME/qlc/doc/QuickStart.md"
  log "  Online Docs:   https://docs.researchconcepts.io/qlc/latest/"
  log "  Usage Guide:   https://docs.researchconcepts.io/qlc/latest/user-guide/usage/"
  log "========================================================================================"
  exit 0
fi

log "----------------------------------------------------------------------------------------"

# Pre-compute experiment list string for embedding in generated batch scripts.
# The running batch job needs experiment IDs to locate MARS .id files; resolving
# this at submission time avoids re-parsing the full (now option-rich) all_args.
exp_list_precomputed="${experiments[*]}"

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
    # Experiment list was resolved at job submission time to avoid re-parsing
    # the full (option-rich) argument string inside the running batch job.
    exp_list="$exp_list_precomputed"
    
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
