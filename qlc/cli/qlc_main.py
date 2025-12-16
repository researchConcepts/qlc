#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Main Controller: Master Orchestration for qlc-py

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/

Description:
    Main Python controller for QLC processing. Handles configuration loading,
    multi-region analysis, parallel processing, and orchestration of the
    complete model-observation comparison workflow.

Usage:
    qlc-py --config=/path/to/config.json
    Called automatically by D1-ANAL script in qlc workflows

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

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
            "author": "qlc Team",
            "source": "Quick Look Content (QLC) Processor",
            "version": f"QLC Version: {QLC_VERSION}",
            "qlcmode": f"QLC Mode: {QLC_DISTRIBUTION}",
            "release": f"QLC Release Date: {QLC_RELEASE_DATE}",
            "contact": "qlc Team @ ResearchConcepts io GmbH",
            "rcemail": "qlc@researchconcepts.io",
            "internet": "https://docs.researchconcepts.io/qlc/latest/",
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
        "use_uniform_time_grid": False,  # False = preserve actual timestamps (for sub-hourly data); True = create uniform time grid with NaN padding
        "spatial_interp_method": "nearest",  # Spatial interpolation for model extraction at station locations: 'nearest' (default, fast, preserves values), 'linear' (smoother for regular grids), 'cubic' (smoothest), 'quadratic', or 'pad'/'ffill'/'backfill'
        "temporal_interp_method": "", # Temporal interpolation DISABLED by default (exact time matching): empty string. To enable, set to: 'linear' (smooth gap filling), 'nearest' (closest time), 'time' (time-weighted), 'pchip' (monotonic), 'akima', 'cubic', 'spline', or 'pad'/'ffill'/'backfill'
        "station_network": "",
        "station_suffix": "",
        "station_type": "concentration",
        "start_date": "2018-01-01",
        "end_date": "2018-01-31",
        "variable": "",
        "plot_type": "map,burden,scatter,zonal,meridional,taylor",
        "model_level": None,  # None = auto-detect surface (last level index), or specify 0-9 for explicit level
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
        "use_obs": None,  # Explicit flag: load and process observation data (None = auto-detect from obs_path)
        "use_mod": None,  # Explicit flag: load and process model data (None = auto-detect from mod_path)
        "use_com": None,  # Explicit flag: perform collocation (None = auto-detect if use_obs AND use_mod)
        "load_station_timeseries_obs": False,  # Load observation time series (set automatically from use_obs if not explicit)
        "show_station_timeseries_obs": False,  # Visualization: plot observation time series
        "show_station_timeseries_mod": False,  # Visualization: plot model time series
        "show_station_timeseries_com": False,  # Visualization: plot collocation comparison
        "unit_to": "",  # Target unit for collocation results (applies to both obs and mod). If empty, uses observation unit. Examples: "ug/m3", "ppb", "ppm"
        "save_plot_format": "png",  # Plot output formats (comma-separated): png, jpg, jpeg, tif, tiff (raster), pdf, svg, eps (vector)
        "save_data_format": "csv",
        "read_data_format": "nc",
        "output_base_name": "./output/QLC",
        "map_colormap": "turbo",  # Colormap for map plots (e.g., "turbo", "turbo_r", "viridis", "plasma")
        "map_show_features": False,  # Show country borders, rivers, and lakes (useful for regions like DE, US)
        "map_show_contour_labels": False,  # Show contour line labels on maps (default off to avoid clutter)
        "map_show_stats": True,  # Show statistics overlay on map plots (default on)
        "map_colorbar_type": "simple",  # Colorbar style: "simple" (default, like zonal plots) or "scientific" (equidistant ticks)
        "map_colormap_diff": "RdBu_r", # Use symmetric diverging colormap for difference plots (RdBu_r = Red-Blue diverging)
        "map_projection": "Robinson",  # Map projection for global plots (Robinson, PlateCarree, Mollweide, EqualEarth)
        "enable_diff_plots": True, # Enable automatic difference plots (exp1-REF, exp2-REF, ...) when multiple experiments are provided
        "use_log_scale": False,  # Use logarithmic scale for maps and diff plots (better for spanning multiple orders of magnitude)
        "use_normalized_scale": False,  # Scale values to 0-100 range (only linear scale + pub mode) for direct percentage comparison
        "publication_style": False,  # Publication quality: False (fast preview), True (high quality with contour lines, gridlines, etc.)
        "plot_dpi": None,  # DPI for PNG plots: None (auto: 300 if publication_style=True, 150 otherwise), or set explicitly: 100 (fast), 150 (balanced), 300+ (publication)
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

def export_variable_metadata_json(config):
    """
    Export variable metadata to JSON file in output directory.
    
    Creates qlc_variable_metadata.json with information about all variables
    used in this analysis, including mappings, units, and source information.
    """
    try:
        from qlc.py.variable_mapping import get_variable_mapping_manager
        from pathlib import Path
        
        # Get output directory from config
        output_base = config.get("output_base_name", "./output/QLC")
        output_dir = Path(output_base).parent
        output_dir.mkdir(parents=True, exist_ok=True)
        
        metadata_file = output_dir / "qlc_variable_metadata.json"
        
        # Get variable mapping manager
        manager = get_variable_mapping_manager()
        
        # Collect variables from config
        variables_to_export = []
        
        # Add observation variables if available
        obs_dataset_type = config.get("obs_dataset_type", "").lower()
        if obs_dataset_type:
            variables_to_export.append(f"obs:{obs_dataset_type}")
        
        # Add model variables from experiments
        variable = config.get("variable", "")
        if variable:
            variables_to_export.append(f"model:{variable}")
        
        # Export metadata
        manager.export_metadata_json(metadata_file, variables=None)  # Export all
        
        logging.info(f"Variable metadata exported to: {metadata_file}")
        
    except Exception as e:
        logging.warning(f"Could not export variable metadata: {e}")


def run_single_config(config_entry, idx, total_configs):
    try:
        # Use the main logger configured in run_with_file, no separate config needed here
        logging.info(f"(Process {idx+1}/{total_configs}) Starting configuration '{config_entry.get('name', f'config_{idx+1}')}'...")

        config = load_config_with_defaults(config_entry)
        validate_paths(config)
        log_input_availability(config)
        
        # Export variable metadata JSON (new in v1.0.1 beta)
        export_variable_metadata_json(config)
        
        if not config.get("use_mod", False) and not config.get("use_obs", False):
            logging.warning("WARNING: Nothing to process: no model or observation input available. Skipping execution.")
            return

        # Suppress persistent ChainedAssignmentError FutureWarning from pandas.
        # This is a known issue with the Cython execution path where standard
        # fixes (.copy(), .loc) are not sufficient. The underlying code is correct.
        with pd.option_context('mode.chained_assignment', None):
            run_main_processing(config)

        logging.info(f"(Process {idx+1}/{total_configs}) Finished configuration '{config_entry.get('name', f'config_{idx+1}')}'.")
        # Add separator between config entries
        if idx + 1 < total_configs:
            logging.info("************************************************************************************************")
    except Exception as e:
        print(f"[ERROR] Failed in run_single_config for config {idx+1}: {e}")
        traceback.print_exc()
        # Re-raise to ensure caller can detect failure
        raise

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
    logging.info(f"Configuration file: {os.path.abspath(file_path) if file_path != '-' else 'stdin'}")
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
    try:
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
    except Exception as e:
        end_time = time.time()
        duration = end_time - start_time
        logging.error(f"End   execution: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(end_time))} - Total execution time: {duration:.2f} seconds")
        logging.error("************************************************************************************************")
        logging.error(f"FATAL ERROR: Processing failed: {e}")
        sys.exit(1)

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
  qlc-py --config ~/qlc/config/qlc-py/json/my_config.json
  
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
  
  See ~/qlc/config/qlc-py/json/qlc_config.json for a template.
  See ~/qlc/Plots/  for auto-generated working examples (by qlc_D1-ANAL.sh).

Interpolation Methods:
  Spatial (for model extraction at station lat/lon):
    - Default: 'nearest' (fast, preserves values)
    - Available: 'linear', 'cubic', 'quadratic', 'pad', 'ffill', 'backfill'
    - Set via: "spatial_interp_method": "nearest"
  
  Temporal (for time alignment between obs and model):
    - Default: DISABLED (exact time matching only)
    - To enable, add: "temporal_interp_method": "linear"  (or 'nearest', 'time', etc.)
    - Use cases: 3-hourly model vs hourly obs, offset timestamps, gap filling
    - Available: 'linear', 'nearest', 'time', 'pchip', 'akima', 'cubic', 'spline'

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
              https://pypi.org/project/rc-qlc/
              https://github.com/researchConcepts/qlc
              https://docs.researchconcepts.io/qlc/latest/
              https://docs.researchconcepts.io/qlc/latest/user-guide/usage/
        """
    )
    parser.add_argument(
        "--config",
        type=str,
        help="Path to JSON configuration file (or '-' for stdin). Default: ~/qlc/config/qlc-py/json/qlc_config.json or ~/qlc-dev-run/config/qlc-py/json/qlc_config.json for dev mode",
        default=None  # Let qlc_py_main set it
    )
    
    args = parser.parse_args()

    # Use default if no config provided
    if args.config is None:
        # Try to detect from environment
        qlc_home = os.environ.get('QLC_HOME', os.path.expanduser('~/qlc'))
        
        # Check for dev mode
        if 'qlc-dev' in os.environ.get('VIRTUAL_ENV', ''):
            qlc_home = os.path.expanduser('~/qlc-dev-run')
        
        args.config = os.path.join(qlc_home, "config", "qlc-py", "json", "qlc_config.json")
    
    if args.config:
        run_with_file(args.config)
    else:
        print(f"ERROR: Please provide an input JSON file using --config option.")
        sys.exit(1)

if __name__ == "__main__":
    main()
