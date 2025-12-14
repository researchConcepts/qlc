#!/bin/bash -e
umask 0022

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

ARCH="`uname -m`"
myOS="`uname -s`"
HOST="`hostname -s`"
CUSR="`echo $USER`"

# ----------------------------------------------------------------------------------------
# Parse command line arguments dynamically to support variable number of experiments
# Format: qlc exp1 [exp2 ...] startDate endDate [config]
# ----------------------------------------------------------------------------------------

# Handle --version and --help (if called directly instead of via Python wrapper)
if [ "$1" == "--version" ] || [ "$1" == "-V" ]; then
  echo "QLC version information (use Python entry point for full details)"
  echo "Run: python -m qlc.cli --version"
  exit 0
fi

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  echo "QLC help (use Python entry point for full details)"
  echo "Run: python -m qlc.cli --help"
  exit 0
fi

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
elif [ $num_args -ge 4 ]; then
  # No config name, using default
  config_arg=""
  end_date="${args[$((num_args-1))]}"
  start_date="${args[$((num_args-2))]}"
  # Everything before start_date is experiments
  experiments=("${args[@]:0:$((num_args-2))}")
else
  echo "Error: Insufficient arguments"
  echo "Usage: qlc exp1 [exp2 ...] startDate endDate [config]"
  exit 1
fi

# Validate dates
if ! is_date "$start_date" || ! is_date "$end_date"; then
  echo "Error: Dates must be in YYYY-MM-DD format"
  echo "Got start_date='$start_date', end_date='$end_date'"
  exit 1
fi

# Validate we have at least one experiment
if [ ${#experiments[@]} -eq 0 ]; then
  echo "Error: At least one experiment must be specified"
  exit 1
fi

# Log parsed arguments (before CONFIG_FILE is loaded, so using echo)
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Parsed arguments:"
echo "[$(date +"%Y-%m-%d %H:%M:%S")]   Experiments: ${experiments[*]} (${#experiments[@]} total)"
echo "[$(date +"%Y-%m-%d %H:%M:%S")]   Start date: $start_date"
echo "[$(date +"%Y-%m-%d %H:%M:%S")]   End date: $end_date"
echo "[$(date +"%Y-%m-%d %H:%M:%S")]   Config: ${config_arg:-default}"

# user specific configuration file
QLC_DIR="$QLCHOME"
if [ "$config_arg" == "mars" ] || [ -z "$config_arg" ]; then
   USER_DIR="default"
else
   USER_DIR="$config_arg"
fi
CONFIG_DIR="$QLC_DIR/config/$USER_DIR"
CONFIG_FILE="$CONFIG_DIR/qlc_$USER_DIR.conf"
#----------------------------------------------------------------------
JSON_DIR="${CONFIG_DIR}/../json"
NAMELIST_DIR="${CONFIG_DIR}/../nml"
#----------------------------------------------------------------------

# Source the configuration file and automatically export all defined variables
# to make them available to any subscripts that are called.
set -a
. "$CONFIG_FILE"
set +a

export CONFIG_DIR
export CONFIG_FILE
export NAMELIST_DIR
export JSON_DIR

# Include common functions
FUNCTIONS="$SCRIPTS_PATH/qlc_common_functions.sh"
source $FUNCTIONS
export  FUNCTIONS

SCRIPT="$0"
log  "________________________________________________________________________________________"
log  "Start ${SCRIPT} at `date`"
log  "----------------------------------------------------------------------------------------"
log  "Purpose of QLC = Quick Look CAMS/IFS results -- ${HOST} on ${myOS} / ${ARCH} - ${CUSR}  "
log  "           QLC uses subscripts defined in $CONFIG_FILE                                  "
log  "           see $QLC_DIR/doc/README.md for details                                       "
log  "Don^t expect too much, as we follow the KISS principle >Keep it simple, stupid!< ;-) ..."
log  "________________________________________________________________________________________"
log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
log  "----------------------------------------------------------------------------------------"

# Check if the required parameters are provided
if [ $# -eq 0 ]; then
  log  "________________________________________________________________________________________"
  log  "QLC (Quick Look Content) - Interactive Execution"
  log  "----------------------------------------------------------------------------------------"
  log  " "
  log  "Usage:"
  log  "  qlc <exp1> [exp2 ...] <start_date> <end_date> [config]"
  log  " "
  log  "Arguments:"
  log  "  <exp1> [exp2 ...]  One or more experiment identifiers (minimum 1)"
  log  "  <start_date>       Start date in YYYY-MM-DD format"
  log  "  <end_date>         End date in YYYY-MM-DD format"
  log  "  [config]           Configuration option (default: 'default')"
  log  " "
  log  "Configuration Options:"
  log  "  Each subdirectory in ~/qlc/config can be used as a config option:"
  log  " "
  log  "  default (or mars)  MARS data retrieval only (no analysis)"
  log  "  qpy                qlc-py collocation & time series plots"
  log  "  evaltools          Advanced statistics with Taylor diagrams"
  log  "  eac5               EAC5/CAMS reanalysis analysis (K1 namelist)"
  log  "  pyferret           PyFerret visualization integration"
  log  "  ver0d              Ver0D processing (ATOS/IDL-based)"
  log  " "
  log  "Multi-Experiment Support:"
  log  "  QLC supports comparing any number of experiments (N >= 1):"
  log  "  - Single:  qlc exp1 2018-12-01 2018-12-21 qpy"
  log  "  - Two:     qlc exp1 exp2 2018-12-01 2018-12-21 qpy"
  log  "  - Three+:  qlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy"
  log  " "
  log  "Examples:"
  log  "  # Two experiments with qlc-py collocation and time series"
  log  "  qlc b2ro b2rn 2018-12-01 2018-12-21 qpy"
  log  " "
  log  "  # Three experiments with evaltools statistics"
  log  "  qlc exp1 exp2 exp3 2018-12-01 2018-12-21 evaltools"
  log  " "
  log  "  # EAC5 reanalysis validation (K1 namelist: 10 variables)"
  log  "  qlc b2ro b2rn 2018-12-01 2018-12-21 eac5"
  log  " "
  log  "  # MARS data retrieval only (no analysis)"
  log  "  qlc b2ro b2rn 2018-12-01 2018-12-21 mars"
  log  " "
  log  "  # PyFerret visualization"
  log  "  qlc b2ro b2rn 2018-12-01 2018-12-21 pyferret"
  log  " "
  log  "Data Retrieval Behavior:"
  log  "  - Non-mars configs: Auto-retrieve data if qlc_A1.sh is active"
  log  "    (checks data_retrieval flag; only retrieves if needed)"
  log  "  - 'mars' config: Retrieves data ONLY, no analysis/processing"
  log  "  - Data based on MARS namelist (e.g., mars_K1_sfc.nml) and"
  log  "    parameter mapping (e.g., K1_sfc in MARS_RETRIEVALS)"
  log  " "
  log  "For batch submission, use: sqlc <exp1> [exp2 ...] <dates> [config]"
  log  "For help: qlc --help (or just 'qlc' without arguments in Python wrapper)"
  log  "________________________________________________________________________________________"
  log  "End   ${SCRIPT} at `date`"
  log  "________________________________________________________________________________________"
  exit 0
fi

# Loop through the provided parameters
for param in "$@"; do
  log  "Command line input: $param"
done

# Check if the configuration file exists
if [ -f "$CONFIG_FILE" ]; then
	# Read and export the variables from the configuration file
	# ----------------------------------------------------------------------------------------
	# Log the active configuration settings, excluding comments and empty lines
	log "Active configuration settings from: ${CONFIG_FILE}"
	grep -v '^\s*#\|^\s*$' "$CONFIG_FILE" | while IFS= read -r line; do
		log "  ${line}"
	done
	log "----------------------------------------------------------------------------------------"

	# Source the configuration file and automatically export all defined variables
	# to make them available to any subscripts that are called.
	set -a
	. "$CONFIG_FILE"
	set +a

else
  log  "Error: Config file '$CONFIG_FILE' not found."
  exit 1
fi

# Check if the SUBSCRIPT_NAMES array is defined
if [ -z "${SUBSCRIPT_NAMES[*]}" ]; then
  log "Error: SUBSCRIPT_NAMES is not defined in the configuration file."
  exit 1
fi

# Create working directory if not existent
if [ ! -d "$WORKING_DIRECTORY" ]; then
    mkdir -p $WORKING_DIRECTORY
fi

# Create a temporary directory and store its path in a variable
#TEMP_DIR=$(mktemp -d)
TEMP_DIR=$WORKING_DIRECTORY
export TEMP_DIR

# Change to the temporary directory
cd "$TEMP_DIR"
PWD="`pwd -P`"
log "changed to directory: $PWD" 

# Loop through and call the specified subscripts individually
for name in "${SUBSCRIPT_NAMES[@]}"; do
  script_name="qlc_${name}.sh"
  log  "processing subscript:  $script_name"

  if [ -f "$SCRIPTS_PATH/$script_name" ]; then
    # Call the subscript
    log   "$SCRIPTS_PATH/$script_name" "$@"
          "$SCRIPTS_PATH/$script_name" "$@"

    if [ "$config_arg" == "mars" ]; then
       log "Only calling the mars retrieval script, the other processes can be called in the second qlc submission step (without option: mars)"
       log  "----------------------------------------------------------------------------------------"
       log  "End ${SCRIPT} at `date`"
       log  "________________________________________________________________________________________"
       exit 1
    fi
          
  else
    log  "Error: $script_name not found in $SCRIPTS_PATH."
  fi
done

pwd -P
log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0

