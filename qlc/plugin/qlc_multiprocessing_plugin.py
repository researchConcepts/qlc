import logging
import multiprocessing

"""
Plugin for QLC.
This module enables multiprocessing of multiple config entries.
"""

def process_multiple_configs_mp(config_data, run_single_config_fn):
    """Multiprocessing of multiple config entries."""
    print("Start: ************************ multiprocessing of multiple config entries ************************")
    total_configs = len(config_data)
    print(f"{total_configs} configurations found. Processing in parallel using multiprocessing...")

    with multiprocessing.Pool(processes=min(multiprocessing.cpu_count(), total_configs)) as pool:
        tasks = [(entry, idx, total_configs) for idx, entry in enumerate(config_data)]
        pool.starmap(run_single_config_fn, tasks)

    print("End:   ************************ multiprocessing of multiple config entries ************************")
