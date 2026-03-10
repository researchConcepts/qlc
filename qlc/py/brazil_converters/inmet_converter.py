"""
INMET Meteorological Data Converter

Converts Brazilian INMET (Instituto Nacional de Meteorologia) automatic weather
station data from CSV to standardized NetCDF format.

Data Characteristics:
  - Period: 2000-2025
  - Resolution: Hourly
  - Time Reference: UTC
  - Format: CSV (semicolon-delimited, comma decimal separator)
  - Metadata: 8-line header with station information
  - Organization: By year directory, one file per station per year

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


class INMETConverter(BrazilDataConverter):
    """
    Converter for INMET meteorological observations.
    
    Handles:
      - CSV parsing with semicolon delimiter and comma decimal
      - 8-line metadata header extraction
      - Station coordinate extraction from header
      - Date/time parsing (already in UTC)
      - Variable name mapping from Portuguese to standard names
    """
    
    def __init__(self, source_dir: Path, output_dir: Path, version: str, config_dir: Path, output_format: str = '2d'):
        """Initialize INMET converter."""
        super().__init__(source_dir, output_dir, version, config_dir, output_format)
        
        # Load variable mapping
        self.var_mapping = self.load_variable_mapping('brazil_inmet_variables.csv')
        
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
        
        logging.info("INMET Converter initialized")
        logging.info(f"  Variable mappings loaded: {len(self.var_mapping)}")
    
    def parse_inmet_header(self, file_path: Path) -> Dict:
        """
        Parse INMET CSV header to extract station metadata.
        
        The header contains 8 lines with station information:
        REGIAO:;CO
        UF:;DF
        ESTACAO:;BRASILIA
        CODIGO (WMO):;A001
        LATITUDE:;-15,78944444
        LONGITUDE:;-47,92583332
        ALTITUDE:;1160,96
        DATA DE FUNDACAO:;07/05/00
        
        Args:
            file_path: Path to INMET CSV file
            
        Returns:
            Dictionary with station metadata
        """
        metadata = {}
        
        try:
            # Try UTF-8 first, fall back to Latin-1
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    for i in range(8):
                        line = f.readline().strip()
                        if ':;' in line:
                            key, value = line.split(':;', 1)
                            metadata[key] = value
            except UnicodeDecodeError:
                logging.debug(f"UTF-8 failed for {file_path.name}, trying Latin-1")
                with open(file_path, 'r', encoding='latin-1') as f:
                    for i in range(8):
                        line = f.readline().strip()
                        if ':;' in line:
                            key, value = line.split(':;', 1)
                            metadata[key] = value
            
            # Extract and clean key fields
            station_id = metadata.get('CODIGO (WMO)', '').strip()
            station_name = metadata.get('ESTACAO', '').strip()
            region = metadata.get('REGIAO', '').strip()
            state = metadata.get('UF', '').strip()
            
            # Parse coordinates (use comma as decimal separator)
            # Handle invalid values gracefully
            try:
                lat_str = metadata.get('LATITUDE', '0').replace(',', '.')
                latitude = float(lat_str)
            except (ValueError, AttributeError):
                logging.warning(f"Invalid latitude in {file_path.name}, skipping station")
                return {}
            
            try:
                lon_str = metadata.get('LONGITUDE', '0').replace(',', '.')
                longitude = float(lon_str)
            except (ValueError, AttributeError):
                logging.warning(f"Invalid longitude in {file_path.name}, skipping station")
                return {}
            
            try:
                alt_str = metadata.get('ALTITUDE', '0').replace(',', '.')
                altitude = float(alt_str)
            except (ValueError, AttributeError):
                logging.debug(f"Invalid altitude in {file_path.name}, using 0.0")
                altitude = 0.0
            
            # Parse founding date
            founding_str = metadata.get('DATA DE FUNDACAO', '')
            
            result = {
                'station_id': station_id,
                'station_name': station_name,
                'region': region,
                'state': state,
                'latitude': latitude,
                'longitude': longitude,
                'altitude': altitude,
                'founding_date': founding_str,
                'network': 'INMET'
            }
            
            logging.debug(f"Parsed header: {station_id} - {station_name}")
            
            return result
            
        except Exception as e:
            logging.error(f"Failed to parse header from {file_path}: {e}")
            return {}
    
    def parse_inmet_csv(self, file_path: Path, metadata: Dict) -> pd.DataFrame:
        """
        Parse INMET CSV data file.
        
        Args:
            file_path: Path to INMET CSV file
            metadata: Station metadata from header
            
        Returns:
            DataFrame with parsed data
        """
        try:
            # Read CSV with specific settings
            # - Skip 8 header lines
            # - Semicolon delimiter
            # - Comma decimal separator
            # - Try UTF-8 first, fall back to Latin-1
            try:
                df = pd.read_csv(
                    file_path,
                    sep=';',
                    decimal=',',
                    skiprows=8,
                    encoding='utf-8',
                    na_values=['-9999', '', ' ']
                )
            except UnicodeDecodeError:
                logging.debug(f"UTF-8 failed for {file_path.name}, trying Latin-1")
                df = pd.read_csv(
                    file_path,
                    sep=';',
                    decimal=',',
                    skiprows=8,
                    encoding='latin-1',
                    na_values=['-9999', '', ' ']
                )
            
            # Check for required columns (handle both old and new INMET formats)
            # Old format (2000-2024): 'DATA (YYYY-MM-DD)' and 'HORA (UTC)'
            # New format (2025+): 'Data' and 'Hora UTC'
            date_col = None
            time_col = None
            
            if 'DATA (YYYY-MM-DD)' in df.columns:
                date_col = 'DATA (YYYY-MM-DD)'
            elif 'Data' in df.columns:
                date_col = 'Data'
            
            if 'HORA (UTC)' in df.columns:
                time_col = 'HORA (UTC)'
            elif 'Hora UTC' in df.columns:
                time_col = 'Hora UTC'
            
            if date_col is None or time_col is None:
                logging.error(f"Required date/time columns not found in {file_path}")
                logging.error(f"Expected: 'DATA (YYYY-MM-DD)' or 'Data', and 'HORA (UTC)' or 'Hora UTC'")
                logging.error(f"Found columns: {list(df.columns)}")
                logging.warning(f"This file has an unsupported format - skipping")
                return pd.DataFrame()
            
            # Combine date and time
            df['datetime_str'] = df[date_col].astype(str) + ' ' + df[time_col].astype(str)
            
            # Parse datetime - handle both formats:
            # Old (2000-2018): 'YYYY-MM-DD HHMM' or 'YYYY-MM-DD HH:MM'
            # New (2019-2025): 'YYYY/MM/DD HHMM UTC' or 'YYYY/MM/DD HH:MM UTC'
            # Try multiple formats
            df['time'] = pd.to_datetime(df['datetime_str'].str.replace(' UTC', ''), format='%Y-%m-%d %H:%M', errors='coerce')
            
            # If that didn't work, try slash format
            if df['time'].isna().all():
                df['time'] = pd.to_datetime(df['datetime_str'].str.replace(' UTC', ''), format='%Y/%m/%d %H:%M', errors='coerce')
            
            # If still not working, try without colon in time
            if df['time'].isna().all():
                df['time'] = pd.to_datetime(df['datetime_str'].str.replace(' UTC', ''), format='%Y-%m-%d %H%M', errors='coerce')
            
            # Last try: slash format without colon
            if df['time'].isna().all():
                df['time'] = pd.to_datetime(df['datetime_str'].str.replace(' UTC', ''), format='%Y/%m/%d %H%M', errors='coerce')
            
            # Remove rows with invalid datetime
            df = df.dropna(subset=['time'])
            
            # Add station information
            df['station_id'] = metadata['station_id']
            df['latitude'] = metadata['latitude']
            df['longitude'] = metadata['longitude']
            df['altitude'] = metadata['altitude']
            
            # Map variable names to standard names
            rename_dict = {}
            for source_name, qlc_name in self.var_name_map.items():
                if source_name in df.columns:
                    rename_dict[source_name] = qlc_name
            
            df = df.rename(columns=rename_dict)
            
            # Keep only relevant columns
            keep_cols = ['time', 'station_id', 'latitude', 'longitude', 'altitude']
            keep_cols.extend([col for col in df.columns if col in self.var_attrs_map.keys()])
            df = df[keep_cols]
            
            logging.debug(f"Parsed {len(df)} records from {file_path.name}")
            
            return df
            
        except Exception as e:
            logging.error(f"Failed to parse CSV {file_path}: {e}")
            return pd.DataFrame()
    
    def process_year(self, year: int) -> Optional[pd.DataFrame]:
        """
        Process all INMET files for a given year.
        
        Args:
            year: Year to process
            
        Returns:
            Combined DataFrame for the year, or None if no data
        """
        year_dir = self.source_dir / str(year)
        
        if not year_dir.exists():
            logging.warning(f"Year directory not found: {year_dir}")
            return None
        
        # Find all CSV files for this year
        csv_files = sorted(glob.glob(str(year_dir / '*.CSV')))
        csv_files.extend(sorted(glob.glob(str(year_dir / '*.csv'))))
        
        if not csv_files:
            logging.warning(f"No CSV files found in {year_dir}")
            return None
        
        logging.info(f"Processing year {year}: {len(csv_files)} files")
        
        # Process each file
        all_data = []
        
        for csv_file in csv_files:
            file_path = Path(csv_file)
            
            try:
                # Parse header for metadata
                metadata = self.parse_inmet_header(file_path)
                
                if not metadata:
                    logging.warning(f"Skipping file with invalid header: {file_path.name}")
                    self.stats['files_failed'] += 1
                    continue
                
                # Validate coordinates
                if not self.validate_coordinates(metadata['latitude'], metadata['longitude']):
                    logging.warning(f"Skipping file with invalid coordinates: {file_path.name}")
                    self.stats['files_failed'] += 1
                    continue
                
                # Parse data
                df = self.parse_inmet_csv(file_path, metadata)
                
                if df.empty:
                    logging.warning(f"No valid data in {file_path.name}")
                    self.stats['files_failed'] += 1
                    continue
                
                all_data.append(df)
                self.stats['files_processed'] += 1
                self.stats['stations_found'].add(metadata['station_id'])
                
            except Exception as e:
                logging.error(f"Error processing {file_path.name}: {e}")
                self.stats['files_failed'] += 1
                continue
        
        if not all_data:
            logging.warning(f"No valid data for year {year}")
            return None
        
        # Combine all data
        combined_df = pd.concat(all_data, ignore_index=True)
        
        # Sort by time and station
        combined_df = combined_df.sort_values(['time', 'station_id']).reset_index(drop=True)
        
        logging.info(f"Year {year}: {len(combined_df)} total records from {len(all_data)} stations")
        
        return combined_df
    
    def convert_year_to_netcdf(self, year: int):
        """
        Convert INMET data for one year to NetCDF (flat record format).
        
        Args:
            year: Year to convert
        """
        logging.info(f"Converting INMET data for year {year}...")
        
        # Process year data
        df = self.process_year(year)
        
        if df is None or df.empty:
            logging.warning(f"No data to convert for year {year}")
            return
        
        logging.info(f"Creating NetCDF dataset for year {year} (flat record format)...")
        logging.debug(f"Total records: {len(df)}")
        logging.debug(f"Stations: {df['station_id'].nunique()}")
        logging.debug(f"Time range: {df['time'].min()} to {df['time'].max()}")
        
        # Update statistics
        times = pd.to_datetime(df['time'].unique())
        if self.stats['time_range'][0] is None or times.min() < self.stats['time_range'][0]:
            self.stats['time_range'][0] = times.min()
        if self.stats['time_range'][1] is None or times.max() > self.stats['time_range'][1]:
            self.stats['time_range'][1] = times.max()
        
        self.stats['records_total'] += len(df)
        self.stats['records_valid'] += len(df)
        
        # Track variables present in data
        variable_attrs = {}
        for var_name in self.var_attrs_map.keys():
            if var_name in df.columns:
                variable_attrs[var_name] = self.var_attrs_map[var_name]
                self.stats['variables_found'].add(var_name)
                logging.debug(f"Variable present: {var_name}")
        
        # Create global attributes
        global_attrs = {
            'title': f'Brazilian INMET Meteorological Observations - {year}',
            'institution': 'Instituto Nacional de Meteorologia (INMET)',
            'source': 'INMET Automatic Weather Stations',
            'network': 'INMET',
            'comment': 'Hourly surface meteorological observations from Brazilian automatic weather stations',
            'time_coverage_start': str(df['time'].min()),
            'time_coverage_end': str(df['time'].max()),
            'geospatial_lat_min': float(df['latitude'].min()),
            'geospatial_lat_max': float(df['latitude'].max()),
            'geospatial_lon_min': float(df['longitude'].min()),
            'geospatial_lon_max': float(df['longitude'].max()),
            'geospatial_vertical_min': float(df['altitude'].min()),
            'geospatial_vertical_max': float(df['altitude'].max()),
            'time_coverage_resolution': 'PT1H',
            'time_reference': 'UTC',
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
            
            # Extract unique station metadata
            station_meta = df.groupby('station_id').agg({
                'latitude': 'first',
                'longitude': 'first',
                'altitude': 'first'
            }).reset_index()
            
            # Get sorted lists for dimensions
            station_ids = sorted(station_meta['station_id'].unique())
            times = sorted(df['time'].unique())
            
            # Create coordinate dictionaries
            latitudes = dict(zip(station_meta['station_id'], station_meta['latitude']))
            longitudes = dict(zip(station_meta['station_id'], station_meta['longitude']))
            altitudes = dict(zip(station_meta['station_id'], station_meta['altitude']))
            
            # Update global attributes
            global_attrs['format'] = '2d_timeseries'
            
            # Pivot DataFrame to create 2D arrays (time × station) for each variable
            # Using pandas pivot for efficiency (avoids nested loops per memory optimization)
            variables = {}
            for var_name in variable_attrs.keys():
                if var_name in df.columns:
                    logging.debug(f"Pivoting variable: {var_name}")
                    # Use pandas pivot to convert from long format to 2D array
                    pivot_df = df.pivot(index='time', columns='station_id', values=var_name)
                    # Reindex to ensure all times and stations are present
                    pivot_df = pivot_df.reindex(index=times, columns=station_ids)
                    # Convert to numpy array
                    variables[var_name] = pivot_df.values.astype(np.float32)
            
            # Use existing 2D creator
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
                df=df,
                variable_attrs=variable_attrs,
                global_attrs=global_attrs
            )
        
        logging.info("Xarray dataset created successfully")
        
        # Save to NetCDF
        output_path = self.output_dir / 'Brazil_INMET' / self.version / str(year)
        output_file = output_path / f'brazil_inmet_{year}.nc'
        logging.info(f"Saving NetCDF to: {output_file}")
        
        self.save_netcdf(ds, output_file, compression=True)
        
        logging.info(f"Year {year} converted successfully: {output_file}")
    
    def convert(self, years: Optional[List[int]] = None, force: bool = False):
        """
        Convert INMET data for specified years or all available years.
        
        Args:
            years: List of years to convert, or None for all years
            force: If True, reprocess existing files; if False, skip existing files
        """
        logging.info("=" * 80)
        logging.info("INMET METEOROLOGICAL DATA CONVERSION")
        logging.info("=" * 80)
        
        # Find available years
        year_dirs = sorted([d for d in self.source_dir.iterdir() if d.is_dir() and d.name.isdigit()])
        available_years = [int(d.name) for d in year_dirs]
        
        if not available_years:
            logging.error(f"No year directories found in {self.source_dir}")
            return
        
        # Filter years if specified
        if years:
            available_years = [y for y in available_years if y in years]
        
        if not available_years:
            logging.error("No valid years to process")
            return
        
        logging.info(f"Available years: {available_years}")
        logging.info(f"Processing {len(available_years)} years")
        
        # Convert each year
        for year in available_years:
            # Check if output file already exists
            output_file = self.output_dir / 'Brazil_INMET' / self.version / str(year) / f'brazil_inmet_{year}.nc'
            
            if output_file.exists() and not force:
                logging.info(f"Year {year}: NetCDF file already exists, skipping (use --force to reprocess)")
                continue
            
            try:
                self.convert_year_to_netcdf(year)
            except Exception as e:
                logging.error(f"Failed to convert year {year}: {e}")
                import traceback
                traceback.print_exc()
                continue
        
        # Create 'latest' symlink
        output_base = self.output_dir / 'Brazil_INMET'
        latest_link = output_base / 'latest'
        version_dir = output_base / self.version
        
        if version_dir.exists():
            if latest_link.exists() or latest_link.is_symlink():
                latest_link.unlink()
            latest_link.symlink_to(self.version, target_is_directory=True)
            logging.info(f"Created symlink: latest -> {self.version}")
        
        # Print statistics
        self.print_statistics()
        
        logging.info("INMET conversion completed!")

