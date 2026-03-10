#!/bin/bash -e

# ============================================================================
# QLC Main Workflow Driver
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.2
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Main workflow orchestration script for QLC. Manages environment setup,
#   configuration loading, argument parsing, and sequential execution of
#   workflow subscripts (A1-MARS through Z1-XPDF).
#
# Entry Point:
#   This script is called via the 'qlc' command (Python entry point)
#   Users run: qlc <exp1> [exp2 ...] <start_date> <end_date> <workflow>
#   Example:   qlc aifs1 aifs2 2025-11-01 2025-11-03 aifs
#
# Features:
#   - Automatic environment detection and activation
#   - Virtual environment and HPC module support
#   - Multi-experiment and obs-only mode support
#   - Named and positional argument parsing
#   - MARS data retrieval with pre-flight checking
#   - Workflow subscript orchestration
#
# Usage:
#   Called automatically via 'qlc' command - Do not call directly
#   For help: qlc -h
#
# Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

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
if [ -f "${QLC_HOME:-$HOME/qlc}/bin/qlc_common_functions.sh" ]; then
    source "${QLC_HOME:-$HOME/qlc}/bin/qlc_common_functions.sh"
    
    # Log start banner first (moved up for consistent logging)
    SCRIPT="$0"
    log "________________________________________________________________________________________"
    log "QLC v1.0.2: Quick Look Content for CAMS/IFS Analysis"
    log "________________________________________________________________________________________"
    log "Start ${SCRIPT} at $(date)"
    log "System: ${MOST} on ${myOS} / ${ARCH} - User: ${CUSR}"
    log "________________________________________________________________________________________"
    log "Documentation: https://docs.researchconcepts.io/qlc/latest/"
    log "QLC uses subscripts defined in workflow configuration"
    log "----------------------------------------------------------------------------------------"
    log "Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.                  "
    log "Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>       "
    log "----------------------------------------------------------------------------------------"
    
    # Setup complete QLC environment
    if setup_qlc_complete "$QLC_MODE" "true"; then
        log "[QLC]" "Environment setup completed successfully"
    else
        log "[QLC]" "Warning: Environment setup had issues, continuing..."
    fi
else
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] ERROR: Common functions not found, cannot continue"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Searched locations:"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC]   - ${QLC_HOME:-$HOME/qlc}/bin/qlc_common_functions.sh"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC]   - $HOME/qlc/bin/qlc_common_functions.sh"
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
  log "[QLC]" "ERROR: QLC runtime directory not found: $QLCHOME"
  log "[QLC]" "ERROR: Please run: qlc-install --mode test (or --mode dev)"
  exit 1
fi

# Export for subscripts
export QLCHOME
# --- End: QLC Runtime Detection ---
# exit
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

# Parse arguments and extract options (like -class=, -vars=, -nml=, -scripts=, MARS overrides, expert mode)
# First pass: filter out options and build clean args array
args=()
class_option=""
vars_option=""
nml_option=""
scripts_option=""
mars_options=()
expert_mode_options=()
for arg in "$@"; do
  if [[ "$arg" == -class=* ]]; then
    class_option="$arg"
    log "Class override option: $class_option"
  elif [[ "$arg" == -vars=* ]]; then
    vars_option="$arg"
    log "Variables override option: $vars_option"
  elif [[ "$arg" == -nml=* ]]; then
    nml_option="$arg"
    log "Namelist override option: $nml_option"
  elif [[ "$arg" == -scripts=* ]]; then
    scripts_option="$arg"
    log "Workflow scripts override option: $scripts_option"
  elif [[ "$arg" == -param=* ]] || [[ "$arg" == -ncvar=* ]] || \
       [[ "$arg" == -myvar=* ]] || [[ "$arg" == -levtype=* ]]; then
    expert_mode_options+=("$arg")
    log "Expert mode option: $arg"
  elif [[ "$arg" == -grid=* ]] || [[ "$arg" == -step=* ]] || [[ "$arg" == -time=* ]] || \
       [[ "$arg" == -type=* ]] || [[ "$arg" == -stream=* ]] || [[ "$arg" == -levelist=* ]]; then
    mars_options+=("$arg")
    log "MARS parameter override: $arg"
  else
    args+=("$arg")
  fi
done

# Use modern parse_qlc_arguments function (handles "None" placeholders and obs-only mode)
parse_qlc_arguments "${args[@]}" || {
  log "ERROR: Failed to parse arguments"
  log "Usage: qlc [exp1] [expN ...] <start_date> <end_date> [config] [-class=xx|xx,yy,...] [options]"
  log "   or: qlc <start_date> <end_date> [config]  (obs-only mode)"
  log "Examples:"
  log "  qlc aifs1 aifs2 2025-11-01 2025-11-03 aifs         # Two experiments"
  log "  qlc aifs1 None 2025-11-01 2025-11-03 aifs         # Single experiment"
  log "  qlc None None 2025-11-01 2025-11-03 aifs         # Obs-only mode"
  log "  qlc None 2025-11-01 2025-11-03 aifs              # Obs-only mode (single None)"
  log "  qlc 2025-11-01 2025-11-03 aifs                   # Obs-only mode (no None)"
  exit 1
}

# parse_qlc_arguments sets: experiments (array), sDat, eDat, config_arg, exp1, expN
start_date="$sDat"
end_date="$eDat"

# Echo all raw command line inputs first (positional + optional args logged above by
# parse_qlc_arguments for Python-handled options like --myvar=, --param=, etc.)
for param in "$@"; do
  log "Command line input: $param"
done

# Log parsed arguments
log "Parsed arguments:"
if [ ${#experiments[@]} -eq 0 ]; then
  log "  Experiments: (none - obs-only mode)"
else
  log "  Experiments: ${experiments[*]} (${#experiments[@]} total)"
fi
log "  Start date: $start_date"
log "  End date: $end_date"
log "  Config: ${config_arg:-default}"

# Provide guidance if no config specified
if [ -z "$config_arg" ]; then
  log ""
  log "========================================================================================"
  log "QLC - Interactive QLC Execution"
  log "========================================================================================"
  log ""
  log "Usage:"
  log "  qlc <exp1> [exp2 ...] <start_date> <end_date> <workflow> [options]"
  log ""
  log "Arguments:"
  log "  <exp1> [exp2 ...]  One or more experiment identifiers"
  log "  <start_date>       Start date (YYYY-MM-DD)"
  log "  <end_date>         End date (YYYY-MM-DD)"
  log "  <workflow>         Workflow name: aifs, eac5, evaltools, mars, pyferret, qpy, test"
  log ""
  log "Common Options:"
  log "  --obs-only              Analyze observations only (no MARS retrieval)"
  log "  --mod-only              Analyze model results only"
  log "  -class=xx[,yy]          Override MARS class per experiment (e.g., -class=nl,nl)"
  log "  --myvar=<spec>          Variable spec override (see format below)"
  log "  --network=<net>[,<net>] Station network(s) to activate (overrides ACTIVE_REGIONS)"
  log "  --region=<code>         Map region override (e.g., --region=EU)"
  log "  --user=<name>           Use group/display name instead of Unix username"
  log ""
  log "Variable Spec Format (new in v1.0.2):"
  log "  \"DisplayName|modVAR[,op,val]|obsVAR[,op,val]|targetUNIT[,unitFAC]\""
  log "  Operators: * / + -   applied at load time on model or obs side"
  log "  unitFAC: explicit scale factor (alternative to automatic unit conversion)"
  log "  Use for variables not in the built-in table, custom diagnostics, or quick tests."
  log "  A single --myvar= applies the same spec across all active regions in one run."
  log ""
  log "  Examples:"
  log "    \"O3|go3|O3|ug/m3\"               O3: automatic kg/kg -> ug/m3"
  log "    \"PM2.5|pm2p5|PM2.5|ug/m3\"       PM2.5: automatic kg/m3 -> ug/m3 (preferred)"
  log "    \"T2m|2t|temp|degC\"              T2m: automatic K -> degC"
  log "    \"MyVar|myvar,*,0.001|obs|N/A\"   custom: scale model by 0.001, no unit label"
  log "    \"MyVar|myvar|obs|unit,1e3\"       custom: unitFAC=1e3, unit label kept"
  log "  Multiple variables: separate with ';' inside the quoted string."
  log ""
  log "Quick Examples:"
  log "  qlc exp1 exp2 2018-12-01 2018-12-21 test"
  log "  qlc exp1 exp2 2018-12-01 2018-12-21 test --obs-only --region=EU"
  log "  qlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,nl --myvar=\"O3|go3|O3|ug/m3\""
  log "  qlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,nl --network=EU_AIRBASE,China_AQ"
  log "  qlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,nl --param=210073,210203 --myvar=\"PM2.5|pm2p5|PM2.5|ug/m3;O3|go3|O3|ug/m3\""
  log ""
  log "Variable Search:"
  log "  qlc-vars search PM2.5          # find by name pattern"
  log "  qlc-vars info sfc_O3           # detailed metadata + GRIB parameters"
  log "  qlc-vars list --source ifs     # list all IFS variables"
  log ""
  log "View Results:"
  log "  ls -lrth ~/qlc/Results        # GRIB data (MARS download)"
  log "  ls -lrth ~/qlc/Analysis       # NetCDF processed data"
  log "  ls -lrth ~/qlc/Plots          # Generated plots"
  log "  ls -lrth ~/qlc/Presentations  # PDF reports"
  log ""
  log "For batch submission (HPC/SLURM), use: sqlc"
  log ""
  log "For more information:"
  log "  Quick Start    : ~/qlc/doc/QuickStart.md"
  log "  Documentation  : https://docs.researchconcepts.io/qlc"
  log "  Getting Started: https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/"
  log ""
  log "© 2018-2026 ResearchConcepts io GmbH. All Rights Reserved."
  log "========================================================================================"
  exit 0
fi

# User specific configuration file
QLC_DIR="$QLCHOME"
USER_DIR="$config_arg"
CONFIG_DIR="$QLC_DIR/config/workflows/$USER_DIR"
CONFIG_FILE="$CONFIG_DIR/qlc_$USER_DIR.conf"
#----------------------------------------------------------------------
# JSON and namelist directories
NAMELIST_DIR="$QLC_DIR/config/nml"
# JSON_DIR may be workflow-specific or global for qlc-py
if [ -d "${CONFIG_DIR}/json" ]; then
    JSON_DIR="${CONFIG_DIR}/json"
else
    JSON_DIR="$QLC_DIR/config/qlc-py/json"
fi
#----------------------------------------------------------------------

# Source the configuration file and automatically export all defined variables
# to make them available to any subscripts that are called.
# Redirect to /dev/null to suppress verbose output during sourcing
set -a
. "$CONFIG_FILE" >/dev/null 2>&1 || {
    log "[ERROR]" "Failed to source workflow configuration: $CONFIG_FILE"
    exit 1
}
set +a

export CONFIG_DIR
export CONFIG_FILE
# Export workflow config path for Python parser (variable registry overrides)
export WORKFLOW_CONFIG="$CONFIG_FILE"
export NAMELIST_DIR
export JSON_DIR

# Include common functions
FUNCTIONS="$SCRIPTS_PATH/qlc_common_functions.sh"
source $FUNCTIONS
export  FUNCTIONS

# Log workflow configuration details
log "Workflow configuration: $CONFIG_FILE"
log "Runtime directory: $QLC_DIR"

# Check if the required parameters are provided
if [ $# -eq 0 ]; then
  log  "________________________________________________________________________________________"
  log  "QLC (Quick Look Content) - Interactive Execution"
  log  "----------------------------------------------------------------------------------------"
  log  " "
  log  "Usage:"
  log  "  qlc <exp1> [exp2 ...] <start_date> <end_date> [config] [-class=xx|xx,yy,...]"
  log  " "
  log  "Arguments:"
  log  "  <exp1> [exp2 ...]  One or more experiment identifiers (minimum 1)"
  log  "  <start_date>       Start date in YYYY-MM-DD format"
  log  "  <end_date>         End date in YYYY-MM-DD format"
  log  "  [config]           Configuration option (default: 'default')"
  log  " "
  log  "Options:"
  log  "  -class=xx          Override MARS class for all experiments (e.g., -class=nl)"
  log  "  -class=xx,yy,zz    Override MARS class per experiment (must match count)"
  log  "  -vars=var1,var2    MARS retrieval: override variable groups (e.g., -vars=PM2p5_sfc,O3_pl)"
  log  "  -vars=@GROUP       MARS retrieval: use variable groups (e.g., -vars=@EAC5_SFC,@EAC5_PL)"
  log  "  -nml=nml1,nml2     Legacy namelist override (backward compatible)"
  log  "  -scripts=S1,S2,... Override workflow scripts (e.g., -scripts=A1-MARS,B1-CONV,B2-PREP)"
  log  " "
  log  "Station Analysis / qlc-py Options (qpy, evaltools):"
  log  "  --myvar=\"spec\"      Obs-mod variable mapping spec (pipe format, new in v1.0.2):"
  log  "                       \"DisplayName|modVAR[,op,val]|obsVAR[,op,val]|targetUNIT[,unitFAC]\""
  log  "                       Operators: * / + -   applied at load time on model or obs side"
  log  "                       Enables user-defined unit conversion for any variable (incl. custom)."
  log  "                       Applied across all active regions in one run."
  log  "  --network=net[,net] Station network(s) to activate (overrides ACTIVE_REGIONS)"
  log  "  --region=code       Map region override (overrides REGION_*_PLOT_REGION)"
  log  "  --user=name         Use group/display name instead of Unix username"
  log  " "
  log  "Expert Mode (direct GRIB parameter specification):"
  log  "  -param=p1,p2,...   GRIB parameter codes (e.g., -param=72.210,73.210)"
  log  "  -myvar=v1;v2,...   Display names when paired with -param= (e.g., -myvar=PM2.5;PM10)"
  log  "                     Or standalone with GRIB code: -myvar=PM2.5,210073;O3,210203"
  log  "                     (Note: different from --myvar= pipe format used in qpy/evaltools)"
  log  "  -levtype=t1,t2,... Level types: sfc,pl,ml (single or per-var, e.g., -levtype=sfc)"
  log  "  -ncvar=n1,n2,...   NetCDF var names (optional, defaults to 'unknown' for auto-detect)"
  log  " "
  log  "MARS Parameter Overrides:"
  log  "  -grid=x.x/x.x      Override MARS grid resolution (e.g., -grid=0.5/0.5)"
  log  "  -step=x/to/y/by/z  Override MARS forecast steps (e.g., -step=0/to/48/by/6)"
  log  "  -time=HH:MM:SS     Override MARS forecast base time (e.g., -time=12:00:00)"
  log  "  -levelist=levels   Override MARS pressure/model levels (e.g., -levelist=100/500/850)"
  log  " "
  log  "Workflow Options:"
  log  "  Available workflows in ~/qlc/config/workflows/:"
  log  " "
  log  "  mars               Data retrieval from MARS only (no processing)"
  log  "  test               Short analysis example for testing QLC functionality"
  log  "  qpy                qlc-py station analysis (multi-region, maps, time series)"
  log  "  evaltools          Advanced statistics with Taylor diagrams (requires qpy)"
  log  "  pyferret           3D global/vertical analysis using PyFerret diff plots"
  log  "  eac5               Production analysis (comprehensive species and plots)"
  log  "  aifs               AIFS model evaluation workflow"
  log  "  ver0d              Ver0D processing (under development)"
  log  " "
  log  "Multi-Experiment Support:"
  log  "  QLC supports comparing any number of experiments (N >= 1):"
  log  "  - Single:  qlc exp1 2018-12-01 2018-12-21 qpy"
  log  "  - Two:     qlc exp1 exp2 2018-12-01 2018-12-21 qpy"
  log  "  - Three+:  qlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy"
  log  " "
  log  "Examples:"
  log  "  # Show available configurations"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21"
  log  " "
  log  "  # Data retrieval with GRIB / NetCDF"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 mars"
  log  " "
  log  "  # Quick test analysis"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 test"
  log  " "
  log  "  # Station analysis with qlc-py"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 qpy"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 qpy --myvar=\"O3|go3|O3|ug/m3;PM2.5|pm2p5|PM2.5|ug/m3\""
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 qpy --myvar=\"MyVar|myvar,*,0.001|obs|N/A\" --network=EU_AIRBASE"
  log  " "
  log  "  # Advanced statistics with evaltools"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 evaltools"
  log  " "
  log  "  # 3D analysis with PyFerret"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 pyferret"
  log  " "
  log  "  # Production analysis (comprehensive)"
  log  "  qlc exp1 exp2 2018-12-01 2018-12-21 eac5"
  log  " "
  log  "  # Override MARS class"
  log  "  qlc exp1 exp2 exp3 2019-01-01 2019-12-31 eac5 -class=de"
  log  " "
  log  "  # Override variables (new registry system)"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -vars=PM2p5_sfc,O3_pl"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -vars=@EAC5_SFC,@EAC5_PL"
  log  " "
  log  "  # Override MARS parameters"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -vars=@EAC5_SFC -grid=0.5/0.5 -step=0/to/48/by/6"
  log  " "
  log  "  # Expert mode (direct parameter specification)"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -param=72.210,73.210 -myvar=PM2.5;PM10"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -param=999.210 -myvar=NEW_VAR -levtype=pl -grid=0.5/0.5"
  log  " "
  log  "  # Expert mode with registry variables (additive)"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -vars=@EAC5_SFC -param=999.210 -myvar=TEST -levtype=sfc"
  log  " "
  log  "  # Combined overrides"
  log  "  qlc exp1 exp2 2019-01-01 2019-12-31 eac5 -vars=PM2p5_sfc,O3_sfc -class=de,rd -grid=0.25/0.25"
  log  " "
  log  "Data Retrieval Behavior:"
  log  "  - Auto-retrieves data if workflow includes A1 script"
  log  "  - Checks data_retrieved_*.flag files; only retrieves if missing"
  log  "  - If data needed: exits after A1 with message to re-run command"
  log  "  - If data present: continues with all subscripts automatically"
  log  "  - Data based on MARS namelists (~/qlc/config/nml/) and"
  log  "    MARS_RETRIEVALS parameter mapping (in workflow config)"
  log  " "
  log  "For batch submission, use: sqlc <exp1> [exp2 ...] <dates> [config]"
  log  "For help: qlc --help (or just 'qlc' without arguments in Python wrapper)"
  log  " "
  log  "See: https://docs.researchconcepts.io/qlc/latest/reference/changelog"
  log  "© 2018-2026 ResearchConcepts io GmbH. All Rights Reserved."
  log  "Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>"
  log  "Documentation     : https://docs.researchconcepts.io/qlc/latest"
  log  "________________________________________________________________________________________"
  log  "End   ${SCRIPT} at `date`"
  log  "________________________________________________________________________________________"
  exit 0
fi

# Check if the configuration file exists
if [ -f "$CONFIG_FILE" ]; then
	# Read and export the variables from the configuration file
	# ----------------------------------------------------------------------------------------
	# Log the active configuration settings (variable assignments only, excluding bash control structures)
	log "Active configuration settings from: ${CONFIG_FILE}"
	grep -v '^\s*#\|^\s*$' "$CONFIG_FILE" | \
	  grep -v '^\s*{\|^\s*}\|^\s*if\|^\s*else\|^\s*fi\|^\s*source\|^\s*unset\|^\s*_qlc_conf=' | \
	  grep '=' | \
	  while IFS= read -r line; do
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

# Apply -scripts= override if provided.
# qlc_main.sh scans $@ directly for -scripts= (single-dash, bash-visible args).
# --scripts= (double-dash) is filtered out by Python and propagated via QLC_CLI_SCRIPTS instead.
if [ -n "$scripts_option" ]; then
  scripts_spec="${scripts_option#-scripts=}"
  IFS=',' read -ra SUBSCRIPT_NAMES <<< "$scripts_spec"
  log "Workflow scripts overridden via command line: ${SUBSCRIPT_NAMES[*]}"
elif [ -n "${QLC_CLI_SCRIPTS:-}" ]; then
  IFS=',' read -ra SUBSCRIPT_NAMES <<< "${QLC_CLI_SCRIPTS}"
  log "Workflow scripts overridden via --scripts=: ${SUBSCRIPT_NAMES[*]}"
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

  # Pre-flight check for A1-MARS: Skip if all completion flags are present
  # Python wrapper already checked this - just use the result
  a1_mars_check_retrievals=()
  if [ "$name" == "A1-MARS" ]; then
    # Display variable mapping information (if available from Python wrapper)
    if [ -n "${QLC_A1_MARS_VAR_INFO:-}" ]; then
      log "========================================================================================"
      log "MARS Variable Mapping Information"
      log "========================================================================================"
      
      # Parse multi-line variable info (format: VAR_ID|DISPLAY_NAME|NETCDF_NAME|GRIB_PARAM|UNIT|LEVTYPE|DATA_SOURCE)
      while IFS='|' read -r var_id display_name netcdf_name grib_param unit levtype data_source description; do
        log "Variable ID:       $var_id"
        log "  Display Name:    $display_name"
        log "  NetCDF Name:     $netcdf_name"
        log "  GRIB Parameter:  $grib_param"
        log "  Unit:            $unit"
        log "  Level Type:      $levtype"
        log "  Data Source:     $data_source"
        log "  Description:     $description"
        log "----------------------------------------------------------------------------------------"
      done <<< "$QLC_A1_MARS_VAR_INFO"
      
      log "========================================================================================"
    fi
    
    # Check if Python wrapper already determined data is complete
    if [ "${QLC_A1_MARS_COMPLETE}" == "1" ]; then
      log "========================================================================================"
      log "MARS Data Already Retrieved - Skipping A1-MARS"
      log "========================================================================================"
      log "All required data is present (${QLC_A1_MARS_FLAG_COUNT} completion flags verified by Python wrapper)"
      log "Skipping MARS retrieval and continuing with next script..."
      log "========================================================================================"
      # Signal to batch script that A1-MARS was skipped (data already present)
      export QLC_A1_MARS_SKIPPED=1
      continue  # Skip to next subscript
    fi
    
    # Python wrapper determined data is incomplete - proceed with A1-MARS
    log "Some MARS data missing or not yet verified"
    log "Proceeding with A1-MARS script execution..."
  fi

  if [ -f "$SCRIPTS_PATH/$script_name" ]; then
    # Build subscript arguments: use experiments_original so that experiment IDs are
    # forwarded to subscripts for directory naming even in obs-only / mod-only mode,
    # where experiments[] is cleared for processing but experiments_original[] is kept.
    subscript_args=("${experiments_original[@]}" "$start_date" "$end_date")
    [ -n "$config_arg" ] && subscript_args+=("$config_arg")
    [ -n "$class_option" ] && subscript_args+=("$class_option")
    [ -n "$vars_option" ] && subscript_args+=("$vars_option")
    [ -n "$nml_option" ] && subscript_args+=("$nml_option")
    for expert_opt in "${expert_mode_options[@]}"; do
      subscript_args+=("$expert_opt")
    done
    for mars_opt in "${mars_options[@]}"; do
      subscript_args+=("$mars_opt")
    done
    
    # Call the subscript
    log   "$SCRIPTS_PATH/$script_name" "${subscript_args[@]}"
          "$SCRIPTS_PATH/$script_name" "${subscript_args[@]}"

    # After A1-MARS: Check if MARS data retrieval is complete
    # If A1-MARS was just executed and there are more subscripts to run,
    # check download status using flag files (not grb existence)
    if [ "$name" == "A1-MARS" ] && [ ${#SUBSCRIPT_NAMES[@]} -gt 1 ]; then
      log "Checking MARS data retrieval status using flag files..."
      
      # Convert dates to compact format (consistent with other scripts)
      sDate="${start_date//[-:]/}"
      eDate="${end_date//[-:]/}"
      mDate="$sDate-$eDate"
      
      # Load variables for post-A1 check.
      # When QLC_CLI_MYVAR is set we use the variable names directly — they are plain
      # display names (e.g. pl_NH4_as) that the Python registry cannot resolve without
      # an accompanying GRIB code, so calling expand_variable_spec on them would fail.
      if [ -n "${QLC_CLI_MYVAR:-}" ]; then
        IFS=';' read -ra MARS_RETRIEVALS <<< "${QLC_CLI_MYVAR}"
        log "Post-A1 check: using CLI variable override (${#MARS_RETRIEVALS[@]} var(s)): ${MARS_RETRIEVALS[*]}"
        for _cli_var in "${MARS_RETRIEVALS[@]}"; do
          a1_mars_check_retrievals+=("$_cli_var")
        done
      else
        load_variable_registry
        parse_variable_and_mars_options "$@"
        while IFS= read -r var; do
          a1_mars_check_retrievals+=("$var")
        done < <(get_required_mars_variables)
      fi
      
      log "Checking retrieval status for ${#a1_mars_check_retrievals[@]} variable(s)"
      
      # Check for download and completion flags
      downloads_in_progress=false
      missing_retrievals=false
      download_flag_list=()
      missing_flag_list=()
      
      for exp in "${experiments[@]}"; do
        for var_name in "${a1_mars_check_retrievals[@]}"; do
          completion_flag="$MARS_RETRIEVAL_DIRECTORY/$exp/data_retrieved_${exp}_${mDate}_${var_name}.flag"
          download_flag="$MARS_RETRIEVAL_DIRECTORY/$exp/data_retrieved_${exp}_${mDate}_${var_name}.download"
          job_id_file="$MARS_RETRIEVAL_DIRECTORY/$exp/data_retrieved_${exp}_${mDate}_${var_name}.id"
          
          if [ -f "$completion_flag" ]; then
            # Data retrieved successfully
            log "Completed: $exp / $var_name"
          elif [ -f "$download_flag" ]; then
            # Download in progress (job running)
            log "In progress (running): $exp / $var_name"
            downloads_in_progress=true
            download_flag_list+=("$exp / $var_name")
          elif [ -f "$job_id_file" ]; then
            # Job submitted (queued or starting)
            job_id=$(cat "$job_id_file" 2>/dev/null || echo "unknown")
            log "In progress (queued/submitted): $exp / $var_name (Job ID: $job_id)"
            downloads_in_progress=true
            download_flag_list+=("$exp / $var_name (Job $job_id)")
          else
            # Check if batch script was created (no flags yet)
            batch_script="$MARS_RETRIEVAL_DIRECTORY/$exp/mars_${exp}_${var_name}.sh"
            if [ -f "$batch_script" ]; then
              log "Batch script ready: $exp / $var_name"
              missing_retrievals=true
              missing_flag_list+=("$exp / $var_name (batch script created)")
            else
              log "Not started: $exp / $var_name"
              missing_retrievals=true
              missing_flag_list+=("$exp / $var_name")
            fi
          fi
        done
      done
      
      # Determine action based on flag status
      if [ "$downloads_in_progress" = true ]; then
        log  "========================================================================================"
        log  "MARS Data Retrieval In Progress"
        log  "========================================================================================"
        log  "Status: MARS retrieval jobs have been submitted and are running/queued"
        log  " "
        log  "Jobs submitted or running:"
        for item in "${download_flag_list[@]}"; do
          log  "  - $item"
        done
        log  " "
        log  "Check queue status: squeue -u $USER -n 'mars_*'"
        log  " "
        log  "Please wait for MARS jobs to complete, then re-run the same command:"
        log  " "
        log  "  qlc ${experiments[*]} $start_date $end_date $config_arg"
        log  " "
        log  "The system will automatically continue with processing once all downloads complete."
        log  " "
        log  "Note: Job states transition as follows:"
        log  "  .id file (queued) → .download file (running) → .flag file (completed)"
        log  "========================================================================================"
        log  "End ${SCRIPT} at `date`"
        log  "________________________________________________________________________________________"
        exit 0  # Clean exit - not an error, just waiting for data
      elif [ "$missing_retrievals" = true ]; then
        log  "========================================================================================"
        log  "MARS Retrieval Batch Scripts Created"
        log  "========================================================================================"
        log  "Batch scripts have been generated for MARS data retrieval."
        log  " "
        log  "Status:"
        for item in "${missing_flag_list[@]}"; do
          log  "  $item"
        done
        log  " "
        log  "Next steps:"
        log  "  1. Transfer batch scripts to HPC system (if not already there)"
        log  "  2. Submit batch jobs: sbatch $MARS_RETRIEVAL_DIRECTORY/<exp>/mars_*.sh"
        log  "  3. Monitor job status: squeue -u \$USER -n 'mars_*'"
        log  "  4. After jobs complete successfully, re-run the same command:"
        log  " "
        log  "     qlc ${experiments[*]} $start_date $end_date $config_arg"
        log  " "
        log  "The system will detect completed retrievals (via .flag files) and automatically"
        log  "continue with the remaining processing steps."
        log  "========================================================================================"
        log  "End ${SCRIPT} at `date`"
        log  "________________________________________________________________________________________"
        exit 0  # Clean exit - batch scripts created, waiting for user to submit jobs
      else
        log "All MARS data retrievals complete. Continuing with processing..."
      fi
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

