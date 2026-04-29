#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC CLI Module: Command-Line Interface Entry Points

Part of QLC (Quick Look Content) v1.0.2
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/

Description:
    Provides Python entry points for QLC command-line tools including
    qlc (main workflow), qlc-py (standalone), and sqlc (batch submission).
    Handles argument parsing and shell script execution.

Copyright (c) 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# Import Cythonizable core functions
from qlc.py.qlc_wrapper import (
    detect_qlc_runtime,
    get_compatible_bash,
    extract_qlc_arguments,
    prepare_mars_requests,
    build_bash_command_args
)


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
            else:
                install_type = "Development (Local)"
            
            # Detect runtime
            qlc_home, detection_method = detect_qlc_runtime()
            
            print(f"QLC (Quick Look Content) version {__version__} [{install_type}]")
            print("An Automated Model-Observation Comparison Suite Optimized for CAMS datasets")
            print("")
            print(f"Release date: {__release_date__}")
            print(f"Runtime: {qlc_home} ({detection_method})")
            print(f"Package: {qlc_pkg_path}")
            print("Documentation: https://docs.researchconcepts.io/qlc/latest")
            print("               https://github.com/researchconcepts/qlc")
            print("")
            print("See: https://docs.researchconcepts.io/qlc/latest/reference/changelog")
            print("© 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.")
            print("Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>")
            sys.exit(0)
        except ImportError:
            print("QLC version information not available")
            sys.exit(1)
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""
========================================================================================
QLC - Quick Look Content
========================================================================================

Usage (positional):
  qlc <exp1> [exp2 ...] <start_date> <end_date> <workflow> [options]

Usage (named arguments):
  qlc --exps=<exp1>[,exp2,...] --start_date=<date> --end_date=<date> --workflow=<name> [options]

Both syntaxes can be mixed. Both - and -- prefixes are accepted for all options.

Arguments:
  <exp1> [exp2 ...]          One or more experiment identifiers (positional)
  --exps=exp1[,exp2,...]     Same as above using named syntax
  <start_date>               Start date YYYY-MM-DD (positional)
  --start_date=YYYY-MM-DD    Same using named syntax
  <end_date>                 End date YYYY-MM-DD (positional)
  --end_date=YYYY-MM-DD      Same using named syntax
  <workflow>                 Workflow name, e.g. qpy, aifs, eac5 (positional)
  --workflow=<name>          Same using named syntax

Processing options:
  --obs-only                 Analyse observations only (skip model download/processing)
  --mod-only                 Analyse model results only (skip observation processing)
  --use_grib=true|false      Override USE_GRIB_SOURCE for D1-ANAL only.
                             true:  read GRIB files directly from ~/qlc/Results/<expN>
                                    (use with --scripts=D1-ANAL,Z1-XPDF to skip B1-CONV/B2-PREP)
                             false: read NetCDF files from ~/qlc/Analysis/<expN>
                                    (requires B1-CONV,B2-PREP to have run)
  -class=xx[,yy]             Override MARS class per experiment (e.g. -class=nl or -class=nl,rd)
  --exp_labels=L1[,L2,...]   Display labels for experiments (comma-separated, same order as exps).
                             Quotes optional unless labels contain spaces: --exp_labels="Run 1,Run 2"
  --scripts=S1[,S2,...]      Restrict which QLC scripts to run (e.g. --scripts=D1-ANAL,Z1-XPDF)
  --user=<label>             Override system username in PDF report titles/footers.
                             Example: --user=cams

Variable overrides — Stage 1 (MARS retrieval: A1-MARS, eac5, aifs, pyferret):
  --myvar=<spec>[;<spec>]    Override MARS_RETRIEVALS from workflow config.
                             Overrides (not adds to) both the global MARS_RETRIEVALS and any
                             REGION_*_MARS_RETRIEVALS entries — the CLI value is authoritative.
                             Each spec: [level_type_]display_name[,GRIB_param]  OR  @GROUP
                             Variables must be defined in [VARIABLE_REGISTRY] of the active
                             workflow config or in a referenced @GROUP — otherwise QLC will
                             exit with a clear error. Use 'qlc-vars list' to see available names.
                             IMPORTANT: quote the value when using semicolons in a shell:
                               --myvar="sfc_T2m,167"
                               --myvar="sfc_T2m,167;pl_T,130"
                               --myvar="@AIFS_SFC;pl_HNO3"
  --param=<grib>[;<grib>]    Per-experiment GRIB param override (A1-MARS only).
                             Separator rules: ';' between variables (matches --myvar= order),
                                              ',' between experiments (matches --exps= order).
                             Single entry broadcasts to all experiments.
                             Both GRIB notations accepted: 249.210 and 210249.
                             IMPORTANT: always quote the value; requires --myvar= to be set:
                               --myvar="pl_NH4_as;pl_NO3_as" --param="35.212,249.210;36.212,247.210"

Variable overrides — Stage 2 (mod-obs mapping: D1-ANAL / qpy, evaltools) [new in v1.0.3]:
  --obsmap="DisplayName|modVAR[,op,val]|obsVAR[,op,val]|targetUNIT[,unitFAC]"
                             Pipe-format variable spec for station collocation. Overrides
                             REGION_*_VARIABLES for every active network (--network=) in a
                             single run — no workflow edits needed.
                             Multiple variables separated by ';' inside the quoted string.
                             Arithmetic operators: * / + -  applied at load time (model or obs).
                             unitFAC: explicit scale factor (alternative to automatic conversion).
                             Use for variables not yet in qlc's built-in unit table, custom
                             model diagnostics, or quick scaling tests.
                             Examples:
                               --obsmap="O3|go3|O3|ug/m3"                    O3: auto kg/kg -> ug/m3
                               --obsmap="PM2.5|pm2p5|PM2.5|ug/m3"            PM2.5: auto kg/m3 -> ug/m3
                               --obsmap="T2m|2t|temp|degC"                   T2m: auto K -> degC
                               --obsmap="MyVar|myvar,*,0.001|obs|N/A"         custom: scale model x0.001
                               --obsmap="MyVar|myvar|obs|unit,1e3"            custom: unitFAC=1e3
                               --obsmap="O3|go3|O3|ug/m3;PM2.5|pm2p5|PM2.5|ug/m3"  multi-variable
                             Typical paired use with --myvar= for a complete override:
                               --myvar="sfc_O3;sfc_PM2.5" \
                                 --obsmap="O3|go3|O3|ug/m3;PM2.5|pm2p5|PM2.5|ug/m3"

Network and region overrides (D1-ANAL only):
  --network=CODE[,CODE2,...] Override ACTIVE_REGIONS — which station networks to process.
                             Network codes must match REGION_*_NAME entries in the workflow config.
                             Example: --network=BRAZIL_INMET,US_CASTNET
  --region=GEO[,GEO2,...]   Override geographic plot extent for all active networks.
                             Comma-separated plot region codes (e.g., EU, SA, GLOBE, NH).
                             Each active network is run once per listed plot region.
                             When multiple regions are given, output dirs get a _REGION suffix.
                             Example: --region=SA          (single, same output name)
                             Example: --region=SA,GLOBE    (two runs: BRAZIL_INMET_SA/, BRAZIL_INMET_GLOBE/)
  --station_file=<path>      Override station CSV file for all active networks.
                             Tilde (~) is expanded to home directory.

MARS request overrides:
  -grid=<value>              Override MARS GRID parameter
  -step=<value>              Override MARS STEP
  -time=<value>              Override MARS TIME
  -levelist=<value>          Override MARS LEVELIST

Examples:
  # Positional syntax (classic)
  qlc exp1 exp2 2018-12-01 2018-12-21 test
  qlc exp1 exp2 2018-12-01 2018-12-21 test --obs-only --network=EU_EBAS_Daily
  qlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,nl

  # Named syntax (both - and -- prefix accepted; same options apply to sqlc)
  qlc --exps=exp1,exp2 --start_date=2018-12-01 --end_date=2018-12-21 --workflow=test
  qlc --exps=exp1,exp2 --start_date=2018-12-01 --end_date=2018-12-21 --workflow=test --obs-only

  # GRIB variable overrides (MARS retrieval context; quotes required when using ; in shell)
  qlc exp1 exp2 2018-12-01 2018-12-21 test --myvar="sfc_T2m,167"
  qlc exp1 exp2 2018-12-01 2018-12-21 test --myvar="sfc_T2m,167;pl_T,130"
  qlc exp1 exp2 2018-12-01 2018-12-21 test --network=EU_EBAS_Daily,US_CASTNET
  qlc exp1 exp2 2018-12-01 2018-12-21 test --network=BRAZIL_INMET --region=SA,GLOBE \\
      --station_file=~/qlc/config/station_locations/test.csv

  # Per-experiment GRIB param override (e.g. AER vs HAMM7 comparison)
  qlc exp1 exp2 2018-12-01 2018-12-21 test -class=nl,rd \\
      --myvar="pl_NH4_as;pl_NO3_as" --param="35.212,249.210;36.212,247.210"

  # Obs-mod pipe-format (qpy / evaltools): one spec across all active networks [new in v1.0.2]
  qlc exp1 exp2 2018-12-01 2018-12-21 qpy --myvar="O3|go3|O3|ug/m3;PM2.5|pm2p5|PM2.5|ug/m3"
  qlc exp1 exp2 2018-12-01 2018-12-21 qpy --myvar="MyVar|myvar,*,0.001|obs|N/A" --network=EU_AIRBASE -class=rd

  # Full named syntax
  qlc --exps=exp1,exp2 --start_date=2018-12-01 --end_date=2018-12-21 --workflow=test \\
      --myvar="sfc_T2m,167;pl_T,130" -class=nl,nl --network=EU_EBAS_Daily,US_CASTNET

Other commands:
  qlc -V / --version         Show version information
  qlc-vars search O3         Search variable table
  sqlc ...                   Batch submission (HPC/SLURM), accepts same options as qlc

Results:
  ~/qlc/Results        GRIB data (MARS download)
  ~/qlc/Analysis       NetCDF processed data
  ~/qlc/Plots          Generated plots
  ~/qlc/Presentations  PDF reports

For more information:
  Quick Start    : ~/qlc/doc/QuickStart.md
  Documentation  : https://docs.researchconcepts.io/qlc
  Getting Started: https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/

See: https://docs.researchconcepts.io/qlc/latest/reference/changelog
© 2018-2026 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
========================================================================================
        """)
        sys.exit(0)
    
    # Correctly locate the 'bin' directory relative to the package installation
    bin_dir = os.path.join(os.path.dirname(__file__), '..', 'bin')
    script = os.path.join(bin_dir, "qlc_main.sh")

    # Determine QLC runtime directory using intelligent detection
    qlc_home_str, detection_method = detect_qlc_runtime()
    log_dir = os.path.join(qlc_home_str, "log")
    os.makedirs(log_dir, exist_ok=True)
    
    # Log which runtime is being used (only in verbose mode or for dev)
    timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if detection_method == "dev":
        print(f"[{timestamp_str}] [QLC-DEV] Using development runtime: {qlc_home_str}")

    # Create a timestamped log file for the shell script's output
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file_path = os.path.join(log_dir, f"qlc_shell_main_{timestamp}.log")
    print(f"[{timestamp_str}] [QLC] Logging shell script output to: {log_file_path}")

    try:
        # Get compatible bash (prefers venv bash, falls back to system bash >= 3.2)
        bash_path, bash_version, bash_source = get_compatible_bash()
        
        # Always log which bash is being used
        timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp_str}] [QLC] Using bash: {bash_version} ({bash_source})")
        
        # Inform user if using system bash (optional upgrade available)
        if bash_source == "system":
            print(f"[INFO] For best compatibility, install QLC-managed bash: qlc-install-tools --install-bash")
        
        # Extract arguments for Python-side processing
        args = extract_qlc_arguments(sys.argv)
        
        # Prepare MARS requests (if applicable)
        prepare_mars_requests(qlc_home_str, args)
        
        # Build bash-compatible command line arguments
        # This converts named arguments (--exp_ids=, --start_date=, etc.) to positional format
        bash_args = build_bash_command_args(args, sys.argv)
        
        # Execute bash script with bash-compatible arguments
        command = [bash_path, str(script)] + bash_args
        
        with open(log_file_path, 'w', encoding='utf-8') as log_file:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,  # Line-buffered
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


def run_python_driver():
    """
    Alias for qlc-py command (backwards compatibility).
    The previous name was 'qlc-python', now it's 'qlc-py'.
    This function redirects to the main qlc-py entry point.
    """
    from qlc.cli.qlc_py_main import main
    main()


def run_batch_driver():
    """
    Finds and executes qlc_batch.sh, capturing its output for logging.
    This acts as the entry point for the 'sqlc' command.
    """
    try:
        bin_dir = Path(__file__).resolve().parent.parent / "bin"
        script_path = bin_dir / "qlc_batch.sh"
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
        timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_file_path = log_dir / f"sqlc_shell_main_{timestamp}.log"
        print(f"[{timestamp_str}] [QLC Batch] Logging shell script output to: {log_file_path}")

        # Get compatible bash (prefers venv bash, falls back to system bash >= 3.2)
        bash_path, bash_version, bash_source = get_compatible_bash()
        
        # Always log which bash is being used
        timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp_str}] [QLC] Using bash: {bash_version} ({bash_source})")
        
        # Inform user if using system bash (optional upgrade available)
        if bash_source == "system":
            print(f"[INFO] For best compatibility, install QLC-managed bash: qlc-install-tools --install-bash")
        
        # Extract arguments for Python-side processing (same as qlc command)
        args = extract_qlc_arguments(sys.argv)
        
        # Prepare MARS requests (if applicable) and set environment variables
        # This propagates CLI overrides (--region, --station_selection, etc.) to bash scripts
        prepare_mars_requests(qlc_home_str, args)
        
        # Build bash-compatible command line arguments
        # This converts named arguments (--exp_ids=, --start_date=, etc.) to positional format
        bash_args = build_bash_command_args(args, sys.argv)
        
        command = [bash_path, str(script_path)] + bash_args
        
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
