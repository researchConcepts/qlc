#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC EVALUATOR4EVALTOOLS - Direct Converter from QLC-PY Collocation Output

Converts qlc-py collocated NetCDF output (from qlc_D1.sh) directly to 
evaltools Evaluator objects WITHOUT additional interpolation.

This bypasses the typical evaltools workflow (Grid interpolation) since 
qlc-py has already performed the collocation of model data to station locations.

Input: qlc-py collocated NetCDF from Plots/
       Format: qlc_D1_*_collocated_obs_*_mod_*.nc
       
Output: evaltools Evaluator objects (.evaluator.evaltools files)

Usage:
    python3 qlc_evaluator4evaltools.py --config config.json
    
Author: Swen Metzger, ResearchConcepts io GmbH
Based on qlc-py stations.py merge_obs_mod() and evaltools ifs2evaltools
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
        'region': general.get('region', 'Europe'),
        'forecast_horizon': int(general.get('forecast_horizon', 1)),
        'availability_ratio': float(general.get('availability_ratio', 0.25)),
        'listing_name': listing['listing_name'],
        'listing_dir': listing['listing_dir'],
        'plots_dir': io.get('plots_dir', ''),
        'output_dir': io['output_dir'],
        'temp_dir': io.get('temp_dir', os.path.join(io['output_dir'], 'temp')),
        'output_file_pattern': io.get('output_file_pattern', 
                                      '{region}_{model}_{start}-{end}_{species}_{time_res}.evaluator.evaltools'),
    }
    
    return config

def load_model_colors():
    """Model color mapping for evaltools plots"""
    return {
        'b2ro': 'firebrick',
        'b2rn': 'dodgerblue',
        'b2rm': 'forestgreen',
        'b285': 'lime',
        'b287': 'red',
        'b289': 'chocolate',
        'default': 'blue'
    }

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

def find_collocation_files(plots_dir, species, models, start_date, end_date):
    """
    Find qlc-py collocated NetCDF files for a given species and models.
    
    Pattern: qlc_D1_*_collocated_obs_*_mod_*.nc
    
    Returns dict: {species: [file_path]}
    """
    log(f"\n  Searching for collocated files in: {plots_dir}")
    log(f"    Species: {species}")
    log(f"    Models: {', '.join(models)}")
    
    start_str = start_date.strftime('%Y%m%d')
    end_str = end_date.strftime('%Y%m%d')
    
    # Search pattern: look for files containing the species and date range
    # Pattern: qlc_D1_*_{species}_{dates}_*_collocated_*.nc
    pattern = os.path.join(plots_dir, f"**/*{species}*{start_str}-{end_str}*collocated*.nc")
    
    log(f"    Search pattern: {pattern}", "DEBUG")
    
    matching_files = glob.glob(pattern, recursive=True)
    
    if not matching_files:
        log(f"    Warning: No collocated files found for {species}", "WARNING")
        return []
    
    # Filter files to ensure they contain all model experiments
    # Also skip files with unsupported temporal resolutions (evaltools only supports hourly and daily)
    import re
    
    valid_files = []
    skipped_unsupported = []
    
    # Evaltools only supports these temporal resolutions
    supported_time_resolutions = ['hourly', 'daily']
    
    for fpath in matching_files:
        basename = os.path.basename(fpath)
        
        # Extract temporal resolution from end of filename (just before .nc)
        # Pattern: *_<time_res>.nc where <time_res> contains NO underscores
        # Examples: *_daily.nc, *_hourly.nc, *_weekly.nc, *_monthly.nc, *_10min.nc
        # Note: \w includes underscore, so we use [^_]+ to match non-underscore characters only
        match = re.search(r'_([^_]+)\.nc$', basename)
        
        if not match:
            log(f"    Warning: Could not extract temporal resolution from: {basename}", "WARNING")
            skipped_unsupported.append((basename, 'unknown'))
            continue
        
        time_res = match.group(1)
        
        log(f"    Checking: {basename}")
        log(f"      Temporal resolution: {time_res}")
        
        # Check if temporal resolution is supported by evaltools
        if time_res not in supported_time_resolutions:
            log(f"      → Skipping (unsupported resolution: {time_res})")
            skipped_unsupported.append((basename, time_res))
            continue
        
        log(f"      → Resolution '{time_res}' is supported, checking models: {models}")
        
        # Check if file contains all model names
        models_found = [m for m in models if m in basename]
        models_missing = [m for m in models if m not in basename]
        log(f"      → Models found in filename: {models_found}")
        if models_missing:
            log(f"      → Models missing from filename: {models_missing}")
        
        if all(model in basename for model in models):
            valid_files.append(fpath)
            log(f"    ✓ Found: {basename} (resolution: {time_res})")
        else:
            log(f"      → Skipping file (not all models present)", "WARNING")
    
    if skipped_unsupported:
        log(f"    Skipped {len(skipped_unsupported)} file(s) with unsupported temporal resolution (evaltools only supports hourly/daily)")
        for fname, time_res in skipped_unsupported:
            log(f"      - {fname} (resolution: {time_res})")
    
    if not valid_files:
        log(f"    Warning: Found {len(matching_files)} file(s) but none contain all models: {models}", "WARNING")
    
    return valid_files

###############################################################################
# NETCDF READING
###############################################################################

def parse_qlc_filename(nc_file):
    """
    Parse qlc-py collocated NetCDF filename to extract metadata.
    
    qlc-py filename pattern:
    qlc_D1_<model>_<region>_<station_file_info>_<species>_<daterange>_<time_avg>_collocated_obs_<obs_source>_<time_avg>_mod_<models>_<time_avg>.nc
    
    Example:
    qlc_D1_IFS_EU_ebas_station-locations-208101_stations_NH4_as_20181201-20181221_daily_collocated_obs_ebas_daily_mod_b2ro_b2rn_daily.nc
    
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
        if basename.endswith('.nc'):
            name = basename[:-3]
            parts = name.split('_')
            
            # Time average is last part
            if parts:
                metadata['time_avg'] = parts[-1].lower()
            
            # Try to extract other metadata
            # Pattern: qlc_D1_<model>_<region>_...
            if len(parts) >= 4 and parts[0] == 'qlc' and parts[1] == 'D1':
                metadata['model_type'] = parts[2]  # e.g., 'IFS'
                metadata['region'] = parts[3]      # e.g., 'EU'
            
            # Find species (appears before date range)
            # Look for date range first (YYYYMMDD-YYYYMMDD pattern)
            date_idx = None
            for i, part in enumerate(parts):
                if len(part) >= 17 and '-' in part and part.replace('-', '').isdigit():
                    date_idx = i
                    metadata['date_range'] = part
                    break
            
            # Species is the part immediately before the date range
            # Handle multi-part species names like NH4_as by checking previous parts
            if date_idx is not None and date_idx > 0:
                # Try to reconstruct species name (may be split across underscores)
                # Known pattern: after "stations" comes the species
                try:
                    stations_idx = parts.index('stations')
                    # Species is everything between 'stations' and date_idx
                    if stations_idx + 1 < date_idx:
                        species_parts = parts[stations_idx + 1:date_idx]
                        metadata['species'] = '_'.join(species_parts)
                except ValueError:
                    # Fallback: just use the part immediately before date
                    metadata['species'] = parts[date_idx - 1]
            
            # Extract model names from the part after 'mod_'
            try:
                mod_idx = parts.index('mod')
                if mod_idx + 1 < len(parts):
                    # Models are between 'mod' and the last time_avg
                    # e.g., mod_b2ro_b2rn_daily -> models = ['b2ro', 'b2rn']
                    models_and_time = parts[mod_idx + 1:]
                    # Remove the last part (time_avg) and collect model names
                    metadata['models'] = models_and_time[:-1] if len(models_and_time) > 1 else []
            except ValueError:
                pass
        
    except Exception as e:
        log(f"    Warning: Error parsing filename: {e}", "DEBUG")
    
    return metadata

def detect_temporal_resolution(nc_file, times):
    """
    Detect temporal resolution from qlc-py filename format.
    
    qlc-py filename pattern:
    qlc_D1_<model>_<region>_<station_file>_<species>_<dates>_<time_avg>_collocated_..._<time_avg>.nc
    
    Example:
    qlc_D1_IFS_EU_ebas_station-locations-208101_stations_NH4_as_20181201-20181221_daily_collocated_obs_ebas_daily_mod_b2ro_b2rn_daily.nc
    
    The temporal resolution is the string immediately before the .nc extension.
    
    Args:
        nc_file: Path to NetCDF file
        times: Array of datetime timestamps (used as fallback)
    
    Returns:
        str: temporal resolution ('hourly', 'daily', 'monthly', etc.)
    """
    basename = os.path.basename(nc_file)
    
    # Extract time resolution from filename: last part before .nc extension
    # Pattern: *_<time_avg>.nc
    if basename.endswith('.nc'):
        # Remove .nc and get the last underscore-separated part
        name_without_ext = basename[:-3]
        parts = name_without_ext.split('_')
        if parts:
            time_resolution = parts[-1].lower()
            # Validate it's a known time resolution
            if time_resolution in ['hourly', 'daily', 'monthly', 'yearly', 'annual']:
                return time_resolution
    
    # Fallback: try to detect from time series
    log(f"    Warning: Could not extract time resolution from filename, inferring from data", "WARNING")
    if len(times) >= 2:
        time_diff = (times[1] - times[0]).total_seconds() / 3600  # hours
        if time_diff <= 1.5:  # <= 1.5 hours
            return 'hourly'
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
            
            return obs_df, model_dfs, station_metadata, series_type
    
    except Exception as e:
        log(f"    Error reading NetCDF: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return None, None, None, series_type

###############################################################################
# EVALTOOLS CONVERSION
###############################################################################

def create_observations_from_df(obs_df, species, start_date, end_date, stations, series_type='daily', debug=False):
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
        
        # Ensure all dates are present (fill missing with NaN)
        date_range = pd.date_range(start=start_date, end=end_date, freq='D')
        obs_pivot = obs_pivot.reindex(date_range)
        
        # Get station index from DataFrame or use as-is if already an Index
        station_index = stations.index if isinstance(stations, pd.DataFrame) else stations
        
        # Ensure all stations from listing are present
        for station in station_index:
            if station not in obs_pivot.columns:
                obs_pivot[station] = np.nan
        
        obs_pivot = obs_pivot[station_index]  # Reorder columns to match station listing
        
        log(f"    Observation matrix shape: {obs_pivot.shape}")
        log(f"    Valid data points: {obs_pivot.notna().sum().sum()}")
        
        # Convert station list to plain Python list
        station_list = [str(s) for s in obs_pivot.columns]
        
        if debug:
            log(f"    Station list type: {type(station_list)}", "DEBUG")
            log(f"    First 3 stations: {station_list[:3]}", "DEBUG")
        
        # Create evaltools Dataset and populate with data
        dataset = evt.Dataset(
            stations=station_list,
            startDate=start_date,
            endDate=end_date,
            species=species,
            seriesType=series_type
        )
        dataset.updateFromDataset(obs_pivot)
        
        # Create Observations object - use a workaround to avoid constructor issues
        # Create an empty Observations object by manually setting attributes
        observations = object.__new__(evt.evaluator.Observations)
        # Set the dataset and required attributes
        observations.dataset = dataset
        observations.path = ''
        observations.forecastHorizon = 1
        
        # Create stations DataFrame with metadata (matching evaltools format)
        # Extract station metadata from stations parameter (which should be a DataFrame with name, lat, lon, altitude)
        if isinstance(stations, pd.DataFrame):
            # stations already has the metadata
            stations_df = stations.copy()
        else:
            # Create a minimal DataFrame with station IDs
            stations_df = pd.DataFrame({
                'name': dataset.data.columns,
                'lat': 0.0,
                'lon': 0.0,
                'altitude': 0
            }, index=dataset.data.columns)
        
        observations.__dict__['stations'] = stations_df
        observations.__dict__['forecastHorizon'] = 1
        observations.__dict__['path'] = ''
        
        log(f"    Observations object created successfully")
        return observations
    
    except Exception as e:
        log(f"    Error creating Observations: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return None

def create_simulations_from_df(model_df, model_name, species, start_date, end_date, 
                                stations, series_type='daily', debug=False):
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
        
        # Ensure all dates are present
        date_range = pd.date_range(start=start_date, end=end_date, freq='D')
        sim_pivot = sim_pivot.reindex(date_range)
        
        # Get station index from DataFrame or use as-is if already an Index
        station_index = stations.index if isinstance(stations, pd.DataFrame) else stations
        
        # Ensure all stations from listing are present
        for station in station_index:
            if station not in sim_pivot.columns:
                sim_pivot[station] = np.nan
        
        sim_pivot = sim_pivot[station_index]  # Reorder columns
        
        log(f"    Simulation matrix shape: {sim_pivot.shape}")
        log(f"    Valid data points: {sim_pivot.notna().sum().sum()}")
        
        # Convert station list to plain Python list
        station_list = [str(s) for s in sim_pivot.columns]
        
        if debug:
            log(f"    Station list type: {type(station_list)}", "DEBUG")
            log(f"    First 3 stations: {station_list[:3]}", "DEBUG")
        
        # Create evaltools Dataset and populate with data
        dataset = evt.Dataset(
            stations=station_list,
            startDate=start_date,
            endDate=end_date,
            species=species,
            seriesType=series_type
        )
        dataset.updateFromDataset(sim_pivot)
        
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
        if isinstance(stations, pd.DataFrame):
            # stations already has the metadata
            stations_df = stations.copy()
        else:
            # Create a minimal DataFrame with station IDs
            stations_df = pd.DataFrame({
                'name': dataset.data.columns,
                'lat': 0.0,
                'lon': 0.0,
                'altitude': 0
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

def process_species(species, config, stations, model_colors, debug=False):
    """
    Process a single species: convert collocated NetCDF to evaluators.
    
    Returns:
        Number of successfully created evaluators
    """
    log(f"\n{'='*80}")
    log(f"Processing species: {species}")
    log(f"{'='*80}")
    
    success_count = 0
    
    # Find collocated NetCDF files
    collocation_files = find_collocation_files(
        config['plots_dir'],
        species,
        config['models'],
        config['start_date'],
        config['end_date']
    )
    
    if not collocation_files:
        log(f"  No collocated files found for {species}, skipping", "WARNING")
        return 0
    
    # Process each collocation file (typically one per species+date range+models combination)
    for nc_file in collocation_files:
        log(f"\n--- Processing file: {os.path.basename(nc_file)} ---")
        
        # Read collocated data
        obs_df, model_dfs, station_metadata, series_type = read_collocated_netcdf(
            nc_file, species, config['models'],
            config['start_date'], config['end_date'],
            debug=debug
        )
        
        if obs_df is None or not model_dfs:
            log(f"  Skipping file due to read errors", "WARNING")
            continue
        
        # Add station metadata to evaltools listing if needed
        # This ensures evaltools has the station coordinates
        station_list = station_metadata['site_id'].tolist()
        
        # Create Observations object (shared across all models)
        observations = create_observations_from_df(
            obs_df, species,
            config['start_date'], config['end_date'],
            stations,
            series_type=series_type,
            debug=debug
        )
        
        if observations is None:
            log(f"  Failed to create Observations, skipping file", "ERROR")
            continue
        
        # Create Evaluator for each model
        for model_name, model_df in model_dfs.items():
            log(f"\n--- Creating Evaluator for {model_name} ---")
            
            # Create Simulations object
            simulations = create_simulations_from_df(
                model_df, model_name, species,
                config['start_date'], config['end_date'],
                stations,
                series_type=series_type,
                debug=debug
            )
            
            if simulations is None:
                log(f"  Failed to create Simulations for {model_name}, skipping", "ERROR")
                continue
            
            # Create Evaluator
            color = model_colors.get(model_name, model_colors['default'])
            evaluator = evt.evaluator.Evaluator(observations, simulations, color=color)
            
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
    model_colors = load_model_colors()
    
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
    
    # Find collocated CSV files to extract stations from
    log(f"\nSearching for collocated CSV station files in: {config['plots_dir']}")
    
    collocated_csv_pattern = os.path.join(config['plots_dir'], '*_collocated.csv')
    collocated_csv_files = glob.glob(collocated_csv_pattern)
    
    if not collocated_csv_files:
        log(f"  Warning: No collocated CSV files found matching: {collocated_csv_pattern}", "WARNING")
        log(f"  These files should be created by qlc_D1.sh during collocation", "WARNING")
    else:
        log(f"  Found {len(collocated_csv_files)} collocated CSV file(s)")
        if debug:
            for csv_file in collocated_csv_files[:3]:
                log(f"    - {os.path.basename(csv_file)}", "DEBUG")
    
    # Extract station listing from collocated CSV files
    # This gives us ONLY the stations that actually have collocated data
    converted_listing = os.path.join(config['temp_dir'], 'stations_from_collocated_data.csv')
    
    if collocated_csv_files:
        log(f"\n  Extracting stations from collocated data (stations with actual data)")
        listing_path = extract_stations_from_collocated_csv(
            collocated_csv_files, converted_listing, debug=debug
        )
        
        if listing_path is None:
            log(f"Error: Failed to extract stations from collocated CSV files", "ERROR")
            sys.exit(1)
    else:
        # Fallback: No collocated CSV files found, this shouldn't happen in normal workflow
        log(f"\n  Warning: Using fallback station listing (no collocated CSV files found)", "WARNING")
        listing_path = os.path.join(config['listing_dir'], config['listing_name'])
        
        if not os.path.exists(listing_path):
            log(f"Error: Fallback station listing not found: {listing_path}", "ERROR")
            sys.exit(1)
    
    # Load station listing with evaltools
    try:
        stations = evt.utils.read_listing(listing_path, sep=',')
        log(f"  ✓ Loaded {len(stations)} stations")
        
        if debug:
            log(f"  Station index type: {type(stations.index)}", "DEBUG")
            log(f"  First 3 stations: {list(stations.index[:3])}", "DEBUG")
    except Exception as e:
        log(f"Error loading station listing with evaltools: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    # Statistics
    total_success = 0
    total_errors = 0
    
    # Process each species
    for species in config['species_list']:
        species = species.strip()
        if not species:
            continue
        
        success_count = process_species(species, config, stations, model_colors, debug=debug)
        
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