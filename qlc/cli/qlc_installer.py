#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Installer: Runtime Environment Setup

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/getting-started/installation/

Description:
    Sets up the QLC runtime environment including directory structure,
    configuration files, example data, and workflow templates. Supports
    multiple installation modes (test, cams, dev).

Usage:
    qlc-install --mode test
    qlc-install --mode cams
    qlc-install --mode dev

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import argparse
from qlc.cli.qlc_install import setup
from qlc.py.version import QLC_VERSION

def main():
    parser = argparse.ArgumentParser(
        description="Install the QLC runtime environment.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--mode",
        type=str,
        choices=['test', 'cams', 'dev', 'interactive'],
        required=True,
        help="The installation mode.\n"
             "'test': A standalone mode with bundled example data (PyPI).\n"
             "'cams': An operational mode for CAMS environments.\n"
             "'dev': Development mode for parallel testing (creates qlc_dev runtime).\n"
             "'interactive': A mode for developers to use a custom config."
    )
    parser.add_argument("--version", type=str, help="Override QLC version (for development)")
    parser.add_argument("--config", type=str, help="[interactive mode only] Path to a custom config file.")


    args = parser.parse_args()

    from datetime import datetime
    timestamp_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp_str}] [QLC-INSTALL] Installing QLC version {QLC_VERSION} in '{args.mode}' mode")
    if args.mode == 'interactive' and not args.config:
        parser.error("--config is required when using --mode interactive")
    
    # Use a dummy version if not provided, as the setup script will find the real one
    version = args.version if args.version else "0.0.0"
    
    setup(mode=args.mode, version=version, config_file=args.config)
    return 0
