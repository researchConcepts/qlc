# QLC module package init
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

def detect_qlc_runtime():
    """
    Detects which QLC runtime to use based on environment.
    Priority:
    1. QLC_HOME environment variable (explicit override)
    2. Auto-detection based on conda environment
    3. Default to ~/qlc
    """
    # Priority 1: Explicit override
    if 'QLC_HOME' in os.environ:
        qlc_home = os.environ['QLC_HOME']
        return qlc_home, "explicit"
    
    # Priority 2: Auto-detect from conda environment
    conda_env = os.environ.get('CONDA_DEFAULT_ENV', '')
    bin_dir = str(Path(sys.executable).parent)
    
    if 'qlc-dev' in conda_env or 'qlc-dev' in bin_dir:
        # Development environment detected
        qlc_home = str(Path.home() / "qlc-dev-run")
        if Path(qlc_home).exists():
            return qlc_home, "conda-dev"
    
    # Priority 3: Default to production
    qlc_home = str(Path.home() / "qlc")
    return qlc_home, "default"

def run_shell_driver():
    """
    Finds and executes qlc_main.sh, capturing its output for logging.
    This acts as the entry point for the 'qlc' command.
    """
    # Handle --version and --help flags
    # Show help if no arguments provided
    if len(sys.argv) == 1:
        sys.argv.append('--help')
    
    if '--version' in sys.argv or '-V' in sys.argv:
        try:
            from qlc.py.version import __version__, __release_date__
            
            # Detect installation type
            qlc_pkg_path = Path(__file__).parent.parent.resolve()
            if 'site-packages' in str(qlc_pkg_path) and '.local' in str(qlc_pkg_path):
                install_type = "PyPI (User)"
            elif 'site-packages' in str(qlc_pkg_path):
                install_type = "PyPI (System)"
            elif '.conda' in str(qlc_pkg_path) or 'conda' in str(qlc_pkg_path):
                install_type = "Development (Conda)"
            else:
                install_type = "Development (Local)"
            
            # Detect runtime
            qlc_home, detection_method = detect_qlc_runtime()
            
            print(f"QLC (Quick Look Content) version {__version__} BETA [{install_type}]")
            print(f"Release date: {__release_date__}")
            print(f"Runtime: {qlc_home} ({detection_method})")
            print(f"Package: {qlc_pkg_path}")
            print("An Automated Model-Observation Comparison Suite")
            print("Optimized for CAMS datasets")
            print("")
            print("⚠️  BETA RELEASE: Under development, requires further testing")
            print("© ResearchConcepts io GmbH")
            sys.exit(0)
        except ImportError:
            print("QLC version information not available")
            sys.exit(1)
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""
QLC (Quick Look Content) - An Automated Model-Observation Comparison Suite
Optimized for CAMS datasets

⚠️  BETA RELEASE: Under development, requires further testing

Usage:
  qlc <exp1> [exp2 ...] <start_date> <end_date> [config]
  qlc --version | -V
  qlc --help | -h

Arguments:
  <exp1> [exp2 ...]  One or more experiment identifiers (minimum 1)
  <start_date>       Start date in YYYY-MM-DD format
  <end_date>         End date in YYYY-MM-DD format
  [config]           Configuration option (see below)

Configuration Options:
  Each subdirectory in ~/qlc/config can be used as a config option:
  
  default (or mars)  MARS data retrieval only (default if not specified)
  qpy                qlc-py collocation & time series plots
  evaltools          Advanced statistics with Taylor diagrams
  eac5               EAC5/CAMS reanalysis analysis (K1 namelist)
  pyferret           PyFerret visualization integration
  ver0d              Ver0D processing (ATOS/IDL-based)

Multi-Experiment Support:
  QLC supports comparing any number of experiments (N >= 1):
  - Single:  qlc exp1 2018-12-01 2018-12-21 qpy
  - Two:     qlc exp1 exp2 2018-12-01 2018-12-21 qpy
  - Three+:  qlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy

Multi-Region Support:
  Configure MULTI_REGION_MODE=true in config files to process
  multiple regions (EU, US, Asia) in a single run with region-specific
  observation networks and variable sets.

Options:
  --version, -V    Show version and installation information
  --help, -h       Show this help message

Examples:
  # Two experiments with qlc-py collocation and time series
  qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

  # Three experiments with evaltools statistics and Taylor diagrams
  qlc exp1 exp2 exp3 2018-12-01 2018-12-21 evaltools

  # EAC5 reanalysis validation (K1 namelist: 10 variables)
  qlc b2ro b2rn 2018-12-01 2018-12-21 eac5

  # Multi-experiment comparison with evaltools
  qlc exp1 exp2 exp3 2018-12-01 2018-12-21 evaltools

  # PyFerret visualization
  qlc b2ro b2rn 2018-12-01 2018-12-21 pyferret

  # Ver0D processing (ATOS/IDL-based)
  qlc b2ro b2rn 2018-12-01 2018-12-21 ver0d

  # MARS data retrieval only (no analysis/processing)
  qlc b2ro b2rn 2018-12-01 2018-12-21 mars

Data Retrieval:
  QLC automatically handles data retrieval based on active subscripts:
  - If qlc_A1.sh is active: automatically retrieves missing data
  - Checks data_retrieval flag in Results directory
  - Only submits retrieval if data missing or not in progress
  - 'mars' config: retrieves data ONLY, skips all analysis
  - Other configs: retrieve data if needed, then process

  Data retrieved based on MARS namelist (e.g., mars_K1_sfc.nml)
  and parameter mapping (e.g., K1_sfc in MARS_RETRIEVALS)

Related Commands:
  qlc-py                  Standalone Python processing engine
  qlc-extract-stations    Extract and filter observation stations
  qlc-install             Install/setup QLC runtime environment
  sqlc                    Submit QLC job to SLURM batch scheduler

Documentation:
  Usage Guide:    ~/qlc/doc/USAGE.md
  Installation:   ~/qlc/doc/INSTALL_DEV.md
  Contributing:   ~/qlc/doc/CONTRIBUTING.md
  Online:         https://pypi.org/project/rc-qlc/
  Online:         https://github.com/researchConcepts/qlc
        """)
        sys.exit(0)
    
    # Correctly locate the 'sh' directory relative to the package installation
    sh_dir = os.path.join(os.path.dirname(__file__), '..', 'sh')
    script = os.path.join(sh_dir, "qlc_main.sh")

    # Determine QLC runtime directory using intelligent detection
    qlc_home_str, detection_method = detect_qlc_runtime()
    log_dir = os.path.join(qlc_home_str, "log")
    os.makedirs(log_dir, exist_ok=True)
    
    # Log which runtime is being used (only in verbose mode or for dev)
    if detection_method == "conda-dev":
        print(f"[QLC-DEV] Using development runtime: {qlc_home_str}")

    # Create a timestamped log file for the shell script's output
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file_path = os.path.join(log_dir, f"qlc_shell_main_{timestamp}.log")
    print(f"[QLC Wrapper] Logging shell script output to: {log_file_path}")

    try:
        # Use a list of strings for Popen
        command = [str(script)] + sys.argv[1:]
        
        with open(log_file_path, 'w', encoding='utf-8') as log_file:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1, # Line-buffered
                universal_newlines=True
            )
            
            # Real-time stream processing
            for line in process.stdout:
                # Write to file without adding a newline, as 'line' already has one
                log_file.write(line)
                # Print to console, stripping the newline to avoid double spacing
                sys.stdout.write(line)
            
            process.wait()

        if process.returncode != 0:
            print(f"\n[ERROR] Shell script exited with non-zero code: {process.returncode}", file=sys.stderr)
            sys.exit(process.returncode)

    except FileNotFoundError:
        print(f"Error: Could not find the qlc_main.sh script at {script}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)


def run_batch_driver():
    """
    Finds and executes qlc_batch.sh, capturing its output for logging.
    This acts as the entry point for the 'sqlc' command.
    """
    try:
        sh_dir = Path(__file__).resolve().parent.parent / "sh"
        script_path = sh_dir / "qlc_batch.sh"
        if not script_path.is_file():
            print(f"[ERROR] Batch script not found at: {script_path}", file=sys.stderr)
            sys.exit(1)

        # Ensure the script is executable
        script_path.chmod(script_path.stat().st_mode | 0o111)

        # Determine QLC runtime directory using intelligent detection
        qlc_home_str, detection_method = detect_qlc_runtime()
        log_dir = Path(qlc_home_str) / "log"
        log_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file_path = log_dir / f"sqlc_shell_main_{timestamp}.log"
        print(f"[QLC Batch Wrapper] Logging shell script output to: {log_file_path}")

        command = [str(script_path)] + sys.argv[1:]
        
        with open(log_file_path, 'w', encoding='utf-8') as log_file:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            for line in process.stdout:
                log_file.write(line)
                sys.stdout.write(line)
            
            process.wait()

        if process.returncode != 0:
            print(f"\n[ERROR] Batch script exited with non-zero code: {process.returncode}", file=sys.stderr)
            sys.exit(process.returncode)

    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)
