#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Evaluator4Evaltools: QLC-PY to Evaltools Converter

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/advanced/evaltools/

Description:
    Converts qlc-py collocated NetCDF output directly to evaltools Evaluator
    objects WITHOUT additional interpolation. This bypasses the typical
    evaltools workflow (Grid interpolation) since qlc-py has already performed
    the collocation of model data to station locations.

Input Format:
    qlc-py collocated NetCDF from Plots/
    Format: qlc_D1-ANAL_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.nc
    Example: qlc_D1-ANAL_AIFS-COMPO_US_Airnow_stations-test_O3_20251101-20251103_3hourly_collocated_obs_mod_9191.nc

Output Format:
    evaltools Evaluator objects (.evaluator.evaltools files)

Attribution:
    evaltools (CNRM Open Source by CNRS and Météo-France)
    https://redmine.umr-cnrm.fr/projects/evaltools/wiki

Usage:
    python3 qlc_evaluator4evaltools.py --config config.json
    Called automatically by E1-ECOL script in evaltools workflow

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import os
import sys
import json
import argparse
import glob
import logging
import evaltools as evt
import numpy as np
import pandas as pd
import netCDF4
from datetime import datetime, date, timedelta

# Configure logging with QLC-standard timestamp format
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[logging.StreamHandler()]
)

def log(msg, level="INFO"):
    """QLC-standard logging function with timestamp format matching shell scripts"""
    if level == "DEBUG":
        logging.debug(msg)
    elif level == "WARNING":
        logging.warning(msg)
    elif level == "ERROR":
        logging.error(msg)
    else:
        logging.info(msg)

###############################################################################
# CONFIGURATION
###############################################################################

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description='QLC EVALUATOR4EVALTOOLS - Convert qlc-py collocation to evaltools'
    )
    
    parser.add_argument('--config', type=str, required=True,
                        help='JSON config file with paths and settings')
    parser.add_argument('--debug', action='store_true',
                        help='Enable debug logging')
    
    args = parser.parse_args()
    
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
    
    if not os.path.exists(args.config):
        log(f"Error: Config file not found: {args.config}", "ERROR")
        sys.exit(1)
    
    log(f"Loading configuration from: {args.config}")
    with open(args.config, 'r') as f:
        config = json.load(f)
    
    return config, args.debug

def load_config(config_dict):
    """Extract and validate configuration"""
    general = config_dict.get('general', {})
    listing = config_dict.get('listing', {})
    io = config_dict.get('input_output', {})
    model_colors_config = config_dict.get('model_colors', {})
    
    # Parse dates
    start_date = datetime.strptime(general['start_date'].replace('-', ''), '%Y%m%d').date()
    end_date = datetime.strptime(general['end_date'].replace('-', ''), '%Y%m%d').date()
    
    # Read conversion factors (not used in this converter, but kept for compatibility)
    conv_factors = config_dict.get('conversion_factors', {})
    
    config = {
        'start_date': start_date,
        'end_date': end_date,
        'species_list': [s.strip() for s in general['species_list'].split(',')],
        'models': [m.strip() for m in general['models'].split(',')],
        'region': general.get('region', ''),
        'time_average': general.get('time_average', None),
        'forecast_horizon': int(general.get('forecast_horizon', 1)),
        'availability_ratio': float(general.get('availability_ratio', 0.25)),
        'listing_name': listing['listing_name'],
        'listing_dir': listing['listing_dir'],
        'plots_dir': io.get('plots_dir', ''),
        'output_dir': io['output_dir'],
        'temp_dir': io.get('temp_dir', os.path.join(io['output_dir'], 'temp')),
        'output_file_pattern': io.get('output_file_pattern', 
                                      '{region}_{model}_{start}-{end}_{species}_{time_res}.evaluator.evaltools'),
        'collocated_files': io.get('collocated_files', None),  # File paths provided by E1
        'save_data_format': general.get('save_data_format', 'nc'),
        'default_station_lat': float(general.get('default_station_lat', 0.0)),
        'default_station_lon': float(general.get('default_station_lon', 0.0)),
        'default_station_altitude': float(general.get('default_station_altitude', 0.0)),
        'model_colors': model_colors_config,
    }
    
    return config

def load_model_colors(config_dict):
    """Model color mapping for evaltools plots from config"""
    colors_config = config_dict.get('model_colors', {})
    
    # Build color dictionary from config, with fallback defaults
    model_colors = {}
    for model, color in colors_config.items():
        model_colors[model] = color
    
    # Set default color from config or use fallback
    model_colors['default'] = colors_config.get('default', 'blue')
    
    return model_colors

def extract_stations_from_collocated_csv(collocated_csv_files, output_file, debug=False):
    """
    Extract unique stations from qlc-py collocated CSV files and convert to evaltools format.
    
    This uses the ACTUAL stations that have collocated data, not the original station listing.
    
    Collocated CSV format:
        index,time,site_id,site_name,lat,lon,elevation_m,{VAR}_obs,...
    
    evaltools format:
        station,name,lat,lon,altitude
    
    Args:
        collocated_csv_files: List of paths to collocated CSV files
        output_file: Path to output evaltools format file
        debug: Enable debug logging
    
    Returns:
        Path to converted file, or None on error
    """
    log(f"\n  Extracting stations from collocated data:")
    log(f"    Reading {len(collocated_csv_files)} collocated CSV file(s)")
    
    try:
        all_stations = []
        
        # Read each collocated CSV and extract unique stations
        for csv_file in collocated_csv_files:
            if debug:
                log(f"    Processing: {os.path.basename(csv_file)}", "DEBUG")
            
            try:
                df = pd.read_csv(csv_file)
                
                # Extract unique stations (group by site_id)
                stations = df.groupby('site_id').first()[['site_name', 'lat', 'lon', 'elevation_m']].reset_index()
                stations = stations.rename(columns={
                    'site_id': 'station',
                    'site_name': 'name',
                    'elevation_m': 'altitude'
                })
                
                all_stations.append(stations)
            except Exception as e:
                log(f"    Warning: Could not read {os.path.basename(csv_file)}: {e}", "WARNING")
                continue
        
        if not all_stations:
            log(f"    Error: No stations could be extracted from collocated files", "ERROR")
            return None
        
        # Combine all stations and remove duplicates
        combined = pd.concat(all_stations, ignore_index=True)
        combined = combined.drop_duplicates(subset=['station'])
        
        # Fill missing altitude with 0 (evaltools expects numeric)
        combined['altitude'] = pd.to_numeric(combined['altitude'], errors='coerce').fillna(0)
        
        # Ensure proper data types
        combined['station'] = combined['station'].astype(str).str.strip()
        combined['name'] = combined['name'].astype(str).str.strip()
        combined['lat'] = pd.to_numeric(combined['lat'], errors='coerce')
        combined['lon'] = pd.to_numeric(combined['lon'], errors='coerce')
        
        # Remove any rows with invalid coordinates
        combined = combined.dropna(subset=['lat', 'lon'])
        
        # Sort by station ID for consistency
        combined = combined.sort_values('station')
        
        # Write evaltools format
        combined.to_csv(output_file, index=False, 
                       columns=['station', 'name', 'lat', 'lon', 'altitude'])
        
        log(f"    ✓ Extracted {len(combined)} unique stations with collocated data")
        
        if debug:
            log(f"    First 3 stations:", "DEBUG")
            for _, row in combined.head(3).iterrows():
                log(f"      {row['station']}: ({row['lat']:.3f}, {row['lon']:.3f})", "DEBUG")
        
        return output_file
    
    except Exception as e:
        log(f"    Error extracting stations: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return None

###############################################################################
# COLLOCATION FILE DISCOVERY
###############################################################################

def find_collocation_files(plots_dir, species, models, start_date, end_date, data_format='nc', time_average=None):
    """
    Find qlc-py collocated NetCDF files for a given species and models.
    
    Uses new naming convention: qlc_D1-ANAL_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.nc
    Example: qlc_D1-ANAL_AIFS-COMPO_US_Airnow_stations-test_O3_20251101-20251103_3hourly_collocated_obs_mod_9191.nc
    
    Filters by specific time_average if provided, otherwise discovers all available.
    Excludes stats files (those with _stats in the name).
    
    Evaltools REQUIRES NetCDF format - CSV files are not supported.
    
    Args:
        time_average: Specific time resolution to filter (e.g., '3hourly', 'daily'), or None for all
    
    Returns list of file paths (one per time resolution if available).
    """
    log(f"\n  Searching for collocated files in: {plots_dir}")
    log(f"    Species: {species}")
    log(f"    Models: {', '.join(models)}")
    log(f"    Time average filter: {time_average if time_average else 'all'}")
    log(f"    Required format: NetCDF (.nc) - evaltools does not support CSV format")
    
    start_str = start_date.strftime('%Y%m%d')
    end_str = end_date.strftime('%Y%m%d')
    
    # Check if CSV files are found - evaltools requires NetCDF
    if data_format == 'csv':
        log(f"    ERROR: CSV format specified, but evaltools requires NetCDF format (.nc)", "ERROR")
        log(f"    Please set SAVE_DATA_FORMAT=nc in your configuration", "ERROR")
        log(f"    Or re-run qlc_D1-ANAL.sh with SAVE_DATA_FORMAT=nc to generate NetCDF files", "ERROR")
        return []
    
    # Check for CSV files even if format is nc (in case user has both)
    # Pattern: {output_base}_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.csv
    csv_pattern = os.path.join(plots_dir, f"**/qlc_D1-ANAL_*_*_*_{species}_{start_str}-{end_str}*_collocated_obs_mod_*.csv")
    csv_files = glob.glob(csv_pattern, recursive=True)
    if csv_files:
        log(f"    WARNING: Found {len(csv_files)} CSV file(s), but evaltools requires NetCDF format", "WARNING")
        log(f"    CSV files will be ignored - only NetCDF files will be processed", "WARNING")
    
    # Search for files with optional time_average filter
    # Pattern: qlc_D1-ANAL_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.{ext}
    if time_average:
        # Filter by specific time average
        pattern = os.path.join(plots_dir, f"qlc_D1-ANAL_*_*_*_{species}_{start_str}-{end_str}_{time_average}_collocated_obs_mod_*.{data_format}")
        log(f"    Searching for collocated files with pattern (filtered by time_average={time_average}): {pattern}")
    else:
        # Discover all time resolutions
        pattern = os.path.join(plots_dir, f"qlc_D1-ANAL_*_*_*_{species}_{start_str}-{end_str}*_collocated_obs_mod_*.{data_format}")
        log(f"    Searching for collocated files with pattern (all time averages): {pattern}")
    
    all_matching_files = glob.glob(pattern)
    log(f"    Found {len(all_matching_files)} potential file(s)")
    
    # Extract unique time resolutions from filenames
    discovered_time_resolutions = set()
    valid_files = []
    
    for fpath in all_matching_files:
        basename = os.path.basename(fpath)
        log(f"      Checking: {basename}")
        
        # Extract time resolution from filename (last part before extension)
        # Pattern: *_<time_res>.<ext>
        name_without_ext = os.path.splitext(basename)[0]
        parts = name_without_ext.split('_')
        if parts:
            time_res = parts[-1]
            discovered_time_resolutions.add(time_res)
            
            # Check if file contains all model names
            if all(model in basename for model in models):
                valid_files.append(fpath)
                log(f"        → Accepted (time_res: {time_res})")
            else:
                models_missing = [m for m in models if m not in basename]
                log(f"        → Rejected (missing models: {models_missing})")
    
    if time_average:
        log(f"    Filtered for time resolution: {time_average}")
    else:
        log(f"    Discovered time resolutions: {sorted(discovered_time_resolutions)}")
    
    if not valid_files:
        log(f"    ERROR: No valid collocated files found for {species}")
        if data_format != 'nc':
            log(f"    Evaltools requires NetCDF format (.nc) - please set SAVE_DATA_FORMAT=nc", "ERROR")
        return []
    
    log(f"    SUCCESS: Found {len(valid_files)} valid file(s):")
    for fpath in valid_files:
        log(f"      - {os.path.basename(fpath)}")
    
    return valid_files

###############################################################################
# NETCDF READING
###############################################################################

def parse_qlc_filename(nc_file):
    """
    Parse qlc-py collocated NetCDF filename to extract metadata.
    
    New qlc-py filename pattern (v0.4.02+):
    qlc_D1-ANAL_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.nc
    
    Example:
    qlc_D1-ANAL_AIFS-COMPO_US_Airnow_stations-test_O3_20251101-20251103_3hourly_collocated_obs_mod_9191.nc
    
    Returns:
        dict with keys: 'model_type', 'region', 'species', 'date_range', 'time_avg', 'models'
        Returns None for fields that cannot be parsed
    """
    basename = os.path.basename(nc_file)
    metadata = {
        'model_type': None,
        'region': None,
        'species': None,
        'date_range': None,
        'time_avg': None,
        'models': []
    }
    
    try:
        # Remove .nc extension
        if not basename.endswith('.nc'):
            return metadata
            
        name = basename[:-3]
        
        # Split on '_collocated_obs_mod_' to separate main part from experiments
        if '_collocated_obs_mod_' not in name:
            return metadata
            
        before_collocated, after_collocated = name.split('_collocated_obs_mod_', 1)
        
        # Extract experiments from the part after '_collocated_obs_mod_'
        # Format: {exp1}_{exp2}_...
        if after_collocated:
            metadata['models'] = after_collocated.split('_')
        
        # Parse the part before '_collocated_obs_mod_'
        # Format: qlc_D1-ANAL_{model}_{obs_suffix}_{var}_{dates}_{tavg}
        parts = before_collocated.split('_')
        
        if len(parts) < 3:
            return metadata
        
        # Time average is the last part before '_collocated_obs_mod_'
        metadata['time_avg'] = parts[-1].lower()
        
        # Find date range (YYYYMMDD-YYYYMMDD pattern)
        date_idx = None
        for i, part in enumerate(parts):
            if len(part) >= 17 and '-' in part and part.replace('-', '').isdigit():
                date_idx = i
                metadata['date_range'] = part
                break
        
        # Species is the part immediately before the date range
        if date_idx is not None and date_idx > 0:
            metadata['species'] = parts[date_idx - 1]
        
        # Model type is typically the second part after qlc_D1-ANAL
        # Example: qlc_D1-ANAL_AIFS-COMPO_... -> AIFS-COMPO
        if len(parts) >= 3 and parts[0] == 'qlc' and parts[1] == 'D1-ANAL':
            metadata['model_type'] = parts[2]
        
        # Region could be extracted from obs_suffix, but it's complex
        # Skip for now as it's not critical for evaluator creation
        
    except Exception as e:
        log(f"    Warning: Error parsing filename: {e}", "DEBUG")
    
    return metadata

def map_to_evaltools_seriestype(time_resolution):
    """
    Map any time resolution to evaltools-compatible seriesType.
    
    LIMITATION: The evaltools library (Dataset constructor in evaltools/dataset.py line ~85) 
    has a hardcoded validation that only accepts 'hourly' or 'daily' as seriesType:
    
        if seriesType not in ['hourly', 'daily']:
            raise evt.EvaltoolsError("seriesType argument must be either 'hourly' or 'daily' !!!")
    
    This is a limitation of the evaltools library, NOT a logical requirement. Since we're 
    working with already-collocated data, the actual time resolution shouldn't matter.
    
    However, to work with evaltools as-is, we must map our time resolutions to their limited set.
    The actual time resolution (e.g., '3hourly') is preserved in the output filename.
    
    Args:
        time_resolution: Time resolution string (e.g., '3hourly', 'daily', '6hourly')
    
    Returns:
        str: 'hourly' or 'daily' (evaltools-compatible values only)
    """
    time_res_lower = time_resolution.lower()
    
    # Map sub-daily resolutions to 'hourly'
    if 'hour' in time_res_lower:
        log(f"    Mapping time resolution '{time_resolution}' → 'hourly' (evaltools library limitation)")
        return 'hourly'
    
    # Map daily and coarser resolutions to 'daily'
    if any(keyword in time_res_lower for keyword in ['day', 'month', 'year', 'annual']):
        log(f"    Mapping time resolution '{time_resolution}' → 'daily' (evaltools library limitation)")
        return 'daily'
    
    # Default to daily with warning
    log(f"    Warning: Unknown time resolution '{time_resolution}', defaulting to 'daily'", "WARNING")
    return 'daily'

def detect_temporal_resolution(nc_file, times):
    """
    Detect temporal resolution from qlc-py filename format.
    
    New qlc-py filename pattern (v0.4.02+):
    qlc_D1-ANAL_{model}_{obs_suffix}_{var}_{dates}_{tavg}_collocated_obs_mod_{exps}.nc
    
    Example:
    qlc_D1-ANAL_AIFS-COMPO_US_Airnow_stations-test_O3_20251101-20251103_3hourly_collocated_obs_mod_9191.nc
    
    The temporal resolution is the part immediately BEFORE '_collocated_obs_mod_'.
    
    Args:
        nc_file: Path to NetCDF file
        times: Array of datetime timestamps (used as fallback)
    
    Returns:
        str: temporal resolution ('hourly', 'daily', 'monthly', etc.)
    """
    basename = os.path.basename(nc_file)
    
    # Extract time resolution from filename: part before '_collocated_obs_mod_'
    # New pattern: *_{tavg}_collocated_obs_mod_{exps}.nc
    if '_collocated_obs_mod_' in basename:
        # Split on the collocated marker and get the part before it
        before_collocated = basename.split('_collocated_obs_mod_')[0]
        # The time average is the last part before '_collocated_obs_mod_'
        parts = before_collocated.split('_')
        if parts:
            time_resolution = parts[-1].lower()
            # Validate it looks like a time resolution
            if any(keyword in time_resolution for keyword in ['hour', 'day', 'month', 'year', 'annual']):
                return time_resolution
    
    # Fallback: try to detect from time series
    log(f"    Warning: Could not extract time resolution from filename, inferring from data", "WARNING")
    if len(times) >= 2:
        time_diff = (times[1] - times[0]).total_seconds() / 3600  # hours
        if time_diff <= 1.5:  # <= 1.5 hours
            return 'hourly'
        elif time_diff <= 2.5:  # ~2-3 hours
            return '3hourly'
        elif time_diff <= 4.5:  # ~3-4 hours  
            return '3hourly'
        elif time_diff <= 7:  # ~6 hours
            return '6hourly'
        elif time_diff <= 13:  # ~12 hours
            return '12hourly'
        elif time_diff <= 25:  # <= 25 hours (accounting for some variance)
            return 'daily'
        elif time_diff <= 35 * 24:  # <= ~35 days
            return 'monthly'
        else:
            return 'yearly'
    
    # Default to daily if can't determine
    log(f"    Warning: Using default temporal resolution: daily", "WARNING")
    return 'daily'

def read_collocated_netcdf(nc_file, species, models, start_date, end_date, debug=False):
    """
    Read qlc-py collocated NetCDF and extract observation and model data.
    
    Returns:
        - obs_df: DataFrame with observations (time, station, value)
        - model_dfs: Dict of DataFrames per model {model_name: df}
        - station_metadata: DataFrame with station info (site_id, lat, lon, etc.)
        - series_type: str ('hourly' or 'daily')
    """
    log(f"\n  Reading collocated NetCDF: {os.path.basename(nc_file)}")
    
    # Parse filename to extract metadata
    file_metadata = parse_qlc_filename(nc_file)
    if debug:
        log(f"    Parsed filename metadata:", "DEBUG")
        log(f"      Model type: {file_metadata.get('model_type')}", "DEBUG")
        log(f"      Region: {file_metadata.get('region')}", "DEBUG")
        log(f"      Species: {file_metadata.get('species')}", "DEBUG")
        log(f"      Date range: {file_metadata.get('date_range')}", "DEBUG")
        log(f"      Time average: {file_metadata.get('time_avg')}", "DEBUG")
        log(f"      Models: {', '.join(file_metadata.get('models', []))}", "DEBUG")
    
    # Initialize series_type with default (will be updated if successfully determined)
    series_type = file_metadata.get('time_avg', 'daily')
    
    try:
        with netCDF4.Dataset(nc_file, 'r') as nc:
            # Read dimensions
            n_records = len(nc.dimensions['index'])
            log(f"    Total records: {n_records}")
            
            # Read station metadata
            site_ids = nc.variables['site_id'][:]
            lats = nc.variables['lat'][:]
            lons = nc.variables['lon'][:]
            
            # Decode site_ids if needed
            if hasattr(site_ids[0], 'decode'):
                site_ids = [s.decode('utf-8') if isinstance(s, bytes) else str(s) for s in site_ids]
            else:
                site_ids = [str(s) for s in site_ids]
            
            # Read time (convert from days since reference to datetime)
            time_vals = nc.variables['time'][:]
            time_units = nc.variables['time'].units
            time_cal = getattr(nc.variables['time'], 'calendar', 'proleptic_gregorian')
            
            times = netCDF4.num2date(time_vals, time_units, time_cal)
            # Convert to pandas Timestamp
            times = pd.DatetimeIndex([
                pd.Timestamp(t.year, t.month, t.day, t.hour, t.minute, t.second)
                if hasattr(t, 'year') else pd.Timestamp(t)
                for t in times
            ])
            
            log(f"    Time range: {times.min()} to {times.max()}")
            log(f"    Unique stations: {len(set(site_ids))}")
            
            # Use temporal resolution from filename metadata (authoritative source from D1 script)
            # Fall back to detection only if not available from filename
            if file_metadata.get('time_avg'):
                series_type = file_metadata['time_avg']
                log(f"    Temporal resolution from filename: {series_type}")
            else:
                series_type = detect_temporal_resolution(nc_file, times)
                log(f"    Detected temporal resolution: {series_type}")
            
            # Read observations
            obs_var_name = f"{species}_obs"
            if obs_var_name not in nc.variables:
                log(f"    Error: Observation variable '{obs_var_name}' not found in NetCDF", "ERROR")
                return None, None, None, series_type
            
            obs_vals = nc.variables[obs_var_name][:]
            obs_unit = getattr(nc.variables[obs_var_name], 'units', 'unknown')
            log(f"    Observation variable: {obs_var_name} [{obs_unit}]")
            
            # Create observation DataFrame
            obs_df = pd.DataFrame({
                'time': times,
                'station': site_ids,
                'lat': lats,
                'lon': lons,
                'value': obs_vals
            })
            
            # Remove NaN observations
            obs_df = obs_df.dropna(subset=['value'])
            log(f"    Valid observations: {len(obs_df)}")
            
            # Read model data for each experiment
            model_dfs = {}
            for model in models:
                model_var_name = f"{species}_{model}"
                if model_var_name not in nc.variables:
                    log(f"    Warning: Model variable '{model_var_name}' not found, skipping", "WARNING")
                    continue
                
                model_vals = nc.variables[model_var_name][:]
                model_unit = getattr(nc.variables[model_var_name], 'units', 'unknown')
                log(f"    Model variable: {model_var_name} [{model_unit}]")
                
                model_df = pd.DataFrame({
                    'time': times,
                    'station': site_ids,
                    'lat': lats,
                    'lon': lons,
                    'value': model_vals
                })
                
                # Remove NaN model values
                model_df = model_df.dropna(subset=['value'])
                model_dfs[model] = model_df
                log(f"      Valid {model} simulations: {len(model_df)}")
            
            # Extract unique station metadata
            station_metadata = pd.DataFrame({
                'site_id': site_ids,
                'lat': lats,
                'lon': lons
            }).drop_duplicates(subset=['site_id'])
            
            log(f"    Station metadata: {len(station_metadata)} unique stations")
            
            # Debug: Check if coordinates are valid
            if len(station_metadata) > 0:
                sample_row = station_metadata.iloc[0]
                log(f"    DEBUG: Sample station from NetCDF - ID: {sample_row['site_id']}, lat: {sample_row['lat']}, lon: {sample_row['lon']}")
            
            return obs_df, model_dfs, station_metadata, series_type
    
    except Exception as e:
        log(f"    Error reading NetCDF: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return None, None, None, series_type

###############################################################################
# EVALTOOLS CONVERSION
###############################################################################

def create_observations_from_df(obs_df, species, start_date, end_date, stations, config, series_type='daily', time_step=1, debug=False):
    """
    Create evaltools Observations object from DataFrame.
    
    Args:
        obs_df: DataFrame with columns [time, station, value]
        species: Species name
        start_date, end_date: Date range
        stations: pandas DataFrame with station metadata (index=station IDs, columns=['name', 'lat', 'lon', 'altitude'])
        series_type: Temporal resolution ('hourly' or 'daily')
    
    Returns:
        evaltools Observations object
    """
    log(f"\n  Creating Observations object for {species}")
    
    try:
        # Pivot to get time x station matrix
        obs_pivot = obs_df.pivot_table(
            index='time',
            columns='station',
            values='value',
            aggfunc='first'  # Use first value if duplicates
        )
        
        # Note: Do NOT reindex - preserve the actual temporal resolution from the data
        # The collocation data already has the correct timestamps (hourly, 3-hourly, daily, etc.)
        
        # Get station index from DataFrame or use as-is if already an Index
        station_index = stations.index if isinstance(stations, pd.DataFrame) else stations
        
        # Ensure all stations from listing are present - add missing stations efficiently
        missing_stations = [s for s in station_index if s not in obs_pivot.columns]
        if missing_stations:
            # Create DataFrame with NaN columns for missing stations and concatenate once
            missing_df = pd.DataFrame(np.nan, index=obs_pivot.index, columns=missing_stations)
            obs_pivot = pd.concat([obs_pivot, missing_df], axis=1)
        
        obs_pivot = obs_pivot[station_index]  # Reorder columns to match station listing
        
        log(f"    Observation matrix shape: {obs_pivot.shape}")
        log(f"    Valid data points: {obs_pivot.notna().sum().sum()}")
        
        # Convert station list to plain Python list
        station_list = [str(s) for s in obs_pivot.columns]
        
        if debug:
            log(f"    Station list type: {type(station_list)}", "DEBUG")
            log(f"    First 3 stations: {station_list[:3]}", "DEBUG")
        
        # Note: series_type is already mapped to evaltools-compatible value ('hourly' or 'daily')
        # by the caller before being passed to this function
        # time_step is the temporal resolution (1 for hourly, 3 for 3hourly, etc.)
        # For daily data, time_step=1 (ignored by evaltools but required for validation)
        
        # Create evaltools Dataset and populate with data
        dataset = evt.Dataset(
            stations=station_list,
            startDate=start_date,
            endDate=end_date,
            species=species,
            seriesType=series_type,
            step=time_step
        )
        dataset.updateFromDataset(obs_pivot)
        
        # CRITICAL FIX: evaltools sets step=None for daily data, but Taylor plots need step=1
        # Manually set step attribute after Dataset creation
        if debug:
            log(f"    Pre-fix: seriesType={series_type}, dataset.step={dataset.step}", "DEBUG")
        if series_type == 'daily' and dataset.step is None:
            dataset.step = 1
            if debug:
                log(f"    Fixed step=None to step=1 for daily data (required for Taylor diagrams)", "DEBUG")
        if debug:
            log(f"    Post-fix: dataset.step={dataset.step}", "DEBUG")
        
        # Create Observations object - use a workaround to avoid constructor issues
        # Create an empty Observations object by manually setting attributes
        observations = object.__new__(evt.evaluator.Observations)
        # Set the dataset and required attributes
        observations.dataset = dataset
        observations.path = ''
        observations.forecastHorizon = 1
        
        # Create stations DataFrame with metadata (matching evaltools format)
        # Extract station metadata from stations parameter (which should be a DataFrame with name, lat, lon, altitude)
        if isinstance(stations, pd.DataFrame) and len(stations) > 0:
            log(f"    DEBUG: Received stations DataFrame with {len(stations)} station(s)")
            sample_idx = stations.index[0] if len(stations) > 0 else None
            if sample_idx:
                log(f"    DEBUG: Sample input station '{sample_idx}' - lat: {stations.loc[sample_idx, 'lat']}, lon: {stations.loc[sample_idx, 'lon']}")
            
            # Filter stations to only include those present in the dataset and reindex to match order
            available_stations = [s for s in dataset.data.columns if s in stations.index]
            log(f"    DEBUG: Dataset has {len(dataset.data.columns)} columns, {len(available_stations)} match stations index")
            
            if len(available_stations) > 0:
                stations_df = stations.loc[available_stations].copy()
                log(f"    Using {len(stations_df)} station(s) with coordinates from NetCDF metadata")
                sample_final = stations_df.iloc[0]
                log(f"    DEBUG: Final station coordinates - lat: {sample_final['lat']}, lon: {sample_final['lon']}")
            else:
                log(f"    Warning: No matching stations found in metadata, using defaults", "WARNING")
                stations_df = pd.DataFrame({
                    'name': dataset.data.columns,
                    'lat': float(config.get('default_station_lat', 0.0)),
                    'lon': float(config.get('default_station_lon', 0.0)),
                    'altitude': float(config.get('default_station_altitude', 0.0))
                }, index=dataset.data.columns)
        else:
            # Create a minimal DataFrame with station IDs using config defaults
            log(f"    Warning: No station metadata provided, using default coordinates (0.0, 0.0)", "WARNING")
            stations_df = pd.DataFrame({
                'name': dataset.data.columns,
                'lat': float(config.get('default_station_lat', 0.0)),
                'lon': float(config.get('default_station_lon', 0.0)),
                'altitude': float(config.get('default_station_altitude', 0.0))
            }, index=dataset.data.columns)
        
        observations.__dict__['stations'] = stations_df
        observations.__dict__['forecastHorizon'] = config.get('forecast_horizon', 1)
        observations.__dict__['path'] = ''
        
        log(f"    Observations object created successfully")
        return observations
    
    except Exception as e:
        log(f"    Error creating Observations: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return None

def create_simulations_from_df(model_df, model_name, species, start_date, end_date, 
                                stations, config, series_type='daily', time_step=1, debug=False):
    """
    Create evaltools Simulations object from DataFrame.
    
    Args:
        model_df: DataFrame with columns [time, station, value]
        model_name: Name of model/experiment
        species: Species name
        start_date, end_date: Date range
        stations: pandas DataFrame with station metadata (index=station IDs, columns=['name', 'lat', 'lon', 'altitude'])
        series_type: Temporal resolution ('hourly' or 'daily')
    
    Returns:
        evaltools Simulations object
    """
    log(f"\n  Creating Simulations object for {model_name}")
    
    try:
        # Pivot to get time x station matrix
        sim_pivot = model_df.pivot_table(
            index='time',
            columns='station',
            values='value',
            aggfunc='first'
        )
        
        # Note: Do NOT reindex - preserve the actual temporal resolution from the data
        # The collocation data already has the correct timestamps (hourly, 3-hourly, daily, etc.)
        
        # Get station index from DataFrame or use as-is if already an Index
        station_index = stations.index if isinstance(stations, pd.DataFrame) else stations
        
        # Ensure all stations from listing are present - add missing stations efficiently
        missing_stations = [s for s in station_index if s not in sim_pivot.columns]
        if missing_stations:
            # Create DataFrame with NaN columns for missing stations and concatenate once
            missing_df = pd.DataFrame(np.nan, index=sim_pivot.index, columns=missing_stations)
            sim_pivot = pd.concat([sim_pivot, missing_df], axis=1)
        
        sim_pivot = sim_pivot[station_index]  # Reorder columns
        
        log(f"    Simulation matrix shape: {sim_pivot.shape}")
        log(f"    Valid data points: {sim_pivot.notna().sum().sum()}")
        
        # Convert station list to plain Python list
        station_list = [str(s) for s in sim_pivot.columns]
        
        if debug:
            log(f"    Station list type: {type(station_list)}", "DEBUG")
            log(f"    First 3 stations: {station_list[:3]}", "DEBUG")
        
        # Note: series_type is already mapped to evaltools-compatible value ('hourly' or 'daily')
        # by the caller before being passed to this function
        # time_step is the temporal resolution (1 for hourly, 3 for 3hourly, etc.)
        # For daily data, time_step=1 (ignored by evaltools but required for validation)
        
        # Create evaltools Dataset and populate with data
        dataset = evt.Dataset(
            stations=station_list,
            startDate=start_date,
            endDate=end_date,
            species=species,
            seriesType=series_type,
            step=time_step
        )
        dataset.updateFromDataset(sim_pivot)
        
        # CRITICAL FIX: evaltools sets step=None for daily data, but Taylor plots need step=1
        # Manually set step attribute after Dataset creation
        if debug:
            log(f"    Pre-fix: seriesType={series_type}, dataset.step={dataset.step}", "DEBUG")
        if series_type == 'daily' and dataset.step is None:
            dataset.step = 1
            if debug:
                log(f"    Fixed step=None to step=1 for daily data (required for Taylor diagrams)", "DEBUG")
        if debug:
            log(f"    Post-fix: dataset.step={dataset.step}", "DEBUG")
        
        # Create Simulations object - use a workaround to avoid constructor issues
        # Create an empty Simulations object by manually setting attributes
        simulations = object.__new__(evt.evaluator.Simulations)
        
        # Set all required attributes in __dict__ (Simulations needs these explicitly)
        simulations.__dict__['datasets'] = [dataset]
        simulations.__dict__['model'] = model_name
        simulations.__dict__['path'] = ''
        simulations.__dict__['forecastHorizon'] = 1
        simulations.__dict__['species'] = species
        simulations.__dict__['startDate'] = start_date
        simulations.__dict__['endDate'] = end_date
        simulations.__dict__['seriesType'] = series_type
        
        # Create stations DataFrame with metadata (matching evaltools format)
        if isinstance(stations, pd.DataFrame) and len(stations) > 0:
            # Filter stations to only include those present in the dataset and reindex to match order
            available_stations = [s for s in dataset.data.columns if s in stations.index]
            if len(available_stations) > 0:
                stations_df = stations.loc[available_stations].copy()
                log(f"    Using {len(stations_df)} station(s) with coordinates from NetCDF metadata")
            else:
                log(f"    Warning: No matching stations found in metadata, using defaults", "WARNING")
                stations_df = pd.DataFrame({
                    'name': dataset.data.columns,
                    'lat': float(config.get('default_station_lat', 0.0)),
                    'lon': float(config.get('default_station_lon', 0.0)),
                    'altitude': float(config.get('default_station_altitude', 0.0))
                }, index=dataset.data.columns)
        else:
            # Create a minimal DataFrame with station IDs using config defaults
            log(f"    Warning: No station metadata provided, using default coordinates (0.0, 0.0)", "WARNING")
            stations_df = pd.DataFrame({
                'name': dataset.data.columns,
                'lat': float(config.get('default_station_lat', 0.0)),
                'lon': float(config.get('default_station_lon', 0.0)),
                'altitude': float(config.get('default_station_altitude', 0.0))
            }, index=dataset.data.columns)
        
        simulations.__dict__['stations'] = stations_df
        
        log(f"    Simulations object created successfully")
        return simulations
    
    except Exception as e:
        log(f"    Error creating Simulations: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return None

###############################################################################
# MAIN PROCESSING
###############################################################################

def process_species(species, config, model_colors, debug=False):
    """
    Process a single species: convert collocated NetCDF to evaluators.
    
    Returns:
        Number of successfully created evaluators
    """
    log(f"\n{'='*80}")
    log(f"Processing species: {species}")
    log(f"{'='*80}")
    
    success_count = 0
    
    # Use provided collocated files if available (passed from E1), otherwise search
    if config.get('collocated_files'):
        log(f"  Using {len(config['collocated_files'])} collocated file(s) provided by E1")
        collocation_files = config['collocated_files']
        # Filter files by species (in case E1 passes multiple species files)
        collocation_files = [f for f in collocation_files if species in os.path.basename(f)]
        log(f"  Filtered to {len(collocation_files)} file(s) for species {species}")
    else:
        # Fallback: search for files (backward compatibility)
        log(f"  No files provided, searching in plots_dir...")
        collocation_files = find_collocation_files(
            config['plots_dir'],
            species,
            config['models'],
            config['start_date'],
            config['end_date'],
            config['save_data_format'],
            config.get('time_average', None)
        )
    
    if not collocation_files:
        log(f"  No collocated files found for {species}, skipping", "WARNING")
        return 0
    
    # Process each collocation file (typically one per species+date range+models combination)
    for nc_file in collocation_files:
        log(f"\n--- Processing file: {os.path.basename(nc_file)} ---")
        
        # Check if the collocated NetCDF file contains forecast step information
        # GRIB files preserve step dimension, which can be passed through QLC collocation
        # NetCDF files from GRIB→NetCDF conversion lose step (merged into time axis)
        has_forecast_steps = False
        try:
            import xarray as xr
            with xr.open_dataset(nc_file) as ds:
                # Check for step dimension/coordinate/variable
                if 'step' in ds.dims or 'step' in ds.coords or 'step' in ds.data_vars:
                    has_forecast_steps = True
                    log(f"  ✓ Forecast step information detected in collocated file")
                else:
                    log(f"  ⊗ No forecast step dimension found (GRIB→NetCDF conversion loses step)")
        except Exception as e:
            log(f"  Warning: Could not check for step dimension: {e}", "WARNING")
            has_forecast_steps = False
        
        # Read collocated data
        obs_df, model_dfs, station_metadata, series_type = read_collocated_netcdf(
            nc_file, species, config['models'],
            config['start_date'], config['end_date'],
            debug=debug
        )
        
        if obs_df is None or not model_dfs:
            log(f"  Skipping file due to read errors", "WARNING")
            continue
        
        # Map time resolution once for evaltools compatibility
        # Keep original series_type for filename, use mapped version for evaltools objects
        log(f"  File time resolution: {series_type} (will be preserved in output filename)")
        evaltools_series_type = map_to_evaltools_seriestype(series_type)
        log(f"  Evaltools internal seriesType: {evaltools_series_type} (library limitation, data is unaffected)")
        
        # Extract numeric step from time resolution for Dataset creation
        # This is critical for evaltools to compute statistics correctly
        time_step = 1  # default for hourly
        if 'hour' in series_type.lower():
            import re
            match = re.search(r'(\d+)hour', series_type.lower())
            if match:
                time_step = int(match.group(1))
                log(f"  Extracted time step: {time_step} hours from '{series_type}'")
            else:
                time_step = 1  # plain "hourly" = 1 hour
                log(f"  Using default hourly step: {time_step} hour")
        elif 'day' in series_type.lower() or 'daily' in series_type.lower():
            # Evaltools requires step to be in [None, 1, 2, 3, 4, 6, 8, 12] even though
            # it's ignored when seriesType='daily'. Use 1 to pass validation.
            time_step = 1
            log(f"  Using daily resolution (step parameter ignored by evaltools)")
        
        # Create stations DataFrame from NetCDF metadata (index=site_id, columns=['name', 'lat', 'lon', 'altitude'])
        # This is the actual stations with collocated data
        log(f"  DEBUG: station_metadata type: {type(station_metadata)}, columns: {list(station_metadata.columns) if isinstance(station_metadata, pd.DataFrame) else 'N/A'}")
        
        stations_df = pd.DataFrame({
            'name': station_metadata['site_id'].values,
            'lat': station_metadata['lat'].values,
            'lon': station_metadata['lon'].values,
            'altitude': [0.0] * len(station_metadata)  # Default altitude if not in NetCDF
        })
        stations_df.index = station_metadata['site_id'].values
        log(f"  Created station listing from NetCDF: {len(stations_df)} stations")
        
        # Debug: Check if we actually have coordinates
        if len(stations_df) > 0:
            sample_station = stations_df.iloc[0]
            log(f"  DEBUG: After DataFrame creation - lat: {sample_station['lat']}, lon: {sample_station['lon']}, index: {stations_df.index[0]}")
            if sample_station['lat'] == 0.0 and sample_station['lon'] == 0.0:
                log(f"  WARNING: Station coordinates are (0.0, 0.0) - extraction from NetCDF may have failed!", "WARNING")
        
        # Create Observations object (shared across all models)
        # Pass the already-mapped evaltools_series_type and actual time_step to ensure consistency
        observations = create_observations_from_df(
            obs_df, species,
            config['start_date'], config['end_date'],
            stations_df, config,
            series_type=evaltools_series_type,
            time_step=time_step,
            debug=debug
        )
        
        if observations is None:
            log(f"  Failed to create Observations, skipping file", "ERROR")
            continue
        
        # Create Evaluator for each model
        for model_name, model_df in model_dfs.items():
            log(f"\n--- Creating Evaluator for {model_name} ---")
            
            # Create Simulations object
            # Pass the same already-mapped evaltools_series_type and actual time_step for consistency with Observations
            simulations = create_simulations_from_df(
                model_df, model_name, species,
                config['start_date'], config['end_date'],
                stations_df, config,
                series_type=evaltools_series_type,
                time_step=time_step,
                debug=debug
            )
            
            if simulations is None:
                log(f"  Failed to create Simulations for {model_name}, skipping", "ERROR")
                continue
            
            # Create Evaluator
            color = model_colors.get(model_name, model_colors['default'])
            evaluator = evt.evaluator.Evaluator(observations, simulations, color=color)
            
            # CRITICAL FIX: Set step AFTER Evaluator creation as constructor may reset it
            # This is required for Taylor diagrams and other plots to work with daily data
            if evaltools_series_type == 'daily':
                evaluator.observations.dataset.step = 1
                for sim_ds in evaluator.simulations.datasets:
                    sim_ds.step = 1
                log(f"  ✓ Set step=1 for daily data in Evaluator (required for Taylor diagrams)")
            
            # Add metadata about forecast step availability (detected from collocated NetCDF structure)
            # If QLC collocated files contain 'step' dimension → forecast-dependent plots can be generated
            # If no 'step' dimension (typical for GRIB→NetCDF conversion) → skip forecast plots
            evaluator.has_forecast_steps = has_forecast_steps
            log(f"  Evaluator metadata: has_forecast_steps={evaluator.has_forecast_steps}")
            if not has_forecast_steps:
                log(f"  Note: Forecast-dependent plots (time_scores) will be skipped for this evaluator")
            
            # Save evaluator
            start_str = config['start_date'].strftime('%Y%m%d')
            end_str = config['end_date'].strftime('%Y%m%d')
            output_pattern = config['output_file_pattern']
            
            log(f"  Creating evaluator filename:")
            log(f"    Pattern: {output_pattern}")
            log(f"    Temporal resolution (time_res): {series_type}")
            
            output_filename = output_pattern.format(
                region=config['region'],
                model=model_name,
                start=start_str,
                end=end_str,
                species=species,
                time_res=series_type
            )
            
            evaluator_file = os.path.join(config['output_dir'], output_filename)
            
            try:
                evaluator.dump(evaluator_file)
                log(f"  ✓ Evaluator saved: {os.path.basename(evaluator_file)}")
                log(f"    Stations: {observations.dataset.data.shape[1]}, Timesteps: {observations.dataset.data.shape[0]}")
                success_count += 1
            except Exception as e:
                log(f"  ✗ Error saving Evaluator: {e}", "ERROR")
                import traceback
                traceback.print_exc()
    
    return success_count

def main():
    """Main execution"""
    
    config_dict, debug = parse_arguments()
    config = load_config(config_dict)
    model_colors = load_model_colors(config_dict)
    
    log("="*80)
    log("QLC EVALUATOR4EVALTOOLS - Direct Converter from QLC-PY Collocation")
    log(f"Period: {config['start_date']} to {config['end_date']}")
    log(f"Models: {', '.join(config['models'])}")
    log(f"Species: {', '.join(config['species_list'])}")
    log(f"Input: {config['plots_dir']}")
    log(f"Output: {config['output_dir']}")
    log("="*80)
    
    # Create output and temp directories
    os.makedirs(config['output_dir'], exist_ok=True)
    os.makedirs(config['temp_dir'], exist_ok=True)
    
    # Statistics
    total_success = 0
    total_errors = 0
    
    # Process each species
    for species in config['species_list']:
        species = species.strip()
        if not species:
            continue
        
        success_count = process_species(species, config, model_colors, debug=debug)
        
        if success_count > 0:
            total_success += success_count
        else:
            total_errors += 1
    
    # Summary
    log(f"\n{'='*80}")
    log(f"Conversion Complete")
    log(f"  Successfully created: {total_success} evaluator(s)")
    log(f"  Species with errors: {total_errors}")
    log(f"  Output directory: {config['output_dir']}")
    log(f"{'='*80}")
    
    # Exit with error if no evaluators were created
    if total_success == 0:
        log(f"ERROR: No evaluators were created!", "ERROR")
        sys.exit(1)
    
    sys.exit(0 if total_errors == 0 else 1)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        log("\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        log(f"Fatal error: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        sys.exit(1)