# --- Set Matplotlib backend before any other imports ---
import matplotlib
matplotlib.use('Agg')

import os
import sys
import json
import time
import logging
import argparse
import traceback
import multiprocessing
import pandas as pd
import concurrent.futures
from datetime import datetime
from multiprocessing import current_process
from concurrent.futures import ThreadPoolExecutor, as_completed
from qlc.py.control import run_main_processing, process_multiple_configs_sp, process_single_config
from qlc.py.utils import expand_paths, get_timestamp, validate_paths, merge_global_attributes
from qlc.py.version import QLC_VERSION, QLC_RELEASE_DATE, QLC_DISTRIBUTION
from qlc.py.plugin_loader import try_import_plugin_module
from qlc.py.logging_utils import log_input_availability, log_qlc_banner, setup_logging

# Globally ignore the ChainedAssignmentError FutureWarning by its message.
# This is the most robust way to handle this persistent, non-critical warning
# that arises from the complex interaction between pandas and Cython.
import warnings
warnings.filterwarnings('ignore', '.*ChainedAssignmentError.*')

# -----------------------------------------------
# QLC main controller (Master Orchestration)
# -----------------------------------------------

def load_config_with_defaults(config):
    # Set defaults if missing
    defaults = {
        "global_attributes": {
            "title": "QLC Processor application",
            "subtitle": f"Processing file info (auto replaced)",
            "summary": "This file contains metadata processed by QLC.",
            "author": "Plain & Simple, plain.simple@example.com",
            "source": "Quick Look Content (QLC) Processor",
            "version": f"QLC Version: {QLC_VERSION}",
            "qlcmode": f"QLC Mode: {QLC_DISTRIBUTION}",
            "release": f"QLC Release Date: {QLC_RELEASE_DATE}",
            "contact": "Swen Metzger, ResearchConcepts io GmbH",
            "rcemail": "contact@researchconcepts.io",
            "internet": "https://www.researchconcepts.io",
            "timestamp": f"Created on {datetime.now()}",
            "history": f"User specific (optional)",
            "Conventions": "CF-1.8"
        },
        "name": "CAMS2_35",
        "logdir": "./log",
        "workdir": "./run",
        "outdir": "./output",
        "model": "model",
        "experiments": "",
        "exp_labels": "",
        "mod_path": "",
        "obs_path": "",
        "obs_dataset_type": "ebas_hourly",
        "station_file": "",
        "station_radius_deg": 0.5,
        "station_network": "",
        "station_suffix": "",
        "station_type": "concentration",
        "start_date": "2018-01-01",
        "end_date": "2018-01-31",
        "variable": "",
        "plot_type": "",
        "model_level": 0,
        "plot_region": "Globe",
        "time_average": "mean",
        "plot_mode": "grouped",
        "station_plot_group_size": 10,
        "show_stations": True,
        "show_min_max": True,
        "log_y_axis": False,
        "fix_y_axis": True,
        "force_full_year": True,
        "show_station_map": True,
        "load_station_timeseries_obs": True,
        "show_station_timeseries_obs": True,
        "show_station_timeseries_mod": True,
        "show_station_timeseries_com": True,
        "save_plot_format": "pdf,png",
        "save_data_format": "csv",
        "read_data_format": "nc",
        "output_base_name": "./output/QLC",
        "multiprocessing": False,
        "lazy_load_nc": True,
        "n_threads": "1",
        "debug": False,
        "debug_extended": False
    }

    for key, value in defaults.items():
        if key not in config:
            config[key] = value

    config = merge_global_attributes(config, defaults)
    return config

def run_single_config(config_entry, idx, total_configs):
    try:
        # Use the main logger configured in run_with_file, no separate config needed here
        logging.info(f"(Process {idx+1}/{total_configs}) Starting configuration '{config_entry.get('name', f'config_{idx+1}')}'...")

        config = load_config_with_defaults(config_entry)
        validate_paths(config)
        log_input_availability(config)
        if not config.get("use_mod", False) and not config.get("use_obs", False):
            logging.warning("⚠️ Nothing to process: no model or observation input available. Skipping execution.")
            return

        # Suppress persistent ChainedAssignmentError FutureWarning from pandas.
        # This is a known issue with the Cython execution path where standard
        # fixes (.copy(), .loc) are not sufficient. The underlying code is correct.
        with pd.option_context('mode.chained_assignment', None):
            run_main_processing(config)

        logging.info(f"(Process {idx+1}/{total_configs}) Finished configuration '{config_entry.get('name', f'config_{idx+1}')}'.")
    except Exception as e:
        print(f"[ERROR] Failed in run_single_config for config {idx+1}: {e}")
        traceback.print_exc()

def run_with_file(file_path):
    start_time = time.time()
    
    config_data = None
    try:
        if file_path == '-':
            # Read from stdin if the file path is '-'
            logging.debug("Reading configuration from stdin.")
            config_data = expand_paths(json.load(sys.stdin))
        else:
            if not os.path.isfile(file_path):
                # Using print because logging may not be set up if config fails to load.
                print(f"ERROR: Input file '{file_path}' not found.")
                sys.exit(1)
            with open(file_path, 'r') as f:
                config_data = expand_paths(json.load(f))
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse JSON from {'stdin' if file_path == '-' else file_path}: {e}")
        sys.exit(1)
            
    # --- Setup logging as early as possible ---
    if isinstance(config_data, list):
        first_config = config_data[0]
    else:
        first_config = config_data
        
    log_dir = first_config.get("logdir", "~/qlc/log")
    log_filename = f"qlc_{get_timestamp()}.log"
    full_log_path = os.path.join(os.path.expanduser(log_dir), log_filename)
    setup_logging(log_file_path=full_log_path, debug=first_config.get("debug", False))
    
    # --- Now, use the logger for all output ---
    logging.info("************************************************************************************************")
    logging.info(f"Start execution: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(start_time))}")
    
    try:
        validate_paths(first_config)
        # Pretty print JSON to a string, then log it
        config_str = json.dumps(config_data, indent=2)
        for line in config_str.splitlines():
            logging.info(line)
    except Exception as e:
        logging.error(f"Configuration error: {e}")
        sys.exit(1)

#   If the config is a list, loop over multiple configs
    if isinstance(config_data, list) and len(config_data) == 1:
        process_single_config(config_data[0], run_single_config)
    elif isinstance(config_data, list):
        mp = config_data[0].get("multiprocessing", False)
        if mp:
            plugin_mp = try_import_plugin_module("qlc_multiprocessing_plugin")
            if plugin_mp and hasattr(plugin_mp, "process_multiple_configs_mp"):
                plugin_mp.process_multiple_configs_mp(config_data, run_single_config)
            else:
                print("WARNING: Multiprocessing requested but plugin plugin not found or invalid. Using single config fallback.")
                process_multiple_configs_sp(config_data, run_single_config)
        else:
            process_multiple_configs_sp(config_data, run_single_config)
    else:
        process_single_config(config_data, run_single_config)

    end_time = time.time()
    duration = end_time - start_time
    logging.info(f"End   execution: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(end_time))} - Total execution time: {duration:.2f} seconds")
    logging.info("************************************************************************************************")

def main():
    parser = argparse.ArgumentParser(
        prog='qlc-py',
        description='QLC Python Processing Engine - Model-observation collocation and time series analysis',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use default configuration
  qlc-py
  
  # Use custom configuration
  qlc-py --config ~/qlc/config/json/my_config.json
  
  # Read configuration from stdin
  cat config.json | qlc-py --config -

Configuration File Format:
  The JSON configuration file(s) specify:
  - Experiment names and paths
  - Observation datasets and station locations
  - Variables to process
  - Time range and temporal aggregation
  - Output formats and plotting options
  - Multi-region settings (optional)
  
  See ~/qlc/config/json/qlc_config.json for a template.
  See ~/qlc/config/examples/ for working examples.

Multi-Configuration Support:
  The config file can contain either:
  - Single config object: Process one configuration
  - Array of configs: Process multiple configurations (sequential or parallel)

Typical Workflow:
  1. Shell wrapper (qlc) sets up environment and calls appropriate scripts
  2. Scripts generate JSON configuration for qlc-py
  3. qlc-py performs collocation and generates time series plots
  4. Results saved to Analysis/ and Plots/ directories
  5. E1/E2 scripts can convert output to evaltools format (optional)
  6. Z1 generates PDF reports from all plots

Related Commands:
  qlc                     Main QLC command-line interface
  qlc-extract-stations    Extract station metadata from observations
  sqlc                    Submit QLC jobs to batch scheduler

Documentation:
  Usage Guide:    ~/qlc/doc/USAGE.md
  Configuration:  ~/qlc/doc/README.md
  Online:         https://pypi.org/project/rc-qlc/
  Online:         https://github.com/researchConcepts/qlc
        """
    )
    parser.add_argument(
        "--config",
        type=str,
        help="Path to JSON configuration file (or '-' for stdin). Default: ~/qlc/config/json/qlc_config.json",
        default=os.path.expanduser("~/qlc/config/json/qlc_config.json")
    )
    
    args = parser.parse_args()

    if args.config:
        run_with_file(args.config)
    else:
        print(f"ERROR: Please provide an input JSON file using --config option.")
        sys.exit(1)

if __name__ == "__main__":
    main()
