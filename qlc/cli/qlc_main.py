import os
import sys
import json
import time
import logging
import argparse
import traceback
import multiprocessing
import concurrent.futures
from datetime import datetime
from multiprocessing import current_process
from concurrent.futures import ThreadPoolExecutor, as_completed
from qlc.py.control import run_main_processing, process_multiple_configs_sp, process_single_config
from qlc.py.utils import expand_paths, get_timestamp, setup_logging, validate_paths, merge_global_attributes
from qlc.py.version import QLC_VERSION, QLC_RELEASE_DATE, QLC_DISTRIBUTION
from qlc.py.plugin_loader import try_import_plugin_module
from qlc.py.logging_utils import log_input_availability
from qlc.py.logging_utils import log_qlc_banner

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
            "source": "Quick Look CAMS (QLC) Processor",
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
        # Minimal logging setup for subprocesses only
        if current_process().name != "MainProcess":
            if not logging.getLogger().hasHandlers():
                logging.basicConfig(
                    level=logging.INFO,
                    format='[%(asctime)s] %(levelname)s: [%(processName)s] %(message)s',
                    handlers=[logging.StreamHandler(sys.stdout)]
                )

        logging.info(f"(Process {idx+1}/{total_configs}) Starting configuration '{config_entry.get('name', f'config_{idx+1}')}'...")

        config = load_config_with_defaults(config_entry)
        validate_paths(config)
        log_input_availability(config)
        if not config.get("use_mod", False) and not config.get("use_obs", False):
            logging.warning("⚠️ Nothing to process: no model or observation input available. Skipping execution.")
            return

        run_main_processing(config)

        logging.info(f"(Process {idx+1}/{total_configs}) Finished configuration '{config_entry.get('name', f'config_{idx+1}')}'.")
    except Exception as e:
        print(f"[ERROR] Failed in run_single_config for config {idx+1}: {e}")
        traceback.print_exc()

def run_with_file(file_path):
    start_time = time.time()
    print("************************************************************************************************")
    print(f"Start execution: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(start_time))}")
    if not os.path.isfile(file_path):
        print(f"ERROR: Input file '{file_path}' not found.")
        sys.exit(1)

    with open(file_path, 'r') as f:
        try:
            config_data = expand_paths(json.load(f))
            validate_paths(config_data if isinstance(config_data, dict) else config_data[0])
            print(json.dumps(config_data, indent=2))
        except json.JSONDecodeError as e:
            print(f"ERROR: Failed to parse JSON: {e}")
            sys.exit(1)

    if isinstance(config_data, list):
        first_config = config_data[0]
    else:
        first_config = config_data
    
    log_dir = first_config.get("logdir", "~/qlc/log")
    log_filename = os.path.join(log_dir, f"qlc_{get_timestamp()}.log")
    full_log_path = os.path.join(os.path.expanduser(log_dir), log_filename)
    log_level = logging.DEBUG if first_config.get("debug", False) else logging.INFO
#   setup_logging(log_dir=os.path.dirname(full_log_path), level=log_level)   
    setup_logging(log_dir=log_dir, level=log_level)

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
    parser = argparse.ArgumentParser(description="Run QLC Python Processor")
    parser.add_argument("--config", type=str, help="Path to config JSON", default=os.path.expanduser("~/qlc/config/json/qlc_config.json"))
    args = parser.parse_args()

    if args.config:
        run_with_file(args.config)
    else:
        print(f"ERROR: Please provide an input JSON file using --config option.")
        sys.exit(1)

if __name__ == "__main__":
    main()
