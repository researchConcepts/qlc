#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC CLI Module: Command-Line Interface Entry Points

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/

Description:
    Provides Python entry points for QLC command-line tools including
    qlc (main workflow), qlc-py (standalone), and sqlc (batch submission).
    Handles argument parsing and shell script execution.

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
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
            
            print(f"QLC (Quick Look Content) version {__version__} BETA [{install_type}]")
            print("An Automated Model-Observation Comparison Suite Optimized for CAMS datasets")
            print("")
            print(f"Release date: {__release_date__}")
            print(f"Runtime: {qlc_home} ({detection_method})")
            print(f"Package: {qlc_pkg_path}")
            print("Documentation: https://docs.researchconcepts.io/qlc/latest")
            print("               https://github.com/researchconcepts/qlc")
            print("")
            print("BETA RELEASE: Under development, requires further testing.")
            print("© 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.")
            print("Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>")
            sys.exit(0)
        except ImportError:
            print("QLC version information not available")
            sys.exit(1)
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""
========================================================================================
QLC - Interactive QLC Execution
========================================================================================

Usage:
  qlc <exp1> [exp2 ...] <start_date> <end_date> <workflow> [options]

Arguments:
  <exp1> [exp2 ...]  One or more experiment identifiers
  <start_date>       Start date (YYYY-MM-DD)
  <end_date>         End date (YYYY-MM-DD)
  <workflow>         Workflow name: aifs, eac5, evaltools, mars, pyferret, qpy, test

Common Options:
  --obs-only         Analyze observations only
  --mod-only         Analyze model results only
  -class=xx          Override MARS class (e.g., -class=nl)
  -vars=<spec>       Variable specification (e.g., -vars="go3,NH3,PM2.5")
  -region=<code>     Region override (e.g., -region=EU)

Quick Examples:
  qlc b2ro b2rn 2018-12-01 2018-12-21 test
  qlc b2ro b2rn 2018-12-01 2018-12-21 test -obs-only -region=EU
  qlc b2ro b2rn 2018-12-01 2018-12-21 test -class=nl,nl -vars="go3,nh3"
  qlc b2ro b2rn 2018-12-01 2018-12-21 test -class=nl,nl -param=210073,210203 -myvar=PM2p5,O3 -levtype=sfc,pl

Variable Search:
  qlc-vars search O3
  qlc-vars info O3

View Results:
  ls -lrth ~/qlc/Results        # GRIB data (MARS download)
  ls -lrth ~/qlc/Analysis       # NetCDF processed data
  ls -lrth ~/qlc/Plots          # Generated plots
  ls -lrth ~/qlc/Presentations  # PDF reports

For batch submission (HPC/SLURM), use: sqlc

For more information:
  Quick Start    : ~/qlc/doc/QuickStart.md
  Documentation  : https://docs.researchconcepts.io/qlc
  Getting Started: https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/

BETA RELEASE: Under development, requires further testing.
© 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
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
