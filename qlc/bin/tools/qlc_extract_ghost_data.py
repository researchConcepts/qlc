#!/usr/bin/env python3
"""
GHOST Data Extraction Tool for QLC

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/user-guide/variable-system/

Description:
    This tool is part of the QLC package and processes GHOST (Globally Harmonised
    Observations in Space and Time) observation data for air quality model evaluation
    to automate the extraction of observation data across multiple networks 
    for QLC analysis. This tool is NOT part of the GHOST project.

Attribution:
    GHOST Data (processed by this tool).
    Citation: Bowdalo, D. R., Mozaffar, A., Witt, M. L. I., et al. (2024)
              Globally Harmonised Observations in Space and Time (GHOST)
              Earth System Science Data, 16, 4417-4441
              https://doi.org/10.5194/essd-16-4417-2024
    Data: https://zenodo.org/records/15075961
    License: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)

Users must cite GHOST appropriately when using GHOST data in publications.
-------------------------------------------------------------------------------
Data Organization:

GHOST Source Structure:
    Networks/<NETWORK>/<frequency>/<variable>.tar.xz
        -> <variable>/<variable>_YYYYMM.nc

QLC Target Structure:
    ghost/<network>/<version>/<YYYYMM>/<variable>_<frequency>.nc

Usage:
    python3 qlc_extract_ghost_data.py [--source SOURCE] [--target TARGET] [--network NETWORK]
    python3 qlc_extract_ghost_data.py --help

# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import argparse
import logging
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import Dict, List, Optional, Set
import tempfile
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

# GHOST network name mapping: source name -> QLC name
GHOST_NETWORK_MAPPING = {
    # EBAS networks - European monitoring
    'EBAS-EUCAARI': 'ebas',
    'EBAS-EUSAAR': 'ebas',
    'EBAS-GUAN': 'ebas',
    'EBAS-HELCOM': 'ebas',
    'EBAS-IMPACTS': 'ebas',
    'EBAS-IMPROVE': 'ebas',
    'EBAS-Independent': 'ebas',
    'EBAS-NILU': 'ebas',
    'EBAS-NOAA_ESRL': 'ebas',
    'EBAS-OECD': 'ebas',
    'EBAS-RI_URBANS': 'ebas',
    'EBAS-WMO_WDCA': 'ebas',
    
    # Regional networks
    'EEA': 'airbase',
    'UK_AIR': 'uk_air',
    'CANADA_NAPS': 'naps',
    'INDAAF': 'indaaf',
    
    # US EPA networks
    'US_EPA_AQS': 'aqs',
    'US_EPA_CASTNET': 'castnet',
    
    # US NADP networks
    'US_NADP_AIRMoN': 'nadp_airmon',
    'US_NADP_MDN': 'nadp_mdn',
    'US_NADP_NTN': 'nadp_ntn',
    
    # Aerosol robotic networks
    'AERONET_v3_lev1.5': 'aeronet_lev15',
    'AERONET_v3_lev2.0': 'aeronet_lev20',
    
    # WMO network
    'WMO_WDCPC': 'wmo_wdcpc',
    
    # GHOST harmonized network (main network with aerosol optical properties)
    'GHOST': 'ghost_harmonized',
}


def get_qlc_home() -> Path:
    """Get QLC_HOME directory."""
    qlc_home = os.environ.get('QLC_HOME')
    if qlc_home:
        return Path(qlc_home).expanduser()
    return Path.home() / 'qlc'


def extract_tar_xz(tar_path: Path, extract_to: Path) -> bool:
    """
    Extract a tar.xz file.
    
    Args:
        tar_path: Path to tar.xz file
        extract_to: Directory to extract to
        
    Returns:
        True if successful, False otherwise
    """
    try:
        logging.debug(f"Extracting {tar_path.name} to {extract_to}")
        with tarfile.open(tar_path, 'r:xz') as tar:
            tar.extractall(path=extract_to)
        return True
    except Exception as e:
        logging.error(f"Failed to extract {tar_path}: {e}")
        return False


def reorganize_ghost_files(
    temp_dir: Path,
    target_dir: Path,
    variable: str,
    frequency: str,
    network: str,
    force: bool = False
) -> Dict[str, int]:
    """
    Reorganize extracted GHOST files from variable/variable_YYYYMM.nc
    to QLC structure: YYYYMM/variable_frequency.nc
    
    Args:
        temp_dir: Temporary extraction directory
        target_dir: Target QLC directory
        variable: Variable name
        frequency: Data frequency (hourly_instantaneous, hourly, daily, monthly)
        network: Network name
        force: If True, overwrite existing files. If False (default), skip existing files (UPDATE mode).
        
    Returns:
        Dictionary with statistics
    """
    stats = {'files': 0, 'skipped': 0, 'months': set()}
    
    # Source files are in temp_dir/variable/variable_YYYYMM.nc
    source_var_dir = temp_dir / variable
    if not source_var_dir.exists():
        logging.warning(f"Variable directory not found: {source_var_dir}")
        return stats
    
    # Process each NetCDF file
    for nc_file in source_var_dir.glob(f"{variable}_*.nc"):
        try:
            # Extract YYYYMM from filename
            parts = nc_file.stem.split('_')
            if len(parts) < 2:
                logging.warning(f"Unexpected filename format: {nc_file.name}")
                continue
            
            yyyymm = parts[-1]
            if len(yyyymm) != 6 or not yyyymm.isdigit():
                logging.warning(f"Invalid date format in filename: {nc_file.name}")
                continue
            
            # Create target directory: target_dir/YYYYMM/
            month_dir = target_dir / yyyymm
            month_dir.mkdir(parents=True, exist_ok=True)
            
            # Target filename: variable_frequency.nc
            target_file = month_dir / f"{variable}_{frequency}.nc"
            
            # Check if file exists (UPDATE mode - default)
            if target_file.exists() and not force:
                logging.debug(f"Skipping existing file: {target_file.name}")
                stats['skipped'] += 1
                stats['months'].add(yyyymm)
                continue
            
            # Copy file (CREATE new or FORCE overwrite mode)
            shutil.copy2(nc_file, target_file)
            if force and target_file.exists():
                logging.debug(f"Overwrote {nc_file.name} -> {target_file.relative_to(target_dir.parent)}")
            else:
                logging.debug(f"Copied {nc_file.name} -> {target_file.relative_to(target_dir.parent)}")
            
            stats['files'] += 1
            stats['months'].add(yyyymm)
            
        except Exception as e:
            logging.error(f"Failed to process {nc_file}: {e}")
    
    return stats


def check_if_extraction_needed(tar_file: Path, target_dir: Path, variable: str, frequency: str, force: bool) -> tuple:
    """
    Check if extraction is needed by listing tar contents and checking target files.
    
    Args:
        tar_file: Path to tar.xz file
        target_dir: Target directory
        variable: Variable name
        frequency: Frequency string
        force: Force mode flag
        
    Returns:
        (needs_extraction, expected_count, existing_count)
    """
    if force:
        return (True, 0, 0)  # Always extract in FORCE mode
    
    try:
        # List tar contents without extracting
        result = subprocess.run(
            ['tar', '-tzf', str(tar_file)],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Count .nc files in tar that match pattern variable_YYYYMM.nc
        tar_contents = result.stdout.strip().split('\n')
        nc_files = [f for f in tar_contents if f.endswith('.nc') and f'{variable}_' in f]
        
        if not nc_files:
            return (True, 0, 0)  # No .nc files found, extract anyway
        
        # Check how many target files already exist
        existing_count = 0
        for nc_file in nc_files:
            # Extract YYYYMM from filename (e.g., absco550/absco550_200801.nc -> 200801)
            nc_basename = Path(nc_file).name
            parts = nc_basename.replace('.nc', '').split('_')
            if len(parts) >= 2:
                yyyymm = parts[-1]
                if len(yyyymm) == 6 and yyyymm.isdigit():
                    # Check if target file exists
                    month_dir = target_dir / yyyymm
                    target_file = month_dir / f"{variable}_{frequency}.nc"
                    if target_file.exists():
                        existing_count += 1
        
        expected_count = len(nc_files)
        
        # If all files exist, skip extraction
        if existing_count == expected_count and expected_count > 0:
            return (False, expected_count, existing_count)
        
        return (True, expected_count, existing_count)
        
    except Exception as e:
        logging.debug(f"Error checking tar contents: {e}")
        return (True, 0, 0)  # Extract on error


def process_network(
    source_network_dir: Path,
    target_base: Path,
    qlc_network: str,
    version: str,
    frequencies: Optional[List[str]] = None,
    force: bool = False
) -> Dict[str, int]:
    """
    Process a single GHOST network.
    
    Args:
        source_network_dir: Source network directory
        target_base: Base target directory (e.g., $HOME/qlc/obs/data/ghost)
        qlc_network: QLC network name
        version: Version string (e.g., v_20251206)
        frequencies: List of frequencies to process (default: all)
        force: If True, overwrite existing files. If False (default), skip existing files (UPDATE mode).
        
    Returns:
        Dictionary with statistics
    """
    stats = {'variables': 0, 'files': 0, 'skipped': 0, 'skipped_extraction': 0, 'months': set()}
    
    if frequencies is None:
        frequencies = ['hourly_instantaneous', 'hourly', 'daily', 'monthly']
    
    # Target directory: ghost/<network>/<version>/
    target_dir = target_base / qlc_network / version
    target_dir.mkdir(parents=True, exist_ok=True)
    
    logging.info(f"Processing network: {source_network_dir.name} -> {qlc_network}")
    
    for frequency in frequencies:
        freq_dir = source_network_dir / frequency
        if not freq_dir.exists():
            logging.debug(f"Frequency directory not found: {freq_dir}")
            continue
        
        logging.info(f"  Processing {frequency} data...")
        
        # Process each variable tar.xz file
        for tar_file in sorted(freq_dir.glob("*.tar.xz")):
            # Remove both .tar and .xz extensions
            # Path.stem only removes the last extension, so we need to do it twice
            variable = Path(tar_file.stem).stem  # Remove .xz, then .tar
            
            # Check if extraction is needed (UPDATE mode optimization)
            needs_extraction, expected, existing = check_if_extraction_needed(
                tar_file, target_dir, variable, frequency, force
            )
            
            if not needs_extraction:
                logging.info(f"    Skipping {variable} (all {existing} files exist)")
                stats['skipped'] += existing
                stats['skipped_extraction'] += 1
                continue
            
            # Extraction needed
            if existing > 0 and not force:
                logging.info(f"    Extracting {variable} ({existing}/{expected} files exist)...")
            else:
                logging.info(f"    Extracting {variable}...")
            
            # Create temporary directory for extraction
            with tempfile.TemporaryDirectory() as temp_dir:
                temp_path = Path(temp_dir)
                
                # Extract tar.xz
                if not extract_tar_xz(tar_file, temp_path):
                    continue
                
                # Reorganize files
                var_stats = reorganize_ghost_files(
                    temp_path,
                    target_dir,
                    variable,
                    frequency,
                    qlc_network,
                    force
                )
                
                if var_stats['files'] > 0 or var_stats['skipped'] > 0:
                    if var_stats['files'] > 0:
                        stats['variables'] += 1
                    stats['files'] += var_stats['files']
                    stats['skipped'] += var_stats['skipped']
                    stats['months'].update(var_stats['months'])
                    
                    if var_stats['files'] > 0 and var_stats['skipped'] > 0:
                        logging.info(f"      Processed {var_stats['files']} files, "
                                   f"skipped {var_stats['skipped']} existing "
                                   f"({len(var_stats['months'])} months)")
                    elif var_stats['files'] > 0:
                        logging.info(f"      Processed {var_stats['files']} files "
                                   f"({len(var_stats['months'])} months)")
                    elif var_stats['skipped'] > 0:
                        logging.info(f"      Skipped {var_stats['skipped']} existing files "
                                   f"({len(var_stats['months'])} months)")
    
    return stats


def create_version_symlink(target_base: Path, network: str, version: str):
    """Create 'latest' symlink pointing to version directory."""
    network_dir = target_base / network
    latest_link = network_dir / 'latest'
    version_dir = network_dir / version
    
    if not version_dir.exists():
        logging.warning(f"Version directory does not exist: {version_dir}")
        return
    
    try:
        # Remove existing symlink if present
        if latest_link.is_symlink() or latest_link.exists():
            latest_link.unlink()
        
        # Create new symlink
        latest_link.symlink_to(version)
        logging.info(f"Created symlink: {latest_link} -> {version}")
        
    except Exception as e:
        logging.error(f"Failed to create symlink: {e}")


def main():
    parser = argparse.ArgumentParser(
        description='Extract and organize GHOST observation data for QLC',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Extract all networks
    python3 qlc_extract_ghost_data.py
    
    # Extract specific network
    python3 qlc_extract_ghost_data.py --network EBAS-EUCAARI
    
    # Custom paths
    python3 qlc_extract_ghost_data.py --source /path/to/GHOST/Networks --target $HOME/qlc/obs/data/ghost
    
    # Specify version
    python3 qlc_extract_ghost_data.py --version v_20251206
        """
    )
    
    parser.add_argument(
        '--source',
        type=Path,
        help='Source directory containing GHOST Networks (default: $HOME/qlc/obs/data/src/GHOST/networks)'
    )
    parser.add_argument(
        '--target',
        type=Path,
        help='Target directory for organized data (default: $HOME/qlc/obs/data/ghost)'
    )
    parser.add_argument(
        '--network',
        type=str,
        help='Process only specific network (e.g., EBAS-EUCAARI, US_EPA_AQS)'
    )
    parser.add_argument(
        '--version',
        type=str,
        default=f'v_20251206',
        help='Version string for target directory (default: v_20251206)'
    )
    parser.add_argument(
        '--frequencies',
        type=str,
        nargs='+',
        choices=['hourly_instantaneous', 'hourly', 'daily', 'monthly'],
        help='Process only specific frequencies (default: all)'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Force overwrite existing files (default: skip existing files in UPDATE mode)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without actually doing it'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Set default paths
    if args.source is None:
        args.source = Path('$HOME/qlc/obs/data/src/GHOST/networks')
    args.source = args.source.expanduser()
    
    if args.target is None:
        qlc_home = get_qlc_home()
        args.target = qlc_home / 'obs' / 'data' / 'ghost'
    args.target = args.target.expanduser()
    
    # Validate source
    if not args.source.exists():
        logging.error(f"Source directory does not exist: {args.source}")
        sys.exit(1)
    
    logging.info(f"GHOST Data Extraction and Organization")
    logging.info(f"Source: {args.source}")
    logging.info(f"Target: {args.target}")
    logging.info(f"Version: {args.version}")
    
    if args.force:
        logging.info("FORCE MODE - Existing files will be overwritten")
    else:
        logging.info("UPDATE MODE - Existing files will be skipped (use --force to overwrite)")
    
    if args.dry_run:
        logging.info("DRY RUN MODE - No files will be modified")
    
    # Collect networks to process
    networks_to_process = []
    
    if args.network:
        # Process specific network
        network_dir = args.source / args.network
        if not network_dir.exists():
            logging.error(f"Network directory not found: {network_dir}")
            sys.exit(1)
        
        qlc_network = GHOST_NETWORK_MAPPING.get(args.network)
        if not qlc_network:
            logging.warning(f"No QLC mapping for {args.network}, using lowercase name")
            qlc_network = args.network.lower().replace('-', '_')
        
        networks_to_process.append((network_dir, qlc_network))
    else:
        # Process all networks with mappings
        for source_name, qlc_name in GHOST_NETWORK_MAPPING.items():
            network_dir = args.source / source_name
            if network_dir.exists():
                networks_to_process.append((network_dir, qlc_name))
    
    if not networks_to_process:
        logging.error("No networks to process")
        sys.exit(1)
    
    logging.info(f"Found {len(networks_to_process)} network(s) to process")
    
    if args.dry_run:
        for network_dir, qlc_name in networks_to_process:
            logging.info(f"Would process: {network_dir.name} -> {qlc_name}")
        sys.exit(0)
    
    # Process each network
    total_stats = {'variables': 0, 'files': 0, 'skipped': 0, 'skipped_extraction': 0, 'networks': 0, 'months': set()}
    
    for network_dir, qlc_network in networks_to_process:
        try:
            stats = process_network(
                network_dir,
                args.target,
                qlc_network,
                args.version,
                args.frequencies,
                args.force
            )
            
            if stats['files'] > 0 or stats['skipped'] > 0:
                total_stats['networks'] += 1
                total_stats['variables'] += stats['variables']
                total_stats['files'] += stats['files']
                total_stats['skipped'] += stats['skipped']
                total_stats['skipped_extraction'] += stats.get('skipped_extraction', 0)
                total_stats['months'].update(stats['months'])
                
                # Create 'latest' symlink
                create_version_symlink(args.target, qlc_network, args.version)
            else:
                logging.warning(f"No files processed for {network_dir.name}")
                
        except Exception as e:
            logging.error(f"Failed to process {network_dir.name}: {e}", exc_info=True)
    
    # Print summary
    logging.info("")
    logging.info("=" * 70)
    logging.info("EXTRACTION COMPLETE")
    logging.info("=" * 70)
    logging.info(f"Networks processed: {total_stats['networks']}")
    logging.info(f"Variables extracted: {total_stats['variables']}")
    logging.info(f"Files created: {total_stats['files']}")
    if total_stats['skipped'] > 0:
        logging.info(f"Files skipped (already exist): {total_stats['skipped']}")
    if total_stats['skipped_extraction'] > 0:
        logging.info(f"Variables skipped (no extraction needed): {total_stats['skipped_extraction']}")
    logging.info(f"Months covered: {len(total_stats['months'])}")
    if total_stats['months']:
        months_sorted = sorted(total_stats['months'])
        logging.info(f"Date range: {months_sorted[0]} to {months_sorted[-1]}")
    logging.info(f"Target directory: {args.target}")
    if args.force:
        logging.info("Mode: FORCE (existing files overwritten)")
    else:
        logging.info("Mode: UPDATE (existing files skipped, no unnecessary extraction)")
    logging.info("=" * 70)


if __name__ == '__main__':
    main()

