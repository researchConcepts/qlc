#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Python CLI: Standalone Entry Point for qlc-py

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/

Description:
    Standalone Python entry point for qlc-py command. Provides direct access
    to QLC Python processing without shell wrapper. Handles version display,
    help information, and execution of the main QLC processing workflow.

Usage:
    qlc-py --config=/path/to/config.json
    qlc-py --version
    qlc-py --help

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import os
import sys
import subprocess
from datetime import datetime
from pathlib import Path

# Fix multiprocessing module loading issue by ensuring venv packages are prioritized
if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
    # We're in a virtual environment
    venv_path = os.environ.get('VIRTUAL_ENV')
    if venv_path:
        venv_site_packages = Path(venv_path) / 'lib' / f'python{sys.version_info.major}.{sys.version_info.minor}' / 'site-packages'
        if venv_site_packages.exists():
            # Insert venv site-packages at the beginning of sys.path
            sys.path.insert(0, str(venv_site_packages))

def main():
    """
    Python entry point for running the main QLC processing script.
    This script now acts as a silent wrapper. All console output
    is handled by the logging configuration in the downstream qlc_main module.
    """
    
    # Handle special options before doing anything else
    if "--version" in sys.argv or "-V" in sys.argv:
        try:
            from qlc.py.version import QLC_VERSION, QLC_RELEASE_DATE
            print(f"QLC (Quick Look Content) version {QLC_VERSION}")
            print(f"Release date: {QLC_RELEASE_DATE}")
            print(f"Runtime: {Path.home() / 'qlc'}")
            print(f"Package: {Path(__file__).parent.parent}")
            print("An Automated Model-Observation Comparison Suite Optimized for CAMS datasets")
            print("")
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
    
    if "--help" in sys.argv or "-h" in sys.argv:
        print("QLC Python CLI - Quick Look Content")
        print("An Automated Model-Observation Comparison Suite Optimized for CAMS datasets")
        print("")
        print("Usage: qlc-py [OPTIONS]")
        print("")
        print("Options:")
        print("  --version, -V     Show version information")
        print("  --help, -h        Show this help message")
        print("  --config FILE     Specify configuration file")
        print("  --config -        Read configuration from stdin")
        print("")
        print("Default behavior:")
        print("  If no --config option is provided, qlc-py will use the default")
        print("  configuration file: ~/qlc/config/qlc-py/json/qlc_config.json")
        print("")
        print("Examples:")
        print("  qlc-py --version")
        print("  qlc-py                           # Uses default config")
        print("  qlc-py --config path/my_config.json")
        print("  qlc-py --config - < path/config.json")
        print("")
        print("Documentation: https://docs.researchconcepts.io/qlc/latest")
        print("               https://github.com/researchconcepts/qlc")
        print("")
        print("BETA RELEASE: Under development, requires further testing.")
        print("© 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.")
        print("Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>")
        sys.exit(0)
    
    # --- Ensure QLC home directory exists ---
    qlc_home = Path.home() / "qlc"
    # The qlc-install script creates this directory.
    # If it's not here, the user needs to run the installer.
    if not qlc_home.is_dir():
        # Use print here because logging is not yet configured and this is a pre-flight check.
        print(f"[ERROR] QLC home directory not found at: {qlc_home}")
        print("Please run 'qlc-install' to set up the required structure.")
        sys.exit(1)

    os.chdir(qlc_home)

    # Determine config path. Default to the standard location if no args are given.
    # Look for a --config flag or --config=value format.
    config_arg_present = False
    stdin_mode = False
    config_path_str = str(qlc_home / "config" / "qlc-py" / "json" / "qlc_config.json") # Default
    
    # Check for --config=value format first
    for arg in sys.argv[1:]:
        if arg.startswith("--config="):
            config_value = arg[9:]  # Remove '--config=' prefix
            config_arg_present = True
            if config_value == '-':
                stdin_mode = True
                config_path_str = '-'
            else:
                # Expand tilde and resolve path
                config_path_str = str(Path(config_value).expanduser().resolve())
            break
    
    # If not found, check for --config value format
    if not config_arg_present and "--config" in sys.argv:
        config_idx = sys.argv.index("--config")
        if len(sys.argv) > config_idx + 1:
            config_value = sys.argv[config_idx + 1]
            config_arg_present = True
            if config_value == '-':
                stdin_mode = True
                config_path_str = '-' # Pass the stdin marker to the subprocess
            else:
                # Expand tilde and resolve path
                config_path_str = str(Path(config_value).expanduser().resolve())
        else:
            # This case should be caught by argparse in the child, but we can be safe.
            print("[ERROR] --config flag was provided without a value.", file=sys.stderr)
            sys.exit(1)

    python_executable = sys.executable
    
    # Set up environment to prioritize venv packages
    env = os.environ.copy()
    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        # We're in a virtual environment
        venv_path = os.environ.get('VIRTUAL_ENV')
        if venv_path:
            venv_site_packages = Path(venv_path) / 'lib' / f'python{sys.version_info.major}.{sys.version_info.minor}' / 'site-packages'
            if venv_site_packages.exists():
                # Clear any existing PYTHONPATH and set to venv only
                env['PYTHONPATH'] = str(venv_site_packages)
            
            # Configure Cartopy to use venv-specific data directory (prevents SSL certificate errors)
            cartopy_data_dir = Path(venv_path) / 'share' / 'cartopy'
            env['CARTOPY_DATA_DIR'] = str(cartopy_data_dir)
            env['CARTOPY_OFFLINE_MODE'] = '1'
            env['CARTOPY_USER_BACKGROUNDS'] = 'false'
    
    command = [
        python_executable,
        "-m",
        "qlc.cli.qlc_main",
        "--config",
        config_path_str,
    ]
    
    try:
        # If in stdin mode, we need to pass our stdin to the subprocess.
        # Otherwise, the subprocess runs without piped data.
        if stdin_mode:
            subprocess.run(
                command,
                check=True,
                text=True,
                stdin=sys.stdin,  # Pass stdin through
                env=env  # Use modified environment
            )
        else:
            subprocess.run(
                command,
                check=True,
                text=True,
                env=env  # Use modified environment
            )
    except subprocess.CalledProcessError as e:
        # The error output from the subprocess will have already been printed.
        sys.exit(e.returncode)
    except Exception as e:
        print(f"A critical error occurred in the QLC wrapper: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

