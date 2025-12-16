#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Extras Installer: Evaltools and PyFerret Integration

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/getting-started/installation/

Description:
    Integrated installation of evaltools (statistical analysis) and PyFerret
    (3D visualization) directly into the QLC virtual environment. Handles all
    dependencies, compatibility patches, and data pre-downloads automatically.

Key Features:
    - Evaltools installation with NumPy 2.x compatibility patch
    - Cartopy installation with Natural Earth data pre-download
    - PyFerret installation (conda, pip, or system modules)
    - No runtime downloads required (all data pre-installed)

Attribution:
    - evaltools: CNRM Open Source by CNRS and Météo-France
      https://redmine.umr-cnrm.fr/projects/evaltools/wiki
    - PyFerret: NOAA/PMEL
      https://github.com/NOAA-PMEL/PyFerret

Usage:
    qlc-install-extras --evaltools
    qlc-install-extras --pyferret
    qlc-install-extras --all

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import argparse
import os
import subprocess
import sys
import tempfile
import urllib.request
import ssl
import zipfile
from pathlib import Path
from typing import Optional, List


def log(message: str, level: str = "INFO") -> None:
    """Simple logging function."""
    print(f"[{level}] {message}")


def run_command(cmd: List[str], cwd: Optional[str] = None, env: Optional[dict] = None, show_output: bool = False) -> bool:
    """Run a command and return success status."""
    try:
        if show_output:
            # For conda commands, show output to provide progress feedback
            result = subprocess.run(cmd, cwd=cwd, env=env, check=True)
        else:
            result = subprocess.run(cmd, cwd=cwd, env=env, check=True, capture_output=True, text=True)
        log(f"Command succeeded: {' '.join(cmd)}")
        return True
    except FileNotFoundError:
        # Command not found (e.g., conda not installed)
        log(f"Command not found: {cmd[0]}", "WARN")
        return False
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {' '.join(cmd)}", "ERROR")
        if not show_output and e.stderr:
            log(f"Error: {e.stderr}", "ERROR")
        return False


def download_file(url: str, dest_path: Path) -> bool:
    """Download a file from URL to destination."""
    try:
        log(f"Downloading {url} to {dest_path}")
        
        # Create SSL context that doesn't verify certificates for problematic URLs
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
        
        # Create request with SSL context
        request = urllib.request.Request(url)
        
        with urllib.request.urlopen(request, context=ssl_context) as response:
            with open(dest_path, 'wb') as f:
                f.write(response.read())
        
        return True
    except Exception as e:
        log(f"Failed to download {url}: {e}", "ERROR")
        return False


def install_cartopy_data(force: bool = False) -> bool:
    """
    Download Natural Earth data to venv-specific Cartopy directory.
    
    This downloads both 50m and 110m resolution data for offline map plotting.
    Data is stored in <venv>/share/cartopy to ensure venv isolation.
    
    Args:
        force: Force re-download even if data already exists
    
    Returns:
        bool: True if download successful, False otherwise
    """
    log("Downloading Cartopy Natural Earth data to venv...")
    
    # Set Cartopy data directory to venv-specific location
    # This ensures data is stored in the active venv, not system-wide
    venv_cartopy_data = Path(sys.prefix) / "share" / "cartopy"
    
    if venv_cartopy_data.exists() and not force:
        log(f"Cartopy data directory already exists: {venv_cartopy_data}")
        log("Use --force to re-download data")
        return True
    
    # Create directory
    venv_cartopy_data.mkdir(parents=True, exist_ok=True)
    
    # Force Cartopy to use venv-specific data directory
    # CRITICAL: Must be set BEFORE importing cartopy
    os.environ['CARTOPY_DATA_DIR'] = str(venv_cartopy_data)
    
    log(f"Setting CARTOPY_DATA_DIR={venv_cartopy_data}")
    log(f"All Natural Earth data will be stored in the active venv")
    
    try:
        # We don't need Cartopy installed to download the data
        # We'll download directly from Natural Earth's S3 bucket
        log(f"Downloading Natural Earth data directly from S3 (bypasses SSL certificate issues)")
        
        # Download required Natural Earth data at BOTH 50m AND 110m resolution
        # Using Cartopy's internal natural_earth() function to force downloads
        # Comprehensive list of Natural Earth shapefiles used by Cartopy
        # Based on actual Cartopy feature requests to avoid runtime downloads
        required_shapefiles = [
            # 50m resolution (high quality for publication mode)
            ('physical', 'coastline', '50m'),
            ('physical', 'rivers_lake_centerlines', '50m'),
            ('physical', 'lakes', '50m'),
            ('physical', 'land', '50m'),
            ('physical', 'ocean', '50m'),
            ('cultural', 'admin_0_countries', '50m'),
            ('cultural', 'admin_0_boundary_lines_land', '50m'),
            ('cultural', 'admin_1_states_provinces', '50m'),
            ('cultural', 'admin_1_states_provinces_lakes', '50m'),
            # 110m resolution (fast mode)
            ('physical', 'coastline', '110m'),
            ('physical', 'rivers_lake_centerlines', '110m'),
            ('physical', 'lakes', '110m'),
            ('physical', 'land', '110m'),
            ('physical', 'ocean', '110m'),
            ('cultural', 'admin_0_countries', '110m'),
            ('cultural', 'admin_0_boundary_lines_land', '110m'),
            ('cultural', 'admin_1_states_provinces', '110m'),
            ('cultural', 'admin_1_states_provinces_lakes', '110m'),
        ]
        
        log("Downloading Natural Earth shapefiles (this may take a few minutes)...")
        log("Using direct download to bypass SSL certificate issues...")
        download_count = 0
        error_count = 0
        
        # Natural Earth base URL
        ne_base_url = "https://naturalearth.s3.amazonaws.com"
        
        for category, name, resolution in required_shapefiles:
            try:
                log(f"  Downloading {category}/ne_{resolution}_{name} ({resolution})...")
                
                # Construct the shapefile name and URL
                shapefile_name = f"ne_{resolution}_{name}"
                
                # Natural Earth URL structure: https://naturalearth.s3.amazonaws.com/[resolution]_[category]/[shapefile_name].zip
                zip_url = f"{ne_base_url}/{resolution}_{category}/{shapefile_name}.zip"
                
                # Create destination directory structure
                dest_dir = venv_cartopy_data / "shapefiles" / "natural_earth" / category
                dest_dir.mkdir(parents=True, exist_ok=True)
                
                # Download the zip file
                zip_path = dest_dir / f"{shapefile_name}.zip"
                
                if download_file(zip_url, zip_path):
                    # Extract the zip file
                    import zipfile
                    try:
                        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                            zip_ref.extractall(dest_dir)
                        # Remove the zip file after extraction
                        zip_path.unlink()
                        
                        # Verify .shp file exists
                        shp_file = dest_dir / f"{shapefile_name}.shp"
                        if shp_file.exists():
                            log(f"  ✓ ne_{resolution}_{name} downloaded and extracted successfully")
                            log(f"    Location: {shp_file}")
                            download_count += 1
                        else:
                            log(f"  ✗ Warning: Extraction succeeded but .shp file not found", "WARN")
                            error_count += 1
                    except zipfile.BadZipFile as e:
                        log(f"  ✗ Warning: Downloaded file is not a valid zip: {e}", "WARN")
                        error_count += 1
                else:
                    log(f"  ✗ Warning: Could not download from {zip_url}", "WARN")
                    error_count += 1
                    
            except Exception as e:
                log(f"  ✗ Warning: Could not download ne_{resolution}_{name}: {e}", "WARN")
                log("  This may cause runtime downloads or errors. Continuing...", "WARN")
                error_count += 1
        
        log(f"Cartopy Natural Earth data download completed")
        log(f"Successfully downloaded: {download_count}/{len(required_shapefiles)} files")
        if error_count > 0:
            log(f"Failed downloads: {error_count}/{len(required_shapefiles)} files", "WARN")
        log(f"All data stored in: {venv_cartopy_data}")
        
        # Verify files actually exist
        total_files = 0
        for root, dirs, files in os.walk(venv_cartopy_data):
            total_files += len([f for f in files if f.endswith(('.shp', '.shx', '.dbf'))])
        log(f"Verification: {total_files} shapefile components found in venv directory")
        
        return error_count == 0  # Success if no errors
        
    except Exception as e:
        log(f"Error downloading Cartopy data: {e}", "ERROR")
        import traceback
        log(traceback.format_exc(), "ERROR")
        return False


def install_evaltools(venv_path: Optional[str] = None, force: bool = False) -> bool:
    """
    Install evaltools into the current or specified virtual environment.
    
    Args:
        venv_path: Path to virtual environment (if None, uses current environment)
        force: Force reinstallation even if already installed
    
    Returns:
        bool: True if installation successful, False otherwise
    """
    log("Installing evaltools into QLC virtual environment...")
    
    # Determine Python executable
    python_exe = sys.executable
    pip_exe = os.path.join(os.path.dirname(python_exe), "pip")
    
    log(f"Using Python: {python_exe}")
    log(f"Using pip: {pip_exe}")
    
    # Check if evaltools is already installed (unless force is specified)
    if not force:
        log("Checking if evaltools is already installed...")
        test_cmd = [python_exe, "-c", "import evaltools; print('Evaltools version:', evaltools.__version__)"]
        try:
            result = subprocess.run(test_cmd, capture_output=True, text=True, check=True)
            log(f"Evaltools is already installed: {result.stdout.strip()}")
            log("Skipping evaltools installation (use --force to reinstall)")
            return True
        except subprocess.CalledProcessError:
            log("Evaltools not found, proceeding with installation...")
    else:
        log("Force installation requested, proceeding with installation...")
    
    # Create temporary directory for downloads
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Download evaltools v1.0.9
        evaltools_url = "https://redmine.umr-cnrm.fr/attachments/download/5300/evaltools_v1.0.9.zip"
        evaltools_zip = temp_path / "evaltools_v1.0.9.zip"
        
        if not download_file(evaltools_url, evaltools_zip):
            return False
        
        # Extract evaltools
        evaltools_dir = temp_path / "evaltools_1.0.9"
        with zipfile.ZipFile(evaltools_zip, 'r') as zip_ref:
            zip_ref.extractall(temp_path)
        
        log(f"Extracted evaltools to: {evaltools_dir}")
        
        # Install pinned dependencies (compatible with QLC 0.4.1+ netCDF stack)
        dependencies = [
            "setuptools>=65.0.0",  # Updated for Python 3.13 compatibility
            "wheel",
            "cython>=0.29.32",
            "numpy>=1.21.0,<2.0",  # Compatible with QLC
            "scipy>=1.9.0,<2.0",   # Compatible with QLC
            "matplotlib>=3.5.0,<4.0",  # Compatible with QLC
            "pandas>=1.5.0,<3.0",  # Compatible with QLC
            "packaging",
            "pyyaml>=6.0",
            "shapely>=2.1.2",
            "netCDF4>=1.7.3",  # Working version that fixes HDF5 errors
            "h5py>=3.15.1",     # Compatible HDF5 Python bindings
            "h5netcdf>=1.7.2",  # Compatible version
        ]
        
        log("Installing evaltools dependencies...")
        for dep in dependencies:
            if not run_command([pip_exe, "install", dep]):
                log(f"Failed to install dependency: {dep}", "WARN")
        
        # Install Cartopy - this is a QLC dependency for map plotting (not just evaltools)
        log("Installing Cartopy (QLC dependency for map plotting)...")
        cartopy_versions = ["cartopy>=0.21.0,<1.0", "cartopy>=0.20.0,<1.0"]
        cartopy_installed = False
        
        for version in cartopy_versions:
            if run_command([pip_exe, "install", "--no-build-isolation", version]):
                cartopy_installed = True
                break
        
        if not cartopy_installed:
            log("Cartopy installation failed - continuing without cartopy", "WARN")
        else:
            # Pre-download Cartopy Natural Earth data during installation to avoid runtime downloads
            # CRITICAL: Store data in venv-specific location, NOT system-wide default
            log("Pre-downloading Cartopy Natural Earth data to venv cartopy directory...")
            try:
                # Set Cartopy data directory to venv-specific location
                # This ensures data is stored in the active venv, not system-wide
                venv_cartopy_data = Path(sys.prefix) / "share" / "cartopy"
                venv_cartopy_data.mkdir(parents=True, exist_ok=True)
                
                # Force Cartopy to use venv-specific data directory
                os.environ['CARTOPY_DATA_DIR'] = str(venv_cartopy_data)
                
                log(f"  Setting CARTOPY_DATA_DIR={venv_cartopy_data}")
                log(f"  All Natural Earth data will be stored in the active venv")
                
                # Import cartopy AFTER setting data directory
                import cartopy.feature as cfeature
                import cartopy.crs as ccrs
                import matplotlib
                matplotlib.use('Agg')  # Non-interactive backend for installation
                import matplotlib.pyplot as plt
                
                # Download required Natural Earth data at BOTH 50m AND 110m resolution
                # QLC uses 50m for publication mode and 110m for fast mode
                # This must be done during installation, NOT at runtime
                required_features = [
                    # 50m resolution (high quality for publication mode)
                    ('physical', 'ne_50m_coastline', '50m', cfeature.COASTLINE),
                    ('physical', 'ne_50m_rivers_lake_centerlines', '50m', cfeature.RIVERS),
                    ('physical', 'ne_50m_lakes', '50m', cfeature.LAKES),
                    ('cultural', 'ne_50m_admin_0_countries', '50m', cfeature.BORDERS),
                    ('cultural', 'ne_50m_admin_1_states_provinces', '50m', cfeature.STATES),
                    # 110m resolution (fast mode)
                    ('physical', 'ne_110m_coastline', '110m', cfeature.COASTLINE),
                    ('physical', 'ne_110m_rivers_lake_centerlines', '110m', cfeature.RIVERS),
                    ('physical', 'ne_110m_lakes', '110m', cfeature.LAKES),
                    ('cultural', 'ne_110m_admin_0_countries', '110m', cfeature.BORDERS),
                    ('cultural', 'ne_110m_admin_1_states_provinces', '110m', cfeature.STATES),
                ]
                
                for category, shapefile_name, resolution, feature in required_features:
                    try:
                        log(f"  Downloading Natural Earth {category}/{shapefile_name} ({resolution})...")
                        # Force download by creating a minimal plot with the feature
                        # This ensures the shapefile is downloaded to venv directory
                        
                        # Create minimal plot to trigger feature download
                        fig = plt.figure(figsize=(1, 1))
                        ax = plt.axes(projection=ccrs.PlateCarree())
                        
                        # Access the feature which triggers download if needed
                        ax.add_feature(feature.with_scale(resolution))
                        
                        plt.close(fig)
                        log(f"  ✓ {shapefile_name} downloaded successfully to venv")
                    except Exception as e:
                        log(f"  WARNING: Could not pre-download {shapefile_name} ({resolution}): {e}", "WARN")
                        log("  This may cause runtime downloads. Continuing installation...", "WARN")
                
                log(f"Cartopy Natural Earth data pre-download completed")
                log(f"All data stored in: {venv_cartopy_data}")
            except ImportError:
                log("Cartopy not available for data pre-download", "WARN")
            except Exception as e:
                log(f"Error pre-downloading Cartopy data: {e}", "WARN")
                log("Natural Earth data will be downloaded on first use (may slow first run)", "WARN")
        
        # Install evaltools
        log("Installing evaltools...")
        if not run_command([pip_exe, "install", "--use-pep517", "--no-build-isolation", str(evaltools_dir)]):
            return False
        
        # Test installation
        log("Testing evaltools installation...")
        test_cmd = [python_exe, "-c", "import evaltools; print('Evaltools version:', evaltools.__version__)"]
        if run_command(test_cmd):
            log("Evaltools installation successful!")
            
            # Apply NumPy 2.x compatibility patch
            log("=" * 50)
            log("Applying evaltools NumPy 2.x compatibility patch...")
            log("=" * 50)
            
            try:
                # Run qlc-fix-evaltools patch
                from qlc.cli.qlc_fix_evaltools import main as fix_evaltools_main
                
                # Save current sys.argv and replace with patch arguments
                import sys as sys_module
                original_argv = sys_module.argv
                sys_module.argv = ["qlc-fix-evaltools"]
                
                try:
                    patch_result = fix_evaltools_main()
                    if patch_result == 0:
                        log("Evaltools patch applied successfully!", "INFO")
                    else:
                        log("Evaltools patch encountered issues (see output above)", "WARN")
                        log("You can manually apply the patch later with: qlc-fix-evaltools", "WARN")
                finally:
                    sys_module.argv = original_argv
                    
            except Exception as e:
                log(f"Failed to apply evaltools patch: {e}", "WARN")
                log("Evaltools is installed but may not work with NumPy >= 2.0", "WARN")
                log("You can manually apply the patch later with: qlc-fix-evaltools", "WARN")
            
            log("=" * 50)
            return True
        else:
            log("Evaltools installation test failed", "ERROR")
            return False


def verify_pyferret_installation(python_exe: str) -> bool:
    """
    Verify that PyFerret installation is working correctly.
    
    Args:
        python_exe: Path to Python executable
    
    Returns:
        bool: True if PyFerret is working, False otherwise
    """
    try:
        # Test 1: Import pyferret
        test_cmd = [python_exe, "-c", "import pyferret; print('PyFerret version:', pyferret.__version__)"]
        result = subprocess.run(test_cmd, capture_output=True, text=True, check=True)
        log(f"PyFerret import test passed: {result.stdout.strip()}")
        
        # Test 2: Try to run pyferret command
        pyferret_cmd = [python_exe, "-c", "import pyferret; pyferret.run('quit')"]
        result = subprocess.run(pyferret_cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            log("PyFerret command execution test passed")
            return True
        else:
            log(f"PyFerret command execution test failed: {result.stderr}", "WARN")
            return False
            
    except subprocess.CalledProcessError as e:
        log(f"PyFerret verification failed: {e.stderr}", "ERROR")
        return False
    except subprocess.TimeoutExpired:
        log("PyFerret verification timed out", "WARN")
        return False
    except Exception as e:
        log(f"PyFerret verification error: {e}", "ERROR")
        return False


def create_pyferret_conda_env(force: bool = False) -> bool:
    """
    Create a dedicated conda environment for PyFerret installation.
    
    Args:
        force: Force recreation even if environment already exists
    
    Returns:
        bool: True if environment creation successful, False otherwise
    """
    log("Creating dedicated conda environment for PyFerret...")
    
    # Check for conda installation
    conda_cmd = None
    for cmd in ["conda", "mamba"]:
        if run_command([cmd, "--version"]):
            conda_cmd = cmd
            break
    
    if not conda_cmd:
        log("Conda not found, cannot create conda environment", "ERROR")
        return False
    
    log(f"Using {conda_cmd} for environment creation")
    
    # Check if environment already exists
    env_name = "FERRET_QLC"
    env_exists = False
    
    try:
        result = subprocess.run([conda_cmd, "env", "list"], capture_output=True, text=True, check=True)
        if env_name in result.stdout:
            env_exists = True
    except subprocess.CalledProcessError:
        log("Failed to check existing conda environments", "WARN")
    
    if env_exists and not force:
        log(f"Conda environment '{env_name}' already exists")
        log("Use --force to recreate the environment")
        return True
    elif env_exists and force:
        log(f"Force recreation requested, removing existing environment '{env_name}'...")
        if not run_command([conda_cmd, "env", "remove", "-n", env_name, "-y"]):
            log("Failed to remove existing environment", "WARN")
    
    # Create the environment
    log(f"Creating conda environment '{env_name}' with PyFerret and ferret_datasets...")
    
    # Check platform for Apple Silicon support
    import platform
    system = platform.system()
    machine = platform.machine()
    
    if system == "Darwin" and machine == "arm64":
        log("macOS ARM64 detected: Using CONDA_SUBDIR=osx-64 for PyFerret installation", "INFO")
        log("This installs x86_64 PyFerret to run under Rosetta 2", "INFO")
        # Use Apple Silicon specific method
        env = os.environ.copy()
        env["CONDA_SUBDIR"] = "osx-64"
        create_cmd = [conda_cmd, "create", "-n", env_name, "-c", "conda-forge/label/pyferret_dev", "pyferret", "ferret_datasets", "-y"]
        log(f"Running: CONDA_SUBDIR=osx-64 {' '.join(create_cmd)}")
        log("This may take several minutes to download and install packages...")
        if run_command(create_cmd, env=env, show_output=True):
            log(f"Conda environment '{env_name}' created successfully!")
            return True
        else:
            log("Failed to create conda environment", "ERROR")
            return False
    else:
        # Standard conda environment creation for other platforms
        create_cmd = [conda_cmd, "create", "-n", env_name, "-c", "conda-forge/label/pyferret_dev", "pyferret", "ferret_datasets", "-y"]
        log(f"Running: {' '.join(create_cmd)}")
        log("This may take several minutes to download and install packages...")
        if run_command(create_cmd, show_output=True):
            log(f"Conda environment '{env_name}' created successfully!")
            return True
        else:
            log("Failed to create conda environment", "ERROR")
            return False


def create_pyferret_dedicated_venv(force: bool = False) -> bool:
    """
    Create a dedicated Python virtual environment for PyFerret installation.
    
    Args:
        force: Force recreation even if environment already exists
    
    Returns:
        bool: True if environment creation successful, False otherwise
    """
    log("Creating dedicated Python virtual environment for PyFerret...")
    
    venv_path = Path.home() / "venv" / "pyferret"
    
    # Check if venv already exists
    if venv_path.exists() and not force:
        log(f"Python virtual environment '{venv_path}' already exists")
        log("Use --force to recreate the environment")
        return True
    elif venv_path.exists() and force:
        log(f"Force recreation requested, removing existing venv '{venv_path}'...")
        import shutil
        shutil.rmtree(venv_path)
    
    # Create the venv
    log(f"Creating Python virtual environment: {venv_path}")
    try:
        import venv
        venv.create(venv_path, with_pip=True)
        log("Virtual environment created successfully")
    except Exception as e:
        log(f"Failed to create virtual environment: {e}", "ERROR")
        return False
    
    # Install PyFerret in the venv
    log("Installing PyFerret in virtual environment...")
    venv_python = venv_path / "bin" / "python"
    venv_pip = venv_path / "bin" / "pip"
    
    # Upgrade pip first
    log("Upgrading pip...")
    if not run_command([str(venv_pip), "install", "--upgrade", "pip"]):
        log("Failed to upgrade pip, continuing anyway", "WARN")
    
    # Check platform for Apple Silicon support
    import platform
    system = platform.system()
    machine = platform.machine()
    
    if system == "Darwin" and machine == "arm64":
        log("macOS ARM64 detected: PyFerret via pip may not work properly", "WARN")
        log("Trying pip installation first, but conda method is recommended for Apple Silicon", "INFO")
    
    # Install PyFerret via pip
    log("Installing PyFerret via pip...")
    if run_command([str(venv_pip), "install", "pyferret"]):
        log("PyFerret installed via pip successfully!")
    else:
        # Try with conda-forge channel
        log("Direct pip installation failed, trying conda-forge channel...")
        if run_command([str(venv_pip), "install", "--extra-index-url", "https://pypi.anaconda.org/conda-forge/simple", "pyferret"]):
            log("PyFerret installed via conda-forge pip successfully!")
        else:
            if system == "Darwin" and machine == "arm64":
                log("PyFerret installation failed in virtual environment on Apple Silicon", "ERROR")
                log("PyFerret via pip is not reliable on macOS ARM64", "ERROR")
                log("Recommended: Use --conda-env instead for Apple Silicon systems", "ERROR")
                log("This creates a conda environment with x86_64 PyFerret under Rosetta 2", "ERROR")
            else:
                log("PyFerret installation failed in virtual environment", "ERROR")
            return False
    
    # Test installation
    if verify_pyferret_installation(str(venv_python)):
        log("PyFerret virtual environment created successfully!")
        log(f"Virtual environment location: {venv_path}")
        log("To activate: source ~/venv/pyferret/bin/activate")
        log("To use PyFerret: python -c 'import pyferret'")
        return True
    else:
        if system == "Darwin" and machine == "arm64":
            log("PyFerret installation verification failed in virtual environment on Apple Silicon", "ERROR")
            log("PyFerret via pip is not reliable on macOS ARM64", "ERROR")
            log("Recommended: Use --conda-env instead for Apple Silicon systems", "ERROR")
            log("This creates a conda environment with x86_64 PyFerret under Rosetta 2", "ERROR")
        else:
            log("PyFerret installation verification failed in virtual environment", "ERROR")
        return False


def create_pyferret_conda_venv(force: bool = False) -> bool:
    """
    Create a conda-based virtual environment for PyFerret installation.
    
    Args:
        force: Force recreation even if environment already exists
    
    Returns:
        bool: True if environment creation successful, False otherwise
    """
    log("Creating conda-based virtual environment for PyFerret...")
    
    venv_path = Path.home() / "venv" / "pyferret"
    
    # Check if venv already exists
    if venv_path.exists() and not force:
        log(f"Conda-based virtual environment '{venv_path}' already exists")
        log("Use --force to recreate the environment")
        return True
    elif venv_path.exists() and force:
        log(f"Force recreation requested, removing existing venv '{venv_path}'...")
        import shutil
        shutil.rmtree(venv_path)
    
    # Check for conda installation
    conda_cmd = None
    for cmd in ["conda", "mamba"]:
        if run_command([cmd, "--version"]):
            conda_cmd = cmd
            break
    
    if not conda_cmd:
        log("Conda not found, cannot create conda-based virtual environment", "ERROR")
        return False
    
    log(f"Using {conda_cmd} for conda-based virtual environment creation")
    
    # Create the conda-based venv
    log(f"Creating conda-based virtual environment: {venv_path}")
    
    # Check platform for Apple Silicon support
    import platform
    system = platform.system()
    machine = platform.machine()
    
    if system == "Darwin" and machine == "arm64":
        log("macOS ARM64 detected: Using CONDA_SUBDIR=osx-64 for PyFerret installation", "INFO")
        log("This installs x86_64 PyFerret to run under Rosetta 2", "INFO")
        # Use Apple Silicon specific method
        env = os.environ.copy()
        env["CONDA_SUBDIR"] = "osx-64"
        create_cmd = [conda_cmd, "create", "-p", str(venv_path), "-c", "conda-forge/label/pyferret_dev", "pyferret", "ferret_datasets", "-y"]
        log(f"Running: CONDA_SUBDIR=osx-64 {' '.join(create_cmd)}")
        log("This may take several minutes to download and install packages...")
        if run_command(create_cmd, env=env, show_output=True):
            log(f"Conda-based virtual environment created successfully!")
            return True
        else:
            log("Failed to create conda-based virtual environment", "ERROR")
            return False
    else:
        # Standard conda-based venv creation for other platforms
        create_cmd = [conda_cmd, "create", "-p", str(venv_path), "-c", "conda-forge/label/pyferret_dev", "pyferret", "ferret_datasets", "-y"]
        log(f"Running: {' '.join(create_cmd)}")
        log("This may take several minutes to download and install packages...")
        if run_command(create_cmd, show_output=True):
            log(f"Conda-based virtual environment created successfully!")
            return True
        else:
            log("Failed to create conda-based virtual environment", "ERROR")
            return False
    
    # Test installation
    if verify_pyferret_installation(str(venv_path / "bin" / "python")):
        log("Conda-based virtual environment created successfully!")
        log(f"Virtual environment location: {venv_path}")
        log("To activate: conda activate ~/venv/pyferret")
        log("To use PyFerret: python -c 'import pyferret'")
        return True
    else:
        log("PyFerret installation verification failed in conda-based virtual environment", "ERROR")
        log("Note: This is a conda environment, activate with: conda activate ~/venv/pyferret", "ERROR")
        return False


def install_pyferret(venv_path: Optional[str] = None, force: bool = False, use_conda_env: bool = False, use_dedicated_venv: bool = False, use_conda_venv: bool = False) -> bool:
    """
    Install pyferret into the current or specified virtual environment.
    
    Args:
        venv_path: Path to virtual environment (if None, uses current environment)
        force: Force reinstallation even if already installed
        use_conda_env: Use dedicated conda environment instead of current environment
        use_dedicated_venv: Use dedicated Python venv ~/venv/pyferret (HPC-friendly)
        use_conda_venv: Use conda-based venv ~/venv/pyferret (Apple Silicon compatible)
    
    Returns:
        bool: True if installation successful, False otherwise
    """
    if use_conda_venv:
        log("Installing PyFerret using conda-based virtual environment...")
        return create_pyferret_conda_venv(force=force)
    elif use_dedicated_venv:
        log("Installing PyFerret using dedicated Python virtual environment...")
        return create_pyferret_dedicated_venv(force=force)
    elif use_conda_env:
        log("Installing PyFerret using dedicated conda environment...")
        return create_pyferret_conda_env(force=force)
    
    log("Installing pyferret into QLC virtual environment...")
    
    # Determine Python executable
    python_exe = sys.executable
    pip_exe = os.path.join(os.path.dirname(python_exe), "pip")
    
    log(f"Using Python: {python_exe}")
    log(f"Using pip: {pip_exe}")
    
    # Check if pyferret is already installed (unless force is specified)
    if not force:
        log("Checking if pyferret is already installed...")
        
        # FIRST: Check for system pyferret (including module-loaded on HPC)
        # This uses the same detection as qlc-install-tools --check
        import shutil
        system_pyferret = shutil.which('pyferret')
        
        if system_pyferret:
            log(f"PyFerret found in system PATH: {system_pyferret}")
            
            # Check if it's from a module system (HPC)
            try:
                from qlc.cli.qlc_install_tools import check_module_system
                modules = check_module_system()
                if modules["module_system"] and modules.get("ferret"):
                    log("PyFerret available via module system (HPC environment)")
                    log("Skipping PyFerret installation (use system modules)")
                    log("Tip: Load module with 'module load ferret'")
                else:
                    log("System PyFerret detected")
                    log("Skipping PyFerret installation (using system installation)")
            except:
                # Fallback if module check fails
                log("System PyFerret detected")
                log("Skipping PyFerret installation (using system installation)")
            
            return True
        
        # SECOND: Check if pyferret is importable as Python module
        test_cmd = [python_exe, "-c", "import pyferret; print('PyFerret version:', pyferret.__version__)"]
        try:
            result = subprocess.run(test_cmd, capture_output=True, text=True, check=True)
            log(f"PyFerret Python module is already installed: {result.stdout.strip()}")
            log("Skipping PyFerret installation (use --force to reinstall)")
            return True
        except subprocess.CalledProcessError:
            log("PyFerret not found in PATH or as Python module, proceeding with installation...")
    else:
        log("Force installation requested, removing existing PyFerret installation...")
        # Remove existing PyFerret installation
        try:
            # Uninstall via pip first
            log("Uninstalling existing PyFerret via pip...")
            subprocess.run([pip_exe, "uninstall", "pyferret", "-y"], 
                         capture_output=True, text=True)
            
            # Remove any symlinks in venv
            venv_bin = Path(os.path.dirname(python_exe))
            venv_pyferret = venv_bin / "pyferret"
            if venv_pyferret.exists():
                log("Removing existing PyFerret symlink...")
                venv_pyferret.unlink()
                
        except Exception as e:
            log(f"Error removing existing PyFerret: {e}", "WARN")
        
        log("Proceeding with fresh PyFerret installation...")
    
    # If we got here, pyferret was not found in system PATH
    # Proceed with installation via conda or pip
    
    # Step 1: Check for conda installation (skip on macOS ARM64)
    import platform
    system = platform.system()
    machine = platform.machine()
    
    log("Checking for conda installation...")
    conda_cmd = None
    for cmd in ["conda", "mamba"]:
        if run_command([cmd, "--version"]):
            conda_cmd = cmd
            break
    
    if conda_cmd:
        log(f"Found {conda_cmd}, attempting PyFerret installation...")
        
        if system == "Darwin" and machine == "arm64":
            log("macOS ARM64 detected: Using CONDA_SUBDIR=osx-64 for PyFerret installation", "INFO")
            log("This installs x86_64 PyFerret to run under Rosetta 2", "INFO")
            # Use Apple Silicon specific method
            env = os.environ.copy()
            env["CONDA_SUBDIR"] = "osx-64"
            conda_install_cmd = [conda_cmd, "install", "-c", "conda-forge/label/pyferret_dev", "pyferret", "ferret_datasets", "-y"]
            log(f"Running: CONDA_SUBDIR=osx-64 {' '.join(conda_install_cmd)}")
            log("This may take several minutes to download and install packages...")
            if run_command(conda_install_cmd, env=env, show_output=True):
                # Test installation
                test_cmd = [python_exe, "-c", "import pyferret; print('PyFerret version:', pyferret.__version__)"]
                if run_command(test_cmd):
                    log("PyFerret installed via conda (x86_64 under Rosetta 2) successfully!")
                    return True
                else:
                    log("PyFerret conda installation failed verification", "WARN")
        else:
            # Standard conda installation for other platforms
            conda_install_cmd = [conda_cmd, "install", "-c", "conda-forge/label/pyferret_dev", "pyferret", "ferret_datasets", "-y"]
            log(f"Running: {' '.join(conda_install_cmd)}")
            log("This may take several minutes to download and install packages...")
            if run_command(conda_install_cmd, show_output=True):
                # Test installation
                test_cmd = [python_exe, "-c", "import pyferret; print('PyFerret version:', pyferret.__version__)"]
                if run_command(test_cmd):
                    log("PyFerret installed via conda successfully!")
                    return True
                else:
                    log("PyFerret conda installation failed verification", "WARN")
    else:
        log("Conda not found, skipping conda installation", "WARN")
    
    # Step 3: Try pip installation methods
    log("Attempting pip-based PyFerret installation...")
    
    # Method 1: Direct pip install
    if run_command([pip_exe, "install", "pyferret"]):
        if verify_pyferret_installation(python_exe):
            log("PyFerret installed via pip successfully!")
            return True
        else:
            log("PyFerret pip installation failed verification", "WARN")
    
    # Method 2: Try with conda-forge channel
    log("Direct pip installation failed, trying conda-forge channel...")
    if run_command([pip_exe, "install", "--extra-index-url", "https://pypi.anaconda.org/conda-forge/simple", "pyferret"]):
        if verify_pyferret_installation(python_exe):
            log("PyFerret installed via conda-forge pip successfully!")
            return True
        else:
            log("PyFerret conda-forge pip installation failed verification", "WARN")
    
    # Method 3: Try with specific version constraints
    log("Trying PyFerret installation with version constraints...")
    pyferret_versions = [
        "pyferret>=7.6.0,<8.0",
        "pyferret>=7.5.0,<8.0", 
        "pyferret>=7.4.0,<8.0"
    ]
    
    for version in pyferret_versions:
        if run_command([pip_exe, "install", version]):
            if verify_pyferret_installation(python_exe):
                log(f"PyFerret installed with version constraint {version} successfully!")
                return True
            else:
                log(f"PyFerret installation with {version} failed verification", "WARN")
    
    # All methods failed
    log("PyFerret installation failed with all methods", "ERROR")
    
    # Provide platform-specific guidance
    if system == "Darwin" and machine == "arm64":
        log("PyFerret installation failed on macOS ARM64 (Apple Silicon)", "WARN")
        log("Recommended solutions:", "INFO")
        log("  1. Use system PyFerret (already detected at /opt/PyFerret/bin/pyferret)", "INFO")
        log("  2. Install PyFerret manually using: CONDA_SUBDIR=osx-64 conda create -n FERRET_QLC -c conda-forge/label/pyferret_dev pyferret ferret_datasets --yes", "INFO")
        log("  3. Use Rosetta 2 terminal to run x86_64 conda installation", "INFO")
        log("  4. Disable PyFerret-dependent scripts in QLC configuration", "INFO")
        log("", "INFO")
        log("For detailed instructions, see: https://github.com/NOAA-PMEL/PyFerret/blob/master/README.md", "INFO")
    else:
        log("PyFerret may not be available for your platform via pip/conda", "WARN")
        log("Please try manual installation:", "INFO")
        log("  conda install -c conda-forge/label/pyferret_dev pyferret ferret_datasets", "INFO")
        log("  Or install system PyFerret and ensure it's in PATH", "INFO")
        log("  Or disable pyferret-dependent scripts in your QLC configuration", "INFO")
    
    return False


def install_cfgrib(force: bool = False) -> bool:
    """
    Install cfgrib and eccodes for GRIB file reading support.
    
    This function installs:
        1. cfgrib - Python package for reading GRIB files
        2. eccodes - Python bindings for ECMWF eccodes library
    
    Args:
        force: Force reinstallation even if already installed
    
    Returns:
        bool: True if installation successful or already installed, False otherwise
    """
    log("Setting up cfgrib for GRIB file reading...")
    
    # Check if cfgrib is already installed
    if not force:
        try:
            import cfgrib
            import eccodes
            log(f"cfgrib already installed: {cfgrib.__version__}")
            log(f"eccodes Python bindings already installed")
            log("Use --force to reinstall")
            return True
        except ImportError:
            pass
    
    # Install eccodes Python bindings first
    log("Installing eccodes Python bindings...")
    if not run_command([sys.executable, "-m", "pip", "install", "eccodes"]):
        log("eccodes installation failed - trying to continue with cfgrib", "WARN")
    else:
        log("eccodes Python bindings installed successfully")
    
    # Install cfgrib
    log("Installing cfgrib package...")
    if not run_command([sys.executable, "-m", "pip", "install", "cfgrib"]):
        log("cfgrib installation failed", "ERROR")
        return False
    
    # Verify installation
    try:
        import cfgrib
        log(f"cfgrib installed successfully: {cfgrib.__version__}")
    except ImportError:
        log("cfgrib installation verification failed", "ERROR")
        return False
    
    # Verify eccodes
    try:
        import eccodes
        log("eccodes Python bindings verified - GRIB file reading is ready to use!")
        return True
    except ImportError:
        log("eccodes Python bindings not available", "WARN")
        log("cfgrib may still work if eccodes system library is installed", "INFO")
        
        # Provide platform-specific guidance
        import platform
        system = platform.system()
        log("", "INFO")
        log("For full GRIB support, install eccodes system library:", "INFO")
        if system == "Darwin":
            log("  macOS: brew install eccodes", "INFO")
        elif system == "Linux":
            log("  Debian/Ubuntu: sudo apt install libeccodes-dev", "INFO")
            log("  RHEL/CentOS: sudo yum install eccodes-devel", "INFO")
            log("  HPC/ATOS: module load eccodes", "INFO")
        return True


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Install evaltools, pyferret, and/or cfgrib into QLC virtual environment (use --all for complete installation)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  qlc-install-extras --evaltools
  qlc-install-extras --pyferret  
  qlc-install-extras --cfgrib
  qlc-install-extras --all
  qlc-install-extras --cartopy_downloads
  qlc-install-extras --cartopy_downloads --force
  qlc-install-extras --evaltools --force
  qlc-install-extras --pyferret --force
  qlc-install-extras --cfgrib
  qlc-install-extras --cfgrib --force
  qlc-install-extras --pyferret --conda-env
  qlc-install-extras --pyferret --conda-env --force
  qlc-install-extras --pyferret --venv
  qlc-install-extras --pyferret --venv --force
  qlc-install-extras --pyferret --conda-venv
  qlc-install-extras --pyferret --conda-venv --force

Important Notes:
  - Cartopy is a QLC dependency for map plotting functionality (not just evaltools)
  - The --evaltools option automatically installs Cartopy (if available)
  - The --cfgrib option automatically installs cfgrib and eccodes Python bindings for GRIB file reading
  - The --cartopy_downloads option downloads Natural Earth data without installing packages
  - All required Cartopy Natural Earth data (50m + 110m resolution) is pre-downloaded
    to <venv>/share/cartopy to prevent runtime downloads
  - Pre-downloaded data includes: coastlines, country borders, state borders, rivers, lakes
  - This ensures QLC map plots work offline without any network access
        """
    )
    
    parser.add_argument("--evaltools", action="store_true", 
                       help="Install evaltools with dependencies and apply NumPy 2.x compatibility patch. Also installs Cartopy (QLC map plotting dependency) and pre-downloads Natural Earth data")
    parser.add_argument("--pyferret", action="store_true",
                       help="Install pyferret")
    parser.add_argument("--cfgrib", action="store_true",
                       help="Install cfgrib and eccodes for GRIB file reading (fully automatic)")
    parser.add_argument("--cartopy_downloads", action="store_true",
                       help="Download Cartopy Natural Earth data (50m + 110m) to venv directory without installing packages")
    parser.add_argument("--all", action="store_true",
                       help="Install evaltools, pyferret, and cfgrib")
    parser.add_argument("--force", action="store_true",
                       help="Force reinstallation/re-download even if already installed")
    parser.add_argument("--conda-env", action="store_true",
                       help="Use dedicated conda environment (FERRET_QLC) for PyFerret installation")
    parser.add_argument("--venv", action="store_true",
                       help="Use dedicated Python venv (~/venv/pyferret) for PyFerret installation (HPC-friendly)")
    parser.add_argument("--conda-venv", action="store_true",
                       help="Use conda-based venv (~/venv/pyferret) for PyFerret installation (Apple Silicon compatible)")
    
    args = parser.parse_args()
    
    if not any([args.evaltools, args.pyferret, args.cfgrib, args.all, args.cartopy_downloads]):
        parser.print_help()
        return 1
    
    success = True
    
    if args.cartopy_downloads:
        if not install_cartopy_data(force=args.force):
            success = False
    
    if args.evaltools or args.all:
        if not install_evaltools(force=args.force):
            success = False
    
    if args.pyferret or args.all:
        if not install_pyferret(force=args.force, use_conda_env=args.conda_env, use_dedicated_venv=args.venv, use_conda_venv=args.conda_venv):
            success = False
    
    if args.cfgrib or args.all:
        if not install_cfgrib(force=args.force):
            success = False
    
    if success:
        log("All installations completed successfully!")
        return 0
    else:
        log("Some installations failed", "ERROR")
        return 1


if __name__ == "__main__":
    sys.exit(main())
