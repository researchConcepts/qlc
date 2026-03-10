"""
State Air Quality Networks Data Converter

Converts Brazilian state air quality monitoring data from CSV to standardized
NetCDF format. Data from various state environmental agencies.

Data Characteristics:
  - Period: 2000-2022 (2023-2025 pending)
  - Resolution: Hourly
  - Time Reference: Local standard time (requires UTC conversion)
  - Format: CSV (comma-delimited)
  - Organization: By state, then by year
  - File Naming: Varies by state (e.g., BA2015.csv, 2016CE.csv, RJ201501.csv)

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


class StateAQConverter(BrazilDataConverter):
    """
    Converter for Brazilian state air quality observations.
    
    Handles:
      - CSV parsing with comma delimiter
      - Variable file naming conventions
      - Local time to UTC conversion based on state location
      - Station location lookup
      - Multiple pollutants in long format (one row per observation)
    """
    
    def __init__(self, source_dir: Path, output_dir: Path, version: str, config_dir: Path, output_format: str = '2d'):
        """Initialize State AQ converter."""
        super().__init__(source_dir, output_dir, version, config_dir, output_format)
        
        # Load variable mapping
        self.var_mapping = self.load_variable_mapping('brazil_aq_variables.csv')
        
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
        
        # Load timezone mapping
        self.tz_mapping = self.load_timezone_mapping()
        self.state_tz_map = dict(zip(self.tz_mapping['state'], self.tz_mapping['timezone']))
        
        # Station metadata (will be populated from files)
        self.station_metadata = {}
        
        logging.info("State AQ Converter initialized")
        logging.info(f"  Variable mappings loaded: {len(self.var_mapping)}")
        logging.info(f"  Timezone mappings loaded: {len(self.tz_mapping)}")
    
    def extract_state_and_year(self, file_path: Path) -> Optional[Tuple[str, int]]:
        """
        Extract state code and year from filename.
        
        Handles various naming conventions:
          - BA2015.csv  → BA, 2015
          - 2016CE.csv  → CE, 2016
          - RJ201501.csv → RJ, 2015
          
        Args:
            file_path: Path to CSV file
            
        Returns:
            Tuple of (state_code, year) or None if cannot parse
        """
        filename = file_path.stem  # without extension
        
        # Try pattern: STATE + YEAR (e.g., BA2015)
        match = re.match(r'([A-Z]{2})(\d{4})', filename)
        if match:
            state = match.group(1)
            year = int(match.group(2))
            return (state, year)
        
        # Try pattern: YEAR + STATE (e.g., 2016CE)
        match = re.match(r'(\d{4})([A-Z]{2})', filename)
        if match:
            year = int(match.group(1))
            state = match.group(2)
            return (state, year)
        
        # Try pattern: STATE + YEAR + MONTH (e.g., RJ201501)
        match = re.match(r'([A-Z]{2})(\d{4})\d{2}', filename)
        if match:
            state = match.group(1)
            year = int(match.group(2))
            return (state, year)
        
        logging.warning(f"Could not extract state/year from filename: {filename}")
        return None
    
    def parse_state_aq_csv(self, file_path: Path, state: str) -> pd.DataFrame:
        """
        Parse state AQ CSV data file.
        
        Format:
        Data,Hora,Estacao,Codigo,Poluente,Valor,Unidade,Tipo
        2015-01-01,00:00,Concordia,BA06,CO,0.36,ppm,automatico
        
        Args:
            file_path: Path to CSV file
            state: Two-letter state code
            
        Returns:
            DataFrame with parsed data
        """
        try:
            # Read CSV - try UTF-8 first, fall back to Latin-1
            try:
                df = pd.read_csv(file_path, encoding='utf-8')
            except UnicodeDecodeError:
                logging.debug(f"UTF-8 failed for {file_path.name}, trying Latin-1")
                df = pd.read_csv(file_path, encoding='latin-1')
            
            # Check for required columns
            required_cols = ['Data', 'Hora', 'Estacao', 'Codigo', 'Poluente', 'Valor']
            missing_cols = [col for col in required_cols if col not in df.columns]
            
            if missing_cols:
                logging.error(f"Missing columns in {file_path}: {missing_cols}")
                return pd.DataFrame()
            
            # Combine date and time
            df['datetime_str'] = df['Data'].astype(str) + ' ' + df['Hora'].astype(str)
            
            # Parse datetime (format: YYYY-MM-DD HH:MM)
            df['time_local'] = pd.to_datetime(df['datetime_str'], format='%Y-%m-%d %H:%M', errors='coerce')
            
            # Remove rows with invalid datetime
            df = df.dropna(subset=['time_local'])
            
            # Convert to UTC based on state timezone
            timezone_str = self.state_tz_map.get(state, 'America/Sao_Paulo')  # Default to São Paulo time
            df = self.convert_to_utc(df, 'time_local', timezone_str)
            df = df.rename(columns={'time_local': 'time'})
            
            # Map pollutant names to standard names
            df['variable'] = df['Poluente'].map(self.var_name_map)
            
            # Keep only mapped variables
            df = df.dropna(subset=['variable'])
            
            # Extract relevant columns
            df = df[['time', 'Codigo', 'Estacao', 'variable', 'Valor']].copy()
            df = df.rename(columns={
                'Codigo': 'station_id',
                'Estacao': 'station_name',
                'Valor': 'value'
            })
            
            # Store station names for metadata
            for station_id, station_name in df[['station_id', 'station_name']].drop_duplicates().values:
                if station_id not in self.station_metadata:
                    self.station_metadata[station_id] = {
                        'name': station_name,
                        'state': state,
                        'network': 'State_AQ'
                    }
            
            logging.debug(f"Parsed {len(df)} records from {file_path.name}")
            
            return df
            
        except Exception as e:
            logging.error(f"Failed to parse CSV {file_path}: {e}")
            import traceback
            traceback.print_exc()
            return pd.DataFrame()
    
    def load_station_locations(self) -> Dict:
        """
        Load station location metadata from external file.
        
        Returns:
            Dictionary mapping station_id to coordinates
        """
        # Try to find station location file
        station_file = self.source_dir.parent / 'Brasil Air Quality Station Location and Caracteristics.csv'
        
        if not station_file.exists():
            logging.warning(f"Station location file not found: {station_file}")
            return {}
        
        try:
            # Read station metadata (handle encoding issues)
            try:
                stations_df = pd.read_csv(station_file, encoding='utf-8', sep='\t')
            except:
                stations_df = pd.read_csv(station_file, encoding='latin-1', sep='\t')
            
            # Extract station coordinates
            # Columns: Latitude, Longitude, Station1, State2, ...
            station_coords = {}
            
            for _, row in stations_df.iterrows():
                # Get station name/code (various possible columns)
                station_id = None
                if 'Station1' in row:
                    station_id = str(row['Station1']).strip()
                
                if station_id and pd.notna(row['Latitude']) and pd.notna(row['Longitude']):
                    station_coords[station_id] = {
                        'latitude': float(row['Latitude']),
                        'longitude': float(row['Longitude']),
                        'altitude': 0.0  # Default, not provided in this file
                    }
            
            logging.info(f"Loaded coordinates for {len(station_coords)} stations from {station_file.name}")
            return station_coords
            
        except Exception as e:
            logging.error(f"Failed to load station locations: {e}")
            return {}
    
    def process_state_year(self, state_files: List[Path]) -> Optional[pd.DataFrame]:
        """
        Process all files for a state/year combination.
        
        Args:
            state_files: List of CSV files to process
            
        Returns:
            Combined DataFrame or None if no data
        """
        all_data = []
        
        for file_path in state_files:
            try:
                # Extract state and year from filename
                result = self.extract_state_and_year(file_path)
                if not result:
                    logging.warning(f"Skipping file with unparseable name: {file_path.name}")
                    self.stats['files_failed'] += 1
                    continue
                
                state, year = result
                
                # Parse CSV
                df = self.parse_state_aq_csv(file_path, state)
                
                if df.empty:
                    logging.warning(f"No valid data in {file_path.name}")
                    self.stats['files_failed'] += 1
                    continue
                
                all_data.append(df)
                self.stats['files_processed'] += 1
                
            except Exception as e:
                logging.error(f"Error processing {file_path.name}: {e}")
                self.stats['files_failed'] += 1
                continue
        
        if not all_data:
            return None
        
        # Combine all data
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Sort by time and station
        combined_df = combined_df.sort_values(['time', 'station_id', 'variable']).reset_index(drop=True)
        
        return combined_df
    
    def convert_year_to_netcdf(self, year: int, year_data: pd.DataFrame, station_coords: Dict):
        """
        Convert state AQ data for one year to NetCDF.
        
        Args:
            year: Year to convert
            year_data: DataFrame with columns: time, station_id, variable, value
            station_coords: Dictionary of station coordinates
        """
        format_name = "2D format: time × station" if self.output_format == '2d' else "flat record format"
        logging.info(f"Converting State AQ data for year {year} ({format_name})...")
        
        # Pivot the data from long format (time, station, variable, value) to wide format
        # where each variable is a column
        logging.debug("Restructuring data from long to wide format...")
        df_wide = year_data.pivot_table(
            index=['time', 'station_id'],
            columns='variable',
            values='value',
            aggfunc='first'  # Take first value if duplicates exist
        ).reset_index()
        
        # Add station coordinates
        # Use station_name (from metadata) to look up coordinates, not station_id (code)
        logging.debug("Adding station coordinates...")
        def get_coord(station_id, coord_key):
            # Get station name from metadata
            if station_id in self.station_metadata:
                station_name = self.station_metadata[station_id]['name']
                # Look up coordinates by station name
                if station_name in station_coords:
                    return station_coords[station_name].get(coord_key, np.nan if coord_key != 'altitude' else 0.0)
            return np.nan if coord_key != 'altitude' else 0.0
        
        df_wide['latitude'] = df_wide['station_id'].map(lambda sid: get_coord(sid, 'latitude'))
        df_wide['longitude'] = df_wide['station_id'].map(lambda sid: get_coord(sid, 'longitude'))
        df_wide['altitude'] = df_wide['station_id'].map(lambda sid: get_coord(sid, 'altitude'))
        
        # Warn about stations without coordinates
        missing_coords = df_wide[df_wide['latitude'].isna()]['station_id'].unique()
        if len(missing_coords) > 0:
            logging.warning(f"No coordinates for {len(missing_coords)} stations")
        
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
            'title': f'Brazilian State Air Quality Observations - {year}',
            'institution': 'Brazilian State Environmental Agencies',
            'source': 'State Air Quality Monitoring Networks',
            'network': 'Brazil_State_AQ',
            'comment': 'Hourly surface air quality observations from Brazilian state monitoring networks',
            'time_coverage_start': str(df_wide['time'].min()),
            'time_coverage_end': str(df_wide['time'].max()),
            'geospatial_lat_min': float(df_wide['latitude'].min()),
            'geospatial_lat_max': float(df_wide['latitude'].max()),
            'geospatial_lon_min': float(df_wide['longitude'].min()),
            'geospatial_lon_max': float(df_wide['longitude'].max()),
            'time_coverage_resolution': 'PT1H',
            'time_reference': 'UTC (converted from local time)',
            'format': 'flat_record',
            'featureType': 'timeSeries',
            'Conventions': 'CF-1.8',
            'conversion_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'),
            'converter_version': '2.0',
            'qlc_version': '1.0.2b0',
            'data_version': self.version
        }
        
        # Create xarray dataset in requested format
        if self.output_format == '2d':
            logging.info("Creating xarray dataset (2D format: time × station)...")
            
            # For 2D format, we need to pivot data to (time, station) arrays
            # Get unique times and stations
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
        output_path = self.output_dir / 'Brazil_AQ' / self.version / str(year)
        output_file = output_path / f'brazil_aq_{year}.nc'
        
        self.save_netcdf(ds, output_file, compression=True)
        
        logging.info(f"Year {year} converted successfully: {output_file}")
    
    def convert(self, years: Optional[List[int]] = None, force: bool = False):
        """
        Convert State AQ data for specified years or all available years.
        
        Args:
            years: List of years to convert, or None for all years
            force: If True, reprocess existing files; if False, skip existing files
        """
        logging.info("=" * 80)
        logging.info("STATE AIR QUALITY DATA CONVERSION")
        logging.info("=" * 80)
        
        # Load station coordinates
        station_coords = self.load_station_locations()
        
        # Find all CSV files across all states
        state_dirs = sorted([d for d in self.source_dir.iterdir() 
                           if d.is_dir() and len(d.name) == 2 and d.name.isupper()])
        
        if not state_dirs:
            logging.error(f"No state directories found in {self.source_dir}")
            return
        
        logging.info(f"Found {len(state_dirs)} state directories")
        
        # Collect all files and group by year
        year_files = defaultdict(list)
        
        for state_dir in state_dirs:
            csv_files = list(state_dir.glob('*.csv'))
            csv_files.extend(list(state_dir.glob('*.CSV')))
            
            for csv_file in csv_files:
                result = self.extract_state_and_year(csv_file)
                if result:
                    _, year = result
                    if years is None or year in years:
                        year_files[year].append(csv_file)
        
        available_years = sorted(year_files.keys())
        
        if not available_years:
            logging.error("No valid years to process")
            return
        
        logging.info(f"Available years: {available_years}")
        logging.info(f"Processing {len(available_years)} years")
        
        # Convert each year
        for year in available_years:
            # Check if output file already exists
            output_file = self.output_dir / 'Brazil_AQ' / self.version / str(year) / f'brazil_aq_{year}.nc'
            
            if output_file.exists() and not force:
                logging.info(f"Year {year}: NetCDF file already exists, skipping (use --force to reprocess)")
                continue
            
            try:
                logging.info(f"Processing year {year} ({len(year_files[year])} files)...")
                
                # Process all files for this year
                year_data = self.process_state_year(year_files[year])
                
                if year_data is None or year_data.empty:
                    logging.warning(f"No data to convert for year {year}")
                    continue
                
                # Convert to NetCDF
                self.convert_year_to_netcdf(year, year_data, station_coords)
                
            except Exception as e:
                logging.error(f"Failed to convert year {year}: {e}")
                import traceback
                traceback.print_exc()
                continue
        
        # Create 'latest' symlink
        output_base = self.output_dir / 'Brazil_AQ'
        latest_link = output_base / 'latest'
        version_dir = output_base / self.version
        
        if version_dir.exists():
            if latest_link.exists() or latest_link.is_symlink():
                latest_link.unlink()
            latest_link.symlink_to(self.version, target_is_directory=True)
            logging.info(f"Created symlink: latest -> {self.version}")
        
        # Print statistics
        self.print_statistics()
        
        logging.info("State AQ conversion completed!")

