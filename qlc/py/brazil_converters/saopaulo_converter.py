"""
São Paulo (CETESB) Air Quality and Meteorology Data Converter

Converts CETESB (Companhia Ambiental do Estado de São Paulo) monitoring data
from hierarchical CSV structure to standardized NetCDF format.

Data Characteristics:
  - Period: 2000-2025
  - Resolution: Hourly
  - Format: CSV (comma-delimited)
  - Character Encoding: UTF-8 or Latin-1 (mixed)
  - Organization: Station/Variable/Year hierarchy
  - File Naming: STATIONCODE_STATIONNAME_VARIABLE_YEAR.csv
  - Variables: Air quality (CO, NO, NO2, NOx, O3, PM10, PM25, SO2) + Meteorology (TEMP, UR, PRESS, DV, VV)

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
"""

import os
import re
import glob
import logging
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from collections import defaultdict

# Import base converter
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from qlc_convert_brazil_data import BrazilDataConverter


class SaoPauloConverter(BrazilDataConverter):
    """
    Converter for São Paulo (CETESB) monitoring network.
    
    Handles:
      - Hierarchical directory structure (Station/Variable/Year)
      - CSV parsing with comma delimiter
      - Character encoding fallback (UTF-8 → Latin-1)
      - Special characters in station names and variable names
      - Combined air quality and meteorological variables
    """
    
    def __init__(self, source_dir: Path, output_dir: Path, version: str, config_dir: Path, output_format: str = '2d'):
        """Initialize São Paulo converter."""
        super().__init__(source_dir, output_dir, version, config_dir, output_format)
        
        # Load variable mapping
        self.var_mapping = self.load_variable_mapping('brazil_sp_variables.csv')
        
        # Create mapping dictionaries (CSV columns: native_name, variable, unit, description)
        self.var_name_map = dict(zip(self.var_mapping['native_name'], self.var_mapping['variable']))
        self.var_attrs_map = {}
        for _, row in self.var_mapping.iterrows():
            self.var_attrs_map[row['variable']] = {
                'long_name': row['description'],
                'units': row['unit']
            }
            # Add optional attributes if present
            if 'valid_min' in row and pd.notna(row['valid_min']):
                self.var_attrs_map[row['variable']]['valid_min'] = row['valid_min']
            if 'valid_max' in row and pd.notna(row['valid_max']):
                self.var_attrs_map[row['variable']]['valid_max'] = row['valid_max']
            if 'standard_name' in row and pd.notna(row['standard_name']):
                self.var_attrs_map[row['variable']]['standard_name'] = row['standard_name']
        
        # Station metadata (will be extracted from directory structure)
        self.station_metadata = {}
        
        # São Paulo timezone
        self.sp_timezone = 'America/Sao_Paulo'
        
        logging.info("São Paulo Converter initialized")
        logging.info(f"  Variable mappings loaded: {len(self.var_mapping)}")
    
    def parse_station_directory_name(self, station_dir: Path) -> Optional[Dict]:
        """
        Parse station directory name to extract station code and name.
        
        Format: 063_Santana, 072_Parque_D_Pedro_II, 095_Cid.Universitária-USP-Ipen
        
        Args:
            station_dir: Path to station directory
            
        Returns:
            Dictionary with station metadata or None
        """
        dir_name = station_dir.name
        
        # Try to match pattern: CODE_NAME
        match = re.match(r'(\d+)_(.+)', dir_name)
        if match:
            station_code = match.group(1)
            station_name = match.group(2).replace('_', ' ').replace('-', ' - ')
            
            return {
                'station_id': f'SP{station_code}',
                'station_name': station_name,
                'state': 'SP',
                'network': 'CETESB'
            }
        
        logging.warning(f"Could not parse station directory name: {dir_name}")
        return None
    
    def parse_sp_csv(self, file_path: Path, variable: str, station_id: str) -> pd.DataFrame:
        """
        Parse São Paulo CSV data file.
        
        Format:
        day,hour,name,pol_name,units,val
        01/01/2000,01:00,Santana,MP10 (Partículas Inaláveis),µg/m3,36.0
        
        Args:
            file_path: Path to CSV file
            variable: Variable identifier from directory structure
            station_id: Station identifier
            
        Returns:
            DataFrame with parsed data
        """
        try:
            # Try UTF-8 first, fall back to Latin-1
            try:
                df = pd.read_csv(file_path, encoding='utf-8')
            except UnicodeDecodeError:
                logging.debug(f"UTF-8 failed, trying Latin-1 for {file_path.name}")
                df = pd.read_csv(file_path, encoding='latin-1')
            
            # Check for required columns
            required_cols = ['day', 'hour', 'val']
            missing_cols = [col for col in required_cols if col not in df.columns]
            
            if missing_cols:
                logging.error(f"Missing columns in {file_path}: {missing_cols}")
                return pd.DataFrame()
            
            # Combine date and time
            df['datetime_str'] = df['day'].astype(str) + ' ' + df['hour'].astype(str)
            
            # Parse datetime (format: DD/MM/YYYY HH:MM)
            df['time_local'] = pd.to_datetime(df['datetime_str'], format='%d/%m/%Y %H:%M', errors='coerce')
            
            # Remove rows with invalid datetime
            df = df.dropna(subset=['time_local'])
            
            # Convert to UTC
            df = self.convert_to_utc(df, 'time_local', self.sp_timezone)
            df = df.rename(columns={'time_local': 'time'})
            
            # Map variable name if pol_name column exists
            if 'pol_name' in df.columns:
                # Use pol_name to determine variable
                df['variable'] = df['pol_name'].map(self.var_name_map)
            else:
                # Use directory variable name
                df['variable'] = variable
            
            # Keep only rows with mapped variables
            df = df.dropna(subset=['variable'])
            
            # Extract relevant columns
            df = df[['time', 'variable', 'val']].copy()
            df = df.rename(columns={'val': 'value'})
            df['station_id'] = station_id
            
            logging.debug(f"Parsed {len(df)} records from {file_path.name}")
            
            return df
            
        except Exception as e:
            logging.error(f"Failed to parse CSV {file_path}: {e}")
            import traceback
            traceback.print_exc()
            return pd.DataFrame()
    
    def map_variable_directory_name(self, var_dir_name: str) -> Optional[str]:
        """
        Map variable directory name to standard QLC name.
        
        Args:
            var_dir_name: Directory name (e.g., PM10, O3, TEMP, UR)
            
        Returns:
            Standard QLC variable name or None (matching case from CSV)
        """
        # Simple mappings for directory names (matching case from brazil_sp_variables.csv)
        dir_map = {
            'PM10': 'PM10',
            'PM25': 'PM25',
            'PM2.5': 'PM2.5',
            'CO': 'CO',
            'NO': 'NO',
            'NO2': 'NO2',
            'NOx': 'NOx',
            'O3': 'O3',
            'SO2': 'SO2',
            'TEMP': 'temp',
            'UR': 'rh',
            'PRESS': 'pressure',
            'DV': 'wind_dir',
            'VV': 'wind_speed'
        }
        
        return dir_map.get(var_dir_name)
    
    def process_station(self, station_dir: Path, years: Optional[List[int]] = None) -> Optional[pd.DataFrame]:
        """
        Process all variables and years for a station.
        
        Args:
            station_dir: Path to station directory
            years: List of years to process, or None for all years
            
        Returns:
            Combined DataFrame for the station or None
        """
        # Parse station metadata
        station_meta = self.parse_station_directory_name(station_dir)
        if not station_meta:
            logging.warning(f"Skipping station with unparseable name: {station_dir.name}")
            return None
        
        station_id = station_meta['station_id']
        self.station_metadata[station_id] = station_meta
        self.stats['stations_found'].add(station_id)
        
        logging.info(f"Processing station: {station_id} - {station_meta['station_name']}")
        
        # Find all variable directories
        var_dirs = [d for d in station_dir.iterdir() if d.is_dir()]
        
        if not var_dirs:
            logging.warning(f"No variable directories found for station {station_id}")
            return None
        
        # Process each variable
        all_data = []
        
        for var_dir in var_dirs:
            var_name_dir = var_dir.name
            var_name = self.map_variable_directory_name(var_name_dir)
            
            if not var_name:
                logging.debug(f"Skipping unmapped variable directory: {var_name_dir}")
                continue
            
            # Find CSV files in variable directory
            csv_files = list(var_dir.glob('*.csv'))
            csv_files.extend(list(var_dir.glob('*.CSV')))
            
            for csv_file in csv_files:
                # Extract year from filename
                match = re.search(r'_(\d{4})\.csv$', csv_file.name, re.IGNORECASE)
                if not match:
                    logging.debug(f"Could not extract year from filename: {csv_file.name}")
                    continue
                
                year = int(match.group(1))
                
                # Check if year should be processed
                if years is not None and year not in years:
                    continue
                
                try:
                    df = self.parse_sp_csv(csv_file, var_name, station_id)
                    
                    if df.empty:
                        logging.debug(f"No valid data in {csv_file.name}")
                        self.stats['files_failed'] += 1
                        continue
                    
                    all_data.append(df)
                    self.stats['files_processed'] += 1
                    
                except Exception as e:
                    logging.error(f"Error processing {csv_file.name}: {e}")
                    self.stats['files_failed'] += 1
                    continue
        
        if not all_data:
            logging.warning(f"No valid data for station {station_id}")
            return None
        
        # Combine all data
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Sort by time and variable
        combined_df = combined_df.sort_values(['time', 'variable']).reset_index(drop=True)
        
        logging.info(f"Station {station_id}: {len(combined_df)} records")
        
        return combined_df
    
    def load_station_locations(self) -> Dict:
        """
        Load station location metadata from external file.
        
        Returns:
            Dictionary mapping station_name to coordinates
        """
        # Try to find station location file (shared with state AQ data)
        station_file = self.source_dir.parent / 'Brasil Air Quality Station Location and Caracteristics.csv'
        
        if not station_file.exists():
            # Try alternative location
            station_file = Path('/Volumes/Data/OBS/Brazil_AQ/Brasil Air Quality Station Location and Caracteristics.csv')
        
        if not station_file.exists():
            logging.warning(f"Station location file not found: {station_file}")
            return {}
        
        try:
            # Read station metadata (handle encoding issues)
            try:
                stations_df = pd.read_csv(station_file, encoding='utf-8', sep='\t')
            except:
                stations_df = pd.read_csv(station_file, encoding='latin-1', sep='\t')
            
            # Extract station coordinates for São Paulo state
            # Columns: Latitude, Longitude, Station1, State2, ...
            station_coords = {}
            
            for _, row in stations_df.iterrows():
                # Only process SP stations
                if row.get('State2') != 'SP':
                    continue
                
                # Get station name
                station_name = None
                if 'Station1' in row:
                    station_name = str(row['Station1']).strip()
                
                if station_name and pd.notna(row['Latitude']) and pd.notna(row['Longitude']):
                    station_coords[station_name] = {
                        'latitude': float(row['Latitude']),
                        'longitude': float(row['Longitude']),
                        'altitude': 0.0  # Default, not provided in this file
                    }
            
            logging.info(f"Loaded coordinates for {len(station_coords)} SP stations from {station_file.name}")
            return station_coords
            
        except Exception as e:
            logging.error(f"Failed to load station locations: {e}")
            return {}
    
    def convert_year_to_netcdf(self, year: int, year_data: pd.DataFrame, station_coords: Dict = None):
        """
        Convert São Paulo data for one year to NetCDF.
        
        Args:
            year: Year to convert
            year_data: DataFrame with columns: time, station_id, variable, value
        """
        format_name = "2D format: time × station" if self.output_format == '2d' else "flat record format"
        logging.info(f"Converting São Paulo data for year {year} ({format_name})...")
        
        # Pivot the data from long format to wide format
        logging.debug("Restructuring data from long to wide format...")
        df_wide = year_data.pivot_table(
            index=['time', 'station_id'],
            columns='variable',
            values='value',
            aggfunc='first'  # Take first value if duplicates exist
        ).reset_index()
        
        # Add station coordinates from external file
        logging.debug("Adding station coordinates...")
        if station_coords is None:
            station_coords = {}
        
        def get_coord(station_id, coord_key):
            # Get station name from metadata
            if station_id in self.station_metadata:
                station_name = self.station_metadata[station_id]['station_name']
                # Look up coordinates by station name
                if station_name in station_coords:
                    return station_coords[station_name].get(coord_key, np.nan if coord_key != 'altitude' else 0.0)
            return np.nan if coord_key != 'altitude' else 0.0
        
        df_wide['latitude'] = df_wide['station_id'].map(lambda sid: get_coord(sid, 'latitude'))
        df_wide['longitude'] = df_wide['station_id'].map(lambda sid: get_coord(sid, 'longitude'))
        df_wide['altitude'] = df_wide['station_id'].map(lambda sid: get_coord(sid, 'altitude'))
        
        # Track statistics
        for station in df_wide['station_id'].unique():
            self.stats['stations_found'].add(station)
        
        times = pd.to_datetime(df_wide['time'].unique())
        if self.stats['time_range'][0] is None or times.min() < self.stats['time_range'][0]:
            self.stats['time_range'][0] = times.min()
        if self.stats['time_range'][1] is None or times.max() > self.stats['time_range'][1]:
            self.stats['time_range'][1] = times.max()
        
        self.stats['records_total'] += len(df_wide)
        self.stats['records_valid'] += len(df_wide)
        
        # Build variable attributes for variables present in data
        variable_attrs = {}
        for var_name in self.var_attrs_map.keys():
            if var_name in df_wide.columns:
                variable_attrs[var_name] = self.var_attrs_map[var_name]
                self.stats['variables_found'].add(var_name)
                logging.debug(f"Variable present: {var_name}")
        
        # Create global attributes
        global_attrs = {
            'title': f'Brazilian São Paulo (CETESB) Air Quality and Meteorology - {year}',
            'institution': 'CETESB - Companhia Ambiental do Estado de São Paulo',
            'source': 'CETESB Air Quality Monitoring Network',
            'network': 'Brazil_SP_CETESB',
            'comment': 'Hourly surface air quality and meteorological observations from São Paulo state monitoring network',
            'time_coverage_start': str(df_wide['time'].min()),
            'time_coverage_end': str(df_wide['time'].max()),
            'time_coverage_resolution': 'PT1H',
            'time_reference': 'UTC (converted from America/Sao_Paulo)',
            'format': 'flat_record',
            'featureType': 'timeSeries',
            'Conventions': 'CF-1.8',
            'conversion_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'),
            'converter_version': '2.0',
            'qlc_version': '1.0.2b0',
            'data_version': self.version,
            'note': 'Station coordinates not available in source data - filled from external station location file'
        }
        
        # Create xarray dataset in requested format
        if self.output_format == '2d':
            logging.info("Creating xarray dataset (2D format: time × station)...")
            
            # For 2D format, pivot data to (time, station) arrays
            times = sorted(df_wide['time'].unique())
            station_ids = sorted(df_wide['station_id'].unique())
            
            # Extract station metadata as dictionaries (required by create_netcdf_dataset)
            # Get unique stations with their coordinates from df_wide (matching INMET pattern)
            station_meta = df_wide.groupby('station_id').agg({
                'latitude': 'first',
                'longitude': 'first',
                'altitude': 'first'
            }).reset_index()
            
            # Create coordinate dictionaries
            latitudes = dict(zip(station_meta['station_id'], station_meta['latitude']))
            longitudes = dict(zip(station_meta['station_id'], station_meta['longitude']))
            altitudes = dict(zip(station_meta['station_id'], station_meta['altitude']))
            
            # Create 2D arrays for each variable using pandas pivot
            variables = {}
            for var_name in [col for col in df_wide.columns if col not in ['time', 'station_id', 'latitude', 'longitude', 'altitude']]:
                if var_name in df_wide.columns:
                    logging.debug(f"Pivoting variable: {var_name}")
                    pivot_df = df_wide.pivot(index='time', columns='station_id', values=var_name)
                    # Reindex to ensure all times and stations are present
                    pivot_df = pivot_df.reindex(index=times, columns=station_ids)
                    variables[var_name] = pivot_df.values.astype(np.float32)
            
            # Use parent class 2D creator
            global_attrs['format'] = '2d_timeseries'
            ds = self.create_netcdf_dataset(
                time=np.array(times),
                station_ids=station_ids,
                latitudes=latitudes,
                longitudes=longitudes,
                altitudes=altitudes,
                variables=variables,
                variable_attrs=variable_attrs,
                global_attrs=global_attrs
            )
        else:  # flat format
            logging.info("Creating xarray dataset (flat record format)...")
            global_attrs['format'] = 'flat_record'
            ds = self.create_netcdf_dataset_flat(
                df=df_wide,
                variable_attrs=variable_attrs,
                global_attrs=global_attrs
            )
        
        # Save to NetCDF
        output_path = self.output_dir / 'Brazil_SP' / self.version / str(year)
        output_file = output_path / f'brazil_sp_{year}.nc'
        
        self.save_netcdf(ds, output_file, compression=True)
        
        logging.info(f"Year {year} converted successfully: {output_file}")
    
    def convert(self, years: Optional[List[int]] = None, force: bool = False):
        """
        Convert São Paulo data for specified years or all available years.
        
        Args:
            years: List of years to convert, or None for all years
            force: If True, reprocess existing files; if False, skip existing files
        """
        logging.info("=" * 80)
        logging.info("SÃO PAULO (CETESB) DATA CONVERSION")
        logging.info("=" * 80)
        
        # Load station coordinates
        station_coords = self.load_station_locations()
        
        # Find all station directories
        station_dirs = sorted([d for d in self.source_dir.iterdir() 
                              if d.is_dir() and re.match(r'\d+_', d.name)])
        
        if not station_dirs:
            logging.error(f"No station directories found in {self.source_dir}")
            return
        
        logging.info(f"Found {len(station_dirs)} station directories")
        
        # Process all stations
        all_data = []
        
        for station_dir in station_dirs:
            try:
                station_data = self.process_station(station_dir, years)
                
                if station_data is not None and not station_data.empty:
                    all_data.append(station_data)
                    
            except Exception as e:
                logging.error(f"Failed to process station {station_dir.name}: {e}")
                continue
        
        if not all_data:
            logging.error("No data to convert")
            return
        
        # Combine all station data
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Group by year and convert
        years_in_data = sorted(combined_df['time'].dt.year.unique())
        
        logging.info(f"Data spans {len(years_in_data)} years: {years_in_data}")
        
        for year in years_in_data:
            # Check if output file already exists
            output_file = self.output_dir / 'Brazil_SP' / self.version / str(year) / f'brazil_sp_{year}.nc'
            
            if output_file.exists() and not force:
                logging.info(f"Year {year}: NetCDF file already exists, skipping (use --force to reprocess)")
                continue
            
            try:
                year_mask = combined_df['time'].dt.year == year
                year_data = combined_df[year_mask].copy()
                
                if year_data.empty:
                    logging.warning(f"No data for year {year}")
                    continue
                
                self.convert_year_to_netcdf(year, year_data, station_coords)
                
            except Exception as e:
                logging.error(f"Failed to convert year {year}: {e}")
                import traceback
                traceback.print_exc()
                continue
        
        # Create 'latest' symlink
        output_base = self.output_dir / 'Brazil_SP'
        latest_link = output_base / 'latest'
        version_dir = output_base / self.version
        
        if version_dir.exists():
            if latest_link.exists() or latest_link.is_symlink():
                latest_link.unlink()
            latest_link.symlink_to(self.version, target_is_directory=True)
            logging.info(f"Created symlink: latest -> {self.version}")
        
        # Print statistics
        self.print_statistics()
        
        logging.info("São Paulo conversion completed!")

