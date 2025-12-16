#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Runtime Installation: Core Setup Module

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/getting-started/installation/

Description:
    Core installation module that sets up the QLC runtime environment including
    directory structure, configuration files, example data, workflow templates,
    and optional tools (TinyTeX, PyFerret, Natural Earth data).

Entry Point:
    This module is called via the 'qlc-install' command
    Users run: qlc-install --mode test|cams|dev
    Example:   qlc-install --mode test

Key Functions:
    - setup(): Main installation orchestrator
    - install_tinytex(): Cross-platform LaTeX installation
    - install_pyferret(): PyFerret 3D visualization tool
    - install_natural_earth_data(): Cartopy map data pre-download
    - setup_data_directories(): Two-stage directory structure
    - link_model_experiments(): Example data linking

Installation Modes:
    - test: Testing with example data (recommended for first-time users)
    - cams: Operational CAMS environment (HPC with MARS access)
    - dev: Development mode (creates qlc-dev runtime)

Features:
    - Automatic environment detection
    - Virtual environment integration
    - HPC module system support
    - Example data management
    - Tool availability checking
    - Comprehensive validation

Usage:
    Called automatically via 'qlc-install' command - Can also import directly
    For help: qlc-install -h

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import os
import sys
import shutil
import argparse
import json
import subprocess
from pathlib import Path
try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    import tomli as tomllib  # Python < 3.11

def get_version_from_pyproject(pyproject_path: Path) -> str:
    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)
    return config["project"]["version"]

def read_version_json(version_json_path: Path) -> dict:
    if not version_json_path.exists():
        raise FileNotFoundError(f"[ERROR] VERSION.json not found: {version_json_path}")
    with version_json_path.open("r", encoding="utf-8") as f:
        return json.load(f)

def get_bin_path():
    """Get the bin directory of the current Python environment (venv or system)"""
    # Always check VIRTUAL_ENV first - this is the most reliable way
    venv_path = os.environ.get('VIRTUAL_ENV')
    if venv_path:
        venv_bin = Path(venv_path) / 'bin'
        print(f"[DEBUG] Using VIRTUAL_ENV: {venv_bin}")
        return venv_bin
    
    # Fallback to sys.executable detection
    python_path = Path(sys.executable).resolve()
    print(f"[DEBUG] No VIRTUAL_ENV, using sys.executable: {python_path.parent}")
    return python_path.parent

def install_tinytex(venv_path: Path):
    """
    Cross-platform TinyTeX installation with intelligent detection.
    Priority: Module system -> System PATH -> venv installation
    """
    # Check if TinyTeX installation should be skipped
    if os.environ.get('QLC_SKIP_TINYTEX', '').lower() in ['1', 'true', 'yes']:
        print("[TinyTeX] Skipping TinyTeX installation (QLC_SKIP_TINYTEX=1)")
        return True
    
    print(f"[TinyTeX] Setting up cross-platform LaTeX for QLC venv: {venv_path}")
    
    # Check if TinyTeX is already installed in the venv
    venv_bin = venv_path / "bin"
    venv_xelatex = venv_bin / "xelatex"
    if venv_xelatex.exists():
        print("[TinyTeX] TinyTeX already installed in QLC venv")
        return True
    
    # Step 1: Check if module system is available and has texlive
    print("[TinyTeX] Checking for module system (ATOS/HPC)...")
    module_check = subprocess.run(['which', 'module'], capture_output=True, text=True)
    if module_check.returncode == 0:
        print("[TinyTeX] Module system detected, checking for texlive...")
        # Use bash to execute module command since it's a shell function
        module_avail = subprocess.run(['bash', '-c', 'module avail texlive'], capture_output=True, text=True)
        if module_avail.returncode == 0 and 'texlive' in module_avail.stdout:
            print("[TinyTeX] texlive module available - will be loaded by scripts")
            print("[TinyTeX] No venv installation needed (using module system)")
            return True
        else:
            print("[TinyTeX] texlive module not available")
    
    # Step 2: Check system PATH for existing LaTeX installation
    print("[TinyTeX] Checking system PATH for LaTeX...")
    
    # Define search paths for LaTeX binaries
    latex_search_paths = [
        "/usr/bin",
        "/usr/local/bin", 
        "/opt/bin",
        "/opt/local/bin",
        "/opt/homebrew/bin",
        "/opt/PyFerret/bin",
        str(Path.home() / ".local" / "bin")
    ]
    
    # Priority order: pdflatex (preferred), xelatex (fallback), lualatex
    latex_commands = ['pdflatex', 'xelatex', 'lualatex']
    
    found_latex = {}
    for cmd in latex_commands:
        # First try 'which' command
        which_result = subprocess.run(['which', cmd], capture_output=True, text=True)
        if which_result.returncode == 0:
            found_latex[cmd] = which_result.stdout.strip()
            continue
            
        # If 'which' fails, search in specific paths
        for search_path in latex_search_paths:
            cmd_path = Path(search_path) / cmd
            if cmd_path.exists():
                found_latex[cmd] = str(cmd_path)
                break
    
    if found_latex:
        # Use pdflatex if available, otherwise xelatex
        primary_cmd = 'pdflatex' if 'pdflatex' in found_latex else 'xelatex'
        primary_path = found_latex[primary_cmd]
        
        print(f"[TinyTeX] Found system LaTeX: {primary_cmd} at {primary_path}")
        
        # Create symlinks in venv for system LaTeX
        venv_bin.mkdir(parents=True, exist_ok=True)
        for cmd in latex_commands:
            if cmd in found_latex:
                cmd_path = venv_bin / cmd
                if not cmd_path.exists():
                    cmd_path.symlink_to(found_latex[cmd])
                    print(f"[TinyTeX] Linked system {cmd} to venv")
        
        print(f"[TinyTeX] Using system LaTeX installation (primary: {primary_cmd})")
        return True
    
    # Step 3: Install TinyTeX in venv as fallback
    print("[TinyTeX] No system LaTeX found, installing TinyTeX in venv...")
    try:
        # Check if PyTinyTeX package is available
        import_result = subprocess.run([
            sys.executable, '-c', 'import pytinytex'
        ], capture_output=True, text=True, timeout=10)
        
        if import_result.returncode != 0:
            print("[TinyTeX] Installing PyTinyTeX dependencies...")
            deps_result = subprocess.run([
                sys.executable, '-m', 'pip', 'install', 'torch', 'torchvision', 'tinycio', 'scikit-fmm', 'pytinytex'
            ], capture_output=True, text=True, timeout=120)
            
            if deps_result.returncode != 0:
                print(f"[TinyTeX] Dependency installation failed: {deps_result.stderr}")
                return False
        
        # Install TinyTeX using PyTinyTeX
        install_result = subprocess.run([
            sys.executable, '-c', 
            'import pytinytex; pytinytex.download_tinytex(variation=1)'
        ], capture_output=True, text=True, timeout=300)
        
        if install_result.returncode == 0:
            print("[TinyTeX] TinyTeX installation completed")
            
            # Find and link TinyTeX binaries (cross-platform)
            venv_bin.mkdir(parents=True, exist_ok=True)
            
            # Search for TinyTeX installation (cross-platform)
            search_paths = [
                Path.home() / ".pytinytex" / "bin",
                Path.home() / "Library" / "TinyTeX" / "bin",
                Path.home() / ".local" / "bin",
                Path.home() / "TinyTeX" / "bin",
            ]
            
            # Add platform-specific subdirectories
            import platform
            system = platform.system().lower()
            machine = platform.machine().lower()
            
            if system == "darwin":
                platform_dirs = ["universal-darwin", "x86_64-darwin", "arm64-darwin"]
            elif system == "linux":
                platform_dirs = ["x86_64-linux", "aarch64-linux", "i386-linux"]
            else:
                platform_dirs = [f"{machine}-{system}"]
            
            tinytex_bin = None
            for base_path in search_paths:
                for platform_dir in platform_dirs:
                    test_path = base_path / platform_dir
                    if test_path.exists() and (test_path / "xelatex").exists():
                        tinytex_bin = test_path
                        break
                if tinytex_bin:
                    break
            
            if tinytex_bin:
                print(f"[TinyTeX] Found TinyTeX at: {tinytex_bin}")
                # Priority order: pdflatex (preferred), xelatex (fallback), lualatex, tlmgr
                for cmd in ['pdflatex', 'xelatex', 'lualatex', 'tlmgr']:
                    cmd_path = venv_bin / cmd
                    tinytex_cmd = tinytex_bin / cmd
                    if tinytex_cmd.exists() and not cmd_path.exists():
                        cmd_path.symlink_to(tinytex_cmd)
                        print(f"[TinyTeX] Linked {cmd} to venv")
            else:
                print("[TinyTeX] Warning: Could not find TinyTeX binaries to link")
            
            return True
        else:
            print(f"[TinyTeX] Installation failed: {install_result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("[TinyTeX] Installation timed out")
        return False
    except Exception as e:
        print(f"[TinyTeX] Installation error: {e}")
        return False

def install_natural_earth_data():
    """
    Pre-download Natural Earth data for Cartopy to prevent runtime downloads.
    Downloads shapefiles for coastlines, borders, states, and rivers at multiple resolutions.
    
    This ensures QLC never attempts to download data at runtime.
    """
    # Check if Natural Earth download should be skipped
    if os.environ.get('QLC_SKIP_NATURAL_EARTH', '').lower() in ['1', 'true', 'yes']:
        print("[Natural Earth] Skipping Natural Earth data download (QLC_SKIP_NATURAL_EARTH=1)")
        return True
    
    print("[Natural Earth] Pre-downloading Cartopy Natural Earth shapefiles...")
    print("[Natural Earth] This prevents runtime downloads and ensures offline operation")
    
    # Validate environment - ensure we're installing in the correct location
    import sys
    venv_path = os.environ.get('VIRTUAL_ENV')
    
    print(f"[Natural Earth] Python executable: {sys.executable}")
    if venv_path:
        print(f"[Natural Earth] Virtual environment: {venv_path}")
        print("[Natural Earth] Installing in venv (recommended)")
    else:
        print("[Natural Earth] WARNING: Not running in virtual environment")
        print("[Natural Earth] WARNING: Data will be installed system-wide")
    
    # STEP 1: Ensure Cartopy is installed BEFORE attempting imports
    cartopy_was_installed = False
    try:
        import cartopy
    except ImportError:
        print("[Natural Earth] Cartopy not installed - attempting to install it now...")
        
        # Try to install Cartopy using pip
        try:
            import subprocess
            
            # Uninstall any broken installation first
            try:
                subprocess.run([sys.executable, '-m', 'pip', 'uninstall', '-y', 'cartopy'], 
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            except:
                pass
            
            # Try multiple installation strategies
            # Note: Cartopy 0.25.0+ doesn't have config.py (it's fine, we have fallback)
            install_commands = [
                # Strategy 1: Latest with compatible numpy
                [sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'cartopy>=0.21.0', 'numpy<2.0,>=1.21.0'],
                # Strategy 2: Specific version that might have config.py
                [sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'cartopy==0.22.0', 'numpy<2.0,>=1.21.0'],
                # Strategy 3: Latest cartopy (may not have config.py, but fallback will handle it)
                [sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'cartopy>=0.21.0'],
            ]
            
            success = False
            for i, cmd in enumerate(install_commands):
                print(f"[Natural Earth] Install attempt {i+1}/{len(install_commands)}...")
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
                
                if result.returncode == 0:
                    print(f"[Natural Earth] Cartopy installed successfully")
                    cartopy_was_installed = True
                    success = True
                    break
                else:
                    print(f"[Natural Earth] WARNING: Attempt {i+1} failed")
                    if i < len(install_commands) - 1:
                        # Uninstall before next attempt
                        subprocess.run([sys.executable, '-m', 'pip', 'uninstall', '-y', 'cartopy'],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            
            if not success:
                print(f"[Natural Earth] Failed to install Cartopy!")
                print(f"[Natural Earth] Error: {result.stderr[:500]}")
                print("[Natural Earth] QLC will use basic coastlines only")
                return False
                
        except subprocess.TimeoutExpired:
            print("[Natural Earth] Cartopy installation timed out")
            print("[Natural Earth] QLC will use basic coastlines only")
            return False
        except Exception as e:
            print(f"[Natural Earth] Error during Cartopy installation: {e}")
            print("[Natural Earth] QLC will use basic coastlines only")
            return False
    
    # STEP 2: Ensure venv site-packages is in sys.path (CRITICAL for venv imports)
    import site
    import sys
    
    # Get venv site-packages directory
    venv_site_packages = None
    for path in site.getsitepackages():
        if 'qlc' in path.lower() and 'site-packages' in path:
            venv_site_packages = path
            break
    
    # If not found, construct from sys.executable
    if not venv_site_packages and sys.prefix:
        python_version = f"python{sys.version_info.major}.{sys.version_info.minor}"
        venv_site_packages = os.path.join(sys.prefix, 'lib', python_version, 'site-packages')
    
    # Ensure venv site-packages is at the BEGINNING of sys.path (highest priority)
    if venv_site_packages and os.path.exists(venv_site_packages):
        if venv_site_packages not in sys.path:
            sys.path.insert(0, venv_site_packages)
            print(f"[Natural Earth] Added venv site-packages to sys.path: {venv_site_packages}")
        elif sys.path.index(venv_site_packages) > 0:
            # Move to front
            sys.path.remove(venv_site_packages)
            sys.path.insert(0, venv_site_packages)
            print(f"[Natural Earth] Prioritized venv site-packages in sys.path: {venv_site_packages}")
    
    # STEP 3: Import cartopy modules (always use importlib for reliability)
    try:
        # Use importlib for all submodule imports (more reliable than regular imports)
        import importlib
        
        # Debug: Show where Python will look for imports
        print(f"[Natural Earth] sys.path[0] (highest priority): {sys.path[0]}")
        
        # Try to import cartopy.config (may not exist in Cartopy 0.25+)
        try:
            cartopy_config = importlib.import_module('cartopy.config')
            print(f"[Natural Earth] Loaded cartopy.config from: {cartopy_config.__file__}")
        except (ImportError, ModuleNotFoundError):
            # Cartopy 0.25+ doesn't have config.py - use fallback immediately
            print("[Natural Earth] Note: Cartopy 0.25+ detected (no config.py), using default paths")
            import pathlib
            default_data_dir = pathlib.Path.home() / '.local' / 'share' / 'cartopy'
            
            class CartopyConfig:
                def get(self, key):
                    if key == 'data_dir':
                        return str(default_data_dir)
                    return None
            
            cartopy_config = CartopyConfig()
        
        cfeature = importlib.import_module('cartopy.feature')
        shpreader = importlib.import_module('cartopy.io.shapereader')
        print("[Natural Earth] Cartopy modules loaded successfully")
    except (ImportError, ModuleNotFoundError) as e:
        # Cartopy or its submodules are broken/corrupted - try to reinstall
        print(f"[Natural Earth] WARNING: Cartopy installation issue: {e}")
        print("[Natural Earth] Attempting to repair Cartopy installation...")
        
        try:
            import subprocess
            
            # STEP 1: Uninstall any existing (broken) Cartopy
            print("[Natural Earth] Uninstalling existing Cartopy...")
            try:
                subprocess.check_call([sys.executable, '-m', 'pip', 'uninstall', '-y', 'cartopy'], 
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print("[Natural Earth] Uninstalled existing Cartopy")
            except:
                print("[Natural Earth] No existing Cartopy to uninstall")
            
            # STEP 2: Fresh install of Cartopy with all dependencies (show output to catch errors)
            print("[Natural Earth] Installing Cartopy with all dependencies (this may take a moment)...")
            
            # Try multiple installation strategies
            # Note: Cartopy 0.25.0+ doesn't have config.py (it's fine, we have fallback)
            install_commands = [
                # Strategy 1: Latest with compatible numpy
                [sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'cartopy>=0.21.0', 'numpy<2.0,>=1.21.0'],
                # Strategy 2: Specific version that might have config.py
                [sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'cartopy==0.22.0', 'numpy<2.0,>=1.21.0'],
                # Strategy 3: Latest cartopy (may not have config.py, but fallback will handle it)
                [sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'cartopy>=0.21.0'],
            ]
            
            success = False
            for i, cmd in enumerate(install_commands):
                print(f"[Natural Earth] Attempt {i+1}/{len(install_commands)}: {' '.join(cmd[-2:])}")
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
                
                if result.returncode == 0:
                    # Check if cartopy was installed (config.py is optional in newer versions)
                    cartopy_check = os.path.join(venv_site_packages, 'cartopy', '__init__.py') if venv_site_packages else None
                    if cartopy_check and os.path.exists(cartopy_check):
                        config_check = os.path.join(venv_site_packages, 'cartopy', 'config.py') if venv_site_packages else None
                        if config_check and os.path.exists(config_check):
                            print(f"[Natural Earth] Cartopy installed successfully with config.py!")
                        else:
                            print(f"[Natural Earth] Cartopy installed (newer version without config.py)")
                        success = True
                        break
                    else:
                        print(f"[Natural Earth] WARNING: Installation succeeded but cartopy not found")
                        if i < len(install_commands) - 1:
                            print(f"[Natural Earth] Trying alternative installation method...")
                            # Uninstall before next attempt
                            subprocess.run([sys.executable, '-m', 'pip', 'uninstall', '-y', 'cartopy'],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                else:
                    print(f"[Natural Earth] WARNING: Attempt {i+1} failed: {result.stderr[:200]}")
                    if i < len(install_commands) - 1:
                        print(f"[Natural Earth] Trying alternative installation method...")
            
            if not success:
                print(f"[Natural Earth] All Cartopy installation attempts failed!")
                print(f"[Natural Earth] Last error: {result.stderr[:500]}")
                raise Exception("Failed to install complete Cartopy package")
            
            # CRITICAL: Clear Python's import cache for cartopy modules
            import sys
            modules_to_clear = [key for key in sys.modules.keys() if key.startswith('cartopy')]
            for module in modules_to_clear:
                del sys.modules[module]
            print(f"[Natural Earth] Cleared {len(modules_to_clear)} cartopy modules from cache")
            
            # CRITICAL: Re-prioritize venv site-packages in sys.path after reinstall
            if venv_site_packages and venv_site_packages in sys.path:
                sys.path.remove(venv_site_packages)
                sys.path.insert(0, venv_site_packages)
                print(f"[Natural Earth] Re-prioritized venv site-packages: {venv_site_packages}")
            
            # Verify cartopy installation location
            cartopy_path = os.path.join(venv_site_packages, 'cartopy') if venv_site_packages else None
            if cartopy_path and os.path.exists(cartopy_path):
                config_path = os.path.join(cartopy_path, 'config.py')
                __init___path = os.path.join(cartopy_path, '__init__.py')
                
                print(f"[Natural Earth] Cartopy directory: {cartopy_path}")
                print(f"[Natural Earth]   __init__.py exists: {os.path.exists(__init___path)}")
                print(f"[Natural Earth]   config.py exists: {os.path.exists(config_path)}")
                
                # List what's actually in the directory
                if os.path.exists(cartopy_path):
                    files = sorted([f for f in os.listdir(cartopy_path) if not f.startswith('.')])[:20]
                    print(f"[Natural Earth]   Files/dirs in cartopy/: {', '.join(files[:10])}")
                
                # Note: config.py is optional in Cartopy 0.25.0+ (we have fallback)
                if not os.path.exists(config_path):
                    print(f"[Natural Earth] Cartopy 0.25.0+ detected (no config.py) - using fallback")
                    # Don't raise exception, just skip to fallback
                    cartopy_config = None  # Signal to use fallback
            else:
                print(f"[Natural Earth] Cartopy directory NOT found!")
                print(f"[Natural Earth] Expected: {cartopy_path}")
                raise Exception("Cartopy directory not found after installation")
            
            # Try imports again after reinstall and cache clear
            importlib = __import__('importlib')
            
            # Try importing with full path verification
            print(f"[Natural Earth] Attempting imports with sys.path[0] = {sys.path[0]}")
            
            # Check if we should use fallback (set earlier if no config.py)
            if cartopy_config is None:
                # Skip trying to import config.py, go directly to fallback
                print("[Natural Earth] Skipping cartopy.config import (using fallback)")
                raise Exception("Using fallback for Cartopy 0.25.0+")
            
            cartopy_config = importlib.import_module('cartopy.config')
            print(f"[Natural Earth] cartopy.config loaded from: {cartopy_config.__file__}")
            
            cfeature = importlib.import_module('cartopy.feature')
            shpreader = importlib.import_module('cartopy.io.shapereader')
            print("[Natural Earth] Cartopy modules loaded successfully")
            
        except Exception as repair_error:
            # FALLBACK: Try to work without cartopy.config by using default paths
            # (This is normal for Cartopy 0.25.0+ which doesn't have config.py)
            print("[Natural Earth] Note: Using fallback for Cartopy 0.25.0+ (no config.py module)")
            print("[Natural Earth] Configuring default data directory...")
            try:
                # Import base cartopy and feature modules
                cartopy = importlib.import_module('cartopy')
                cfeature = importlib.import_module('cartopy.feature')
                shpreader = importlib.import_module('cartopy.io.shapereader')
                
                # Use default data directory (Cartopy's standard location)
                import pathlib
                default_data_dir = pathlib.Path.home() / '.local' / 'share' / 'cartopy'
                print(f"[Natural Earth] Using default data directory: {default_data_dir}")
                
                # Create a mock config object
                class CartopyConfig:
                    def get(self, key):
                        if key == 'data_dir':
                            return str(default_data_dir)
                        return None
                
                cartopy_config = CartopyConfig()
                print("[Natural Earth] Fallback successful - proceeding without cartopy.config")
                
            except Exception as fallback_error:
                print(f"[Natural Earth] Fallback also failed: {fallback_error}")
                print("[Natural Earth] QLC will use basic coastlines only")
                print("[Natural Earth] Try manual reinstall: pip install --force-reinstall cartopy")
                return False
    
    # STEP 3: Now proceed with Natural Earth data download
    try:
        # Show data directory
        data_dir = cartopy_config.get('data_dir')
        if data_dir:
            print(f"[Natural Earth] Data directory: {data_dir}")
            # Create directory if it doesn't exist
            os.makedirs(data_dir, exist_ok=True)
        
        # IMPORTANT: Fix SSL certificate issues for Natural Earth downloads
        # This is needed for macOS systems where certificates may not be properly installed
        import ssl
        import urllib.request
        
        # Check if we need to fix SSL certificates
        try:
            # Create an SSL context that can handle certificate issues
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            
            # Install a custom HTTPS handler to bypass certificate verification
            # Note: This is safe for Natural Earth downloads from trusted sources
            https_handler = urllib.request.HTTPSHandler(context=ssl_context)
            opener = urllib.request.build_opener(https_handler)
            urllib.request.install_opener(opener)
            
            print("[Natural Earth] SSL certificate handling configured for downloads")
        except Exception as ssl_error:
            print(f"[Natural Earth] Note: Could not configure SSL workaround: {ssl_error}")
            print("[Natural Earth] Some downloads may fail due to certificate issues")
        print()
        
        # List of features and resolutions to pre-download
        # These match what QLC uses in map_plots.py
        # IMPORTANT: Feature names must match what Cartopy's cfeature objects request
        features_to_download = [
            ('physical', 'coastline', ['110m', '50m']),  # Coastlines at two resolutions
            ('cultural', 'admin_0_boundary_lines_land', ['110m', '50m']),  # Country borders (cfeature.BORDERS)
            ('cultural', 'admin_1_states_provinces_lakes', ['110m', '50m']),  # State/province borders (cfeature.STATES)
            ('physical', 'rivers_lake_centerlines', ['110m', '50m']),  # Rivers (cfeature.RIVERS)
        ]
        
        downloaded = []
        skipped = []
        
        for category, name, resolutions in features_to_download:
            for resolution in resolutions:
                try:
                    feature_name = f"{category}/{name}"
                    print(f"[Natural Earth] Downloading {resolution} {feature_name}...")
                    
                    # Trigger download by accessing the shapefile path
                    # This will download if not cached
                    shp_path = shpreader.natural_earth(resolution=resolution, 
                                                      category=category, 
                                                      name=name)
                    
                    if shp_path and os.path.exists(shp_path):
                        downloaded.append(f"{resolution}_{name}")
                        print(f"[Natural Earth]   {resolution} {name}")
                    else:
                        skipped.append(f"{resolution}_{name}")
                        print(f"[Natural Earth]   WARNING: {resolution} {name} (file not found after download)")
                        
                except Exception as e:
                    skipped.append(f"{resolution}_{name}")
                    print(f"[Natural Earth]   {resolution} {name}: {e}")
        
        if downloaded:
            print(f"\n[Natural Earth] Successfully downloaded {len(downloaded)} feature sets")
            if data_dir:
                print(f"[Natural Earth] Data installed in: {data_dir}")
            print("[Natural Earth] Cartopy will use pre-downloaded data (no runtime downloads)")
            return True
        else:
            print("\n[Natural Earth] Warning: No features were downloaded successfully")
            print("[Natural Earth] QLC will use basic coastlines only")
            return False
            
    except Exception as e:
        print(f"[Natural Earth] Error downloading Natural Earth data: {e}")
        print("[Natural Earth] QLC will attempt to use cached data or basic coastlines")
        return False

def install_pyferret(venv_path: Path):
    """
    Cross-platform PyFerret installation with intelligent detection.
    Priority: Module system -> System PATH -> venv installation
    """
    print(f"[PyFerret] Setting up cross-platform PyFerret for QLC venv: {venv_path}")
    
    # Check if PyFerret is already installed in the venv
    venv_bin = venv_path / "bin"
    venv_pyferret = venv_bin / "pyferret"
    if venv_pyferret.exists():
        print("[PyFerret] PyFerret already installed in QLC venv")
        return True
    
    # Step 1: Check if module system is available and has ferret
    print("[PyFerret] Checking for module system (ATOS/HPC)...")
    module_check = subprocess.run(['which', 'module'], capture_output=True, text=True)
    if module_check.returncode == 0:
        print("[PyFerret] Module system detected, checking for ferret...")
        # Use bash to execute module command since it's a shell function
        module_avail = subprocess.run(['bash', '-c', 'module avail ferret'], capture_output=True, text=True)
        if module_avail.returncode == 0 and 'ferret' in module_avail.stdout:
            print("[PyFerret] ferret module available - will be loaded by scripts")
            print("[PyFerret] No venv installation needed (using module system)")
            return True
        else:
            print("[PyFerret] ferret module not available")
    
    # Step 2: Check system PATH for existing PyFerret installation
    print("[PyFerret] Checking system PATH for PyFerret...")
    
    # Define search paths for PyFerret binaries
    pyferret_search_paths = [
        "/usr/bin",
        "/usr/local/bin", 
        "/opt/bin",
        "/opt/local/bin",
        "/opt/homebrew/bin",
        "/opt/PyFerret/bin",
        str(Path.home() / ".local" / "bin")
    ]
    
    pyferret_path = None
    
    # First try 'which' command
    which_result = subprocess.run(['which', 'pyferret'], capture_output=True, text=True)
    if which_result.returncode == 0:
        pyferret_path = which_result.stdout.strip()
    else:
        # If 'which' fails, search in specific paths
        for search_path in pyferret_search_paths:
            cmd_path = Path(search_path) / "pyferret"
            if cmd_path.exists():
                pyferret_path = str(cmd_path)
                break
    
    if pyferret_path:
        print(f"[PyFerret] Found system pyferret at: {pyferret_path}")
        
        # Create symlink in venv for system PyFerret
        venv_bin.mkdir(parents=True, exist_ok=True)
        cmd_path = venv_bin / "pyferret"
        if not cmd_path.exists():
            cmd_path.symlink_to(pyferret_path)
            print(f"[PyFerret] Linked system pyferret to venv")
        print("[PyFerret] Using system PyFerret installation")
        return True
    
    # Step 3: Install PyFerret in venv as fallback
    print("[PyFerret] No system PyFerret found, installing PyFerret in venv...")
    try:
        # Try installing via pip first
        pip_result = subprocess.run([
            sys.executable, '-m', 'pip', 'install', 'pyferret'
        ], capture_output=True, text=True, timeout=120)
        
        if pip_result.returncode == 0:
            print("[PyFerret] PyFerret installed via pip")
            return True
        
        # Try conda-forge as fallback
        print("[PyFerret] pip installation failed, trying conda-forge...")
        conda_result = subprocess.run([
            sys.executable, '-m', 'pip', 'install', '--extra-index-url', 'https://pypi.anaconda.org/conda-forge/simple', 'pyferret'
        ], capture_output=True, text=True, timeout=120)
        
        if conda_result.returncode == 0:
            print("[PyFerret] PyFerret installed via conda-forge")
            return True
        
        print(f"[PyFerret] Installation failed: {pip_result.stderr}")
        return False
        
    except subprocess.TimeoutExpired:
        print("[PyFerret] Installation timed out")
        return False
    except Exception as e:
        print(f"[PyFerret] Installation error: {e}")
        return False

def copy_or_link(src, dst, symlink=False, relative=False):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    if symlink:
        link_target = os.path.relpath(src.resolve(), dst.parent) if relative else src.resolve()
        dst.symlink_to(link_target, target_is_directory=src.is_dir())
    else:
        shutil.copy(src, dst)

def copytree_with_symlinks(src: Path, dst: Path):
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)

    for item in src.iterdir():
        s = src / item.name
        d = dst / item.name
        if s.is_symlink():
            target = os.readlink(s)
            print(f"[LINK] Preserving symlink {d} → {target}")
            d.symlink_to(target)
        elif s.is_dir():
            copytree_with_symlinks(s, d)
        else:
            shutil.copy2(s, d)

def safe_move_and_link(src: Path, dst: Path, relative: bool = False, backup: bool = True):
    """
    Safely create a symlink from dst to src.
    If dst exists, it's backed up (if backup=True) before the new link is created.
    If dst is already a symlink pointing to src, do nothing.
    """
    if dst.is_symlink():
        try:
            if dst.resolve() == src.resolve():
                print(f"[SKIP] Link {dst} already points to {src}")
                return
            else:
                print(f"[INFO] Unlinking existing symlink {dst} -> {dst.readlink()}")
                dst.unlink()
        except FileNotFoundError:
            # This handles broken symlinks
            print(f"[INFO] Removing broken symlink {dst}")
            dst.unlink()

    elif dst.exists():
        if backup:
            backup_dst = dst.with_name(f"{dst.name}_backup_link")
            print(f"[BACKUP] Moving existing path {dst} -> {backup_dst}")
            shutil.move(str(dst), str(backup_dst))
        else:
            print(f"[INFO] Removing existing path {dst}")
            if dst.is_dir():
                shutil.rmtree(dst)
            else:
                dst.unlink()

    # Create the new link
    copy_or_link(src, dst, symlink=True, relative=relative)

def update_qlc_version(config_path: Path, version: str):
    if not config_path.exists():
        raise FileNotFoundError(f"[ERROR] Config file not found: {config_path}")

    lines = config_path.read_text(encoding="utf-8").splitlines()
    new_lines = []
    updated = False

    for line in lines:
        if line.strip().startswith("QLC_VERSION="):
            new_lines.append(f'QLC_VERSION="{version}"')
            updated = True
        else:
            new_lines.append(line)

    if not updated:
        print(f"[WARN] QLC_VERSION=... not found in {config_path}")
    else:
        config_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        print(f"[UPDATED] QLC_VERSION set to {version} in {config_path}")

def setup_data_directories(root: Path, mode: str):
    """
    Creates the two-stage symlink structure for data-heavy directories WITHIN a mode's root.
    - Creates <root>/data
    - Populates it with either real directories (test/dev) or symlinks (cams)
    - Creates top-level symlinks from <root>/* -> <root>/data/*
    
    Data directory strategy:
    - CAMS mode: Shared data directories across all versions (e.g., $SCRATCH/qlc_pypi/Results)
      Allows all production versions to access the same operational data
    - Test/Dev modes: Isolated data directories per version (e.g., $PERM/qlc_pypi/v1.0.1b0/test/data/Results)
      Provides sandbox environments for testing and development
    """
    print("[SETUP] Configuring data directories...")
    data_dir = root / "data"
    data_dir.mkdir(exist_ok=True)

    # Define the mapping for CAMS mode
    cams_env_map = {
        "Results": "SCRATCH",
        "Analysis": "HPCPERM",
        "Plots": "PERM",
        "Presentations": "PERM",
        "log": "PERM",
        "run": "PERM",
        "output": "PERM"
    }
    
    data_heavy_dirs = ["Results", "Analysis", "Plots", "Presentations"]

    for d in data_heavy_dirs:
        data_subdir = data_dir / d
        
        # Robustly remove existing path before creating a new one
        if data_subdir.is_symlink():
            data_subdir.unlink()
        elif data_subdir.is_dir():
            shutil.rmtree(data_subdir)
        elif data_subdir.exists():
            data_subdir.unlink()

        if mode == "cams":
            env_var = cams_env_map.get(d)
            target_base_path = os.environ.get(env_var)
            
            if target_base_path:
                # Link to qlc_pypi instead of qlc for simplified data structure
                target_path = Path(target_base_path) / "qlc_pypi" / d
                target_path.mkdir(parents=True, exist_ok=True)
                data_subdir.symlink_to(target_path, target_is_directory=True)
                print(f"[LINK] {data_subdir} -> {target_path}")
            else:
                print(f"[WARN] Environment variable ${env_var} not set for {d}. Creating local directory.")
                data_subdir.mkdir(exist_ok=True)
        else: # test mode
            data_subdir.mkdir(exist_ok=True)
            print(f"[MKDIR] {data_subdir}")

        # Create the top-level symlink, e.g., <root>/Results -> <root>/data/Results
        top_level_link = root / d
        if top_level_link.is_symlink() or top_level_link.exists():
            top_level_link.unlink()
        
        # --- Create a relative symlink ---
        # The target is data_subdir, and the link is created at top_level_link.
        # We need the path of the target relative to the link's parent directory.
        relative_target = os.path.relpath(data_subdir, top_level_link.parent)
        top_level_link.symlink_to(relative_target, target_is_directory=True)
        print(f"[LINK] {top_level_link} -> {relative_target}")

    # Handle remaining directories (log, run, output) for both modes
    remaining_dirs = ["log", "run", "output"]
    for d in remaining_dirs:
        data_subdir = data_dir / d
        
        # Robustly remove existing path before creating a new one
        if data_subdir.is_symlink():
            data_subdir.unlink()
        elif data_subdir.is_dir():
            shutil.rmtree(data_subdir)
        elif data_subdir.exists():
            data_subdir.unlink()

        # For both cams and test modes, create local directories
        data_subdir.mkdir(exist_ok=True)
        print(f"[MKDIR] {data_subdir}")

        # Create the top-level symlink, e.g., <root>/log -> <root>/data/log
        top_level_link = root / d
        if top_level_link.is_symlink() or top_level_link.exists():
            top_level_link.unlink()
        
        # Create relative symlink
        relative_target = os.path.relpath(data_subdir, top_level_link.parent)
        top_level_link.symlink_to(relative_target, target_is_directory=True)
        print(f"[LINK] {top_level_link} -> {relative_target}")

def link_model_experiments(mod_data_src_root: Path, results_dst_root: Path, debug: bool = False):
    """
    Links model experiment files from mod_data_src_root to results_dst_root.
    Creates absolute symlinks for the model data files.
    """
    if not mod_data_src_root.is_dir():
        print(f"[WARN] Source directory not found for model experiments: {mod_data_src_root}")
        return

    for exp_dir in mod_data_src_root.iterdir():
        if exp_dir.is_dir():
            # This is an experiment dir, e.g., /path/to/test/mod/b2ro
            results_exp_dir = results_dst_root / exp_dir.name
            results_exp_dir.mkdir(exist_ok=True)
            
            # Find all .grb files, searching recursively through year folders
            for year_dir in exp_dir.iterdir():
                if year_dir.is_dir():
                    for src_file in year_dir.glob('*.grb'):
                        dst_file = results_exp_dir / src_file.name
                        dst_file.parent.mkdir(parents=True, exist_ok=True)
                        # Use absolute paths for these links as they point from the data dir to the mod dir,
                        # which can be far apart.
                        copy_or_link(src_file, dst_file, symlink=True, relative=False)
                        if debug:
                            print(f"[LINK] {dst_file} -> {src_file}")

def setup(mode: str, version: str, debug: bool = False, config_file: str = None):
    # Set umask to ensure files are readable for world (0022 = rwxr-xr-x)
    import os
    os.umask(0o022)
    print("[SETUP] Set umask to 0022 for world-readable files")

    # Define source root (this file is in qlc/cli/, so parent.parent gives us the qlc package root)
    qlc_root = Path(__file__).resolve().parent.parent
    config_src = qlc_root / "config"
    example_src = qlc_root / "examples"
    sh_src = qlc_root / "bin"
    doc_src = qlc_root / "doc"

    from qlc.py.version import QLC_VERSION as version

    # --- QLC paths with isolated PyPI and Dev installations ---
    # Installation base: $PERM (if set) or $HOME (fallback)
    # Note: $SCRATCH and $HPCPERM are only used for data directory mapping, not installation
    user_home = Path.home()
    
    # Check for $PERM (all modes) - this is where QLC will be installed
    if os.environ.get('PERM'):
        install_base = Path(os.environ['PERM'])
        print(f"[INFO] Using $PERM as installation base: {install_base}")
        print(f"[INFO] Stable link will be created in $HOME: {user_home}")
    else:
        install_base = Path.home()
        print(f"[INFO] Using $HOME as installation base: {install_base}")
    
    # Determine installation directory based on mode
    # Runtime: qlc_pypi (underscore) for production, qlc_dev (underscore) for development
    # Source: qlc-pypi (hyphen) for public, qlc-dev (hyphen) for private
    if mode == 'dev':
        install_root_name = "qlc_dev"
        stable_link_name = "qlc-dev-run"
        print(f"[INFO] Development mode: using {install_root_name} runtime root")
    else:  # test, cams, interactive
        install_root_name = "qlc_pypi"
        stable_link_name = "qlc"
        print(f"[INFO] Production mode: using {install_root_name} runtime root")
    
    # The versioned installation directory
    # Examples: $PERM/qlc_pypi/v1.0.1b0 (HPC) or $HOME/qlc_pypi/v1.0.1b0 (local)
    versioned_install_dir = install_base / install_root_name / f"v{version}"
    
    # The mode-specific root
    # Examples: $PERM/qlc_pypi/v1.0.1b0/test (HPC) or $HOME/qlc_pypi/v1.0.1b0/test (local)
    root = versioned_install_dir / mode

    # --- Backup Logic: Back up the entire versioned directory if the specific mode being installed already exists ---
    if root.exists():
        backup_name = f"{versioned_install_dir.name}_backup"
        backup = versioned_install_dir.with_name(backup_name)
        count = 1
        while backup.exists():
            backup = versioned_install_dir.with_name(f"{backup_name}{count}")
            count += 1
        print(f"[BACKUP] Moving existing install root {versioned_install_dir} → {backup}")
        shutil.move(str(versioned_install_dir), str(backup))

    print(f"[SETUP] Mode: {mode}, Version: {version}")
    print(f"[PATHS] QLC Install Root: {root}")
    
    # Create essential directories for the mode
    root.mkdir(parents=True, exist_ok=True)

    # Prepare paths inside the versioned, mode-specific directory
    config_dst = root / "config"
    example_dst = root / "examples"
    bin_dst = root / "bin"
    mod_dst = root / "mod"
    obs_dst = root / "obs"
    doc_dst = root / "doc"
    plug_dst = root / "plugin"
    
    # Create non-data directories inside the mode-specific root
    # NOTE: 'run' and 'output' are now handled by setup_data_directories
    for path in [config_dst, example_dst, bin_dst, mod_dst, obs_dst, doc_dst, plug_dst]:
        path.mkdir(parents=True, exist_ok=True)

    # --- Setup the new data directory structure INSIDE the mode root ---
    setup_data_directories(root, mode)

    # Copy config files
    shutil.copytree(config_src, config_dst, dirs_exist_ok=True)
    print(f"[COPY] {config_src} -> {config_dst}")

    # Link example directories instead of copying
    if example_src.exists():
        for item in example_src.iterdir():
            if item.is_dir(): # Only link directories
                dst_link = example_dst / item.name
                if dst_link.exists() or dst_link.is_symlink():
                    if dst_link.is_dir() and not dst_link.is_symlink():
                        shutil.rmtree(dst_link)
                    else:
                        dst_link.unlink()
                dst_link.symlink_to(item.resolve(), target_is_directory=True)
                print(f"[LINK] {dst_link} -> {item}")

    # Link all documentation files
    shutil.copytree(doc_src, doc_dst, dirs_exist_ok=True)
    for doc_file in doc_src.glob("*"):
        dst = doc_dst / doc_file.name
        copy_or_link(doc_file, dst, symlink=True, relative=False)
        print(f"[LINK] {dst} -> {doc_file.resolve()}")

    # Link all *.sh files to bin_dst (helpers included)
    for sh_file in sh_src.glob("*.sh"):
        dst = bin_dst / sh_file.name
        copy_or_link(sh_file, dst, symlink=True, relative=False)
        print(f"[LINK] {dst} -> {sh_file.resolve()}")

    # Copy the TeX template directory to bin_dst
    tex_template_src = sh_src / "tex_template"
    tex_template_dst = bin_dst / "tex_template"
    if tex_template_src.is_dir():
        if tex_template_dst.exists():
            shutil.rmtree(tex_template_dst)
        shutil.copytree(tex_template_src, tex_template_dst)
        print(f"[COPY] {tex_template_src} -> {tex_template_dst}")

    # Link the tools directory to bin_dst (consistent with shell scripts)
    tools_src = sh_src / "tools"
    tools_dst = bin_dst / "tools"
    if tools_src.is_dir():
        if tools_dst.exists() or tools_dst.is_symlink():
            if tools_dst.is_dir() and not tools_dst.is_symlink():
                shutil.rmtree(tools_dst)
            else:
                tools_dst.unlink()
        tools_dst.symlink_to(tools_src.resolve(), target_is_directory=True)
        print(f"[LINK] {tools_dst} -> {tools_src.resolve()}")

    # Create shell tool links (now handled by entry_points in setup.py)
    pass

    # In test mode: link obs and mod to examples
    if mode == "test":
        # Link sample observation data as requested
        # 1. $HOME/qlc/obs/data/ver0d/ebas_daily/v_20240216 -> $HOME/qlc/examples/cams_case_1/obs/ebas_daily/v_20240216
        # 2. $HOME/qlc/obs/data/ver0d/ebas_daily/latest -> v_20240216 (relative)
        
        obs_data_source = root / "examples/cams_case_1/obs/ebas_daily/v_20240216"
        obs_data_dest_dir = root / "obs/data/ver0d/ebas_daily"
        obs_data_dest_dir.mkdir(parents=True, exist_ok=True)
        
        # Create the v_20240216 symlink with an absolute path
        link1_target = obs_data_dest_dir / "v_20240216"
        copy_or_link(obs_data_source, link1_target, symlink=True, relative=False)
        print(f"[LINK] {link1_target} -> {obs_data_source.resolve()}")

        # Create the latest symlink, relative to its location
        link2_target = obs_data_dest_dir / "latest"
        if link2_target.exists() or link2_target.is_symlink():
            link2_target.unlink()
        # This one MUST be relative by its nature
        link2_target.symlink_to("v_20240216", target_is_directory=True)
        print(f"[LINK] {link2_target} -> v_20240216")

        # Copy all station files for the test case
        station_files_source_dir = root / "examples/cams_case_1/obs"
        station_files_dest_dir = root / "obs/data"
        if station_files_source_dir.exists():
            # Copy all CSV station files
            for station_file in station_files_source_dir.glob("*.csv"):
                dest_file = station_files_dest_dir / station_file.name
                copy_or_link(station_file, dest_file, symlink=False)
                print(f"[COPY] {dest_file}")


        # Link sample model data, ensuring absolute paths
        mod_data_src_root = root / "examples" / "cams_case_1" / "mod"
        mod_data_dst_root = root / "mod"
        if mod_data_src_root.is_dir():
            for model_dir in mod_data_src_root.iterdir():
                if model_dir.is_dir():
                    dst_link = mod_data_dst_root / model_dir.name
                    # Use copy_or_link to create an absolute symlink
                    copy_or_link(model_dir, dst_link, symlink=True, relative=False)
                    print(f"[LINK] {dst_link} -> {model_dir.resolve()}")

        # Link model experiment files to the 'Results' directory (relative)
        results_dst_root = root / "Results"
        results_dst_root.mkdir(exist_ok=True)
        print(f"[SETUP] Linking model experiments to {results_dst_root}")

        if mod_data_dst_root.is_dir():
            for exp_dir in mod_data_dst_root.iterdir():
                if exp_dir.is_dir():
                    # This is an experiment dir, e.g., /path/to/test/mod/b2ro
                    results_exp_dir = results_dst_root / exp_dir.name
                    results_exp_dir.mkdir(exist_ok=True)
                    
                    # Find all .grb and .flag files, searching recursively through year folders
                    for year_dir in exp_dir.iterdir():
                        if year_dir.is_dir():
                            # Copy both .grb and .flag files
                            for pattern in ['*.grb', '*.flag']:
                                for src_file in year_dir.glob(pattern):
                                    dst_file = results_exp_dir / src_file.name
                                    dst_file.parent.mkdir(parents=True, exist_ok=True)
                                    # Use absolute paths for these links as they point from the data dir to the mod dir,
                                    # which can be far apart.
                                    copy_or_link(src_file, dst_file, symlink=True, relative=False)
                                    if debug:
                                        print(f"[LINK] {dst_file} -> {src_file}")

    # In CAMS mode: link to operational directories
    if mode == "cams":
        # Link obs data directory
        cams_obs_src = Path("/ec/vol/cams/qlc/obs")
        if obs_dst.is_symlink() or obs_dst.is_symlink():
            obs_dst.unlink()
        elif obs_dst.is_dir():
            shutil.rmtree(obs_dst)
        obs_dst.symlink_to(cams_obs_src, target_is_directory=True)
        print(f"[LINK] {obs_dst} -> {cams_obs_src}")
        
        # Link mod directory to this mode's internal Results directory
        results_link = root / "Results"
        if mod_dst.is_symlink() or mod_dst.is_symlink():
            mod_dst.unlink()
        elif mod_dst.is_dir():
            shutil.rmtree(mod_dst)
        mod_dst.symlink_to(results_link, target_is_directory=True)
        print(f"[LINK] {mod_dst} -> {results_link}")

    # The config is now static, just need to update the version
    generic_config_path = config_dst / "qlc.conf"
    update_qlc_version(generic_config_path, version)

    # --- Setup master symlinks for isolated PyPI/Dev installations ---
    
    # Create the new two-level symlink structure:
    # 1. qlc_pypi/current -> v0.4.1 (or qlc_dev/current -> v0.4.1)
    # 2. ~/qlc -> qlc_pypi/current/test (or ~/qlc-dev-run -> qlc_dev/current/dev)
    
    install_root = versioned_install_dir.parent  # e.g., ~/qlc_pypi or ~/qlc_dev
    current_link = install_root / "current"
    stable_link = user_home / stable_link_name  # qlc or qlc-dev-run
    
    # Create/update current -> v0.4.1 (inside qlc_pypi or qlc_dev)
    if current_link.is_symlink():
        current_link.unlink()
    elif current_link.exists():
        shutil.rmtree(current_link)
    
    # Create relative symlink to version directory
    current_link.symlink_to(versioned_install_dir.name, target_is_directory=True)
    print(f"[LINK] {current_link} -> {versioned_install_dir.name}")
    
    # Create/update ~/qlc or ~/qlc-dev-run -> qlc_pypi/current/test (or dev)
    if stable_link.is_symlink():
        stable_link.unlink()
    elif stable_link.exists():
        if stable_link.is_dir():
            print(f"[WARN] {stable_link} exists as directory, not overwriting")
        else:
            stable_link.unlink()
    
    # Create symlink from home to runtime directory
    # If install_base differs from user_home (e.g., using $PERM), create absolute symlink
    if install_base != user_home:
        stable_link.symlink_to(root.resolve(), target_is_directory=True)
        print(f"[LINK] {stable_link} -> {root.resolve()}")
    else:
        # Create relative symlink from home to runtime directory
        relative_target = os.path.relpath(root, user_home)
        stable_link.symlink_to(relative_target, target_is_directory=True)
        print(f"[LINK] {stable_link} -> {relative_target}")


    # Write install info
    info = {
        "version": version,
        "mode": mode,
        "config": "qlc.conf"
    }

    (root / "VERSION.json").write_text(json.dumps(info, indent=2))
    print(f"[WRITE] VERSION.json at {root}")

    # Final version update on the stable link path
    update_qlc_version(stable_link / "config" / "qlc.conf", version)

    # Install TinyTeX for PDF generation
    print("\n[TinyTeX] Setting up LaTeX for PDF generation...")
    venv_path = get_bin_path().parent  # Get the venv directory
    if install_tinytex(venv_path):
        print("[TinyTeX] TinyTeX setup completed successfully")
    else:
        print("[TinyTeX] TinyTeX setup skipped - manual installation required")
        print("[TinyTeX] QLC will use system LaTeX or weasyprint fallback")

    # Install PyFerret for plotting
    print("\n[PyFerret] Setting up PyFerret for plotting...")
    if install_pyferret(venv_path):
        print("[PyFerret] PyFerret setup completed successfully")
    else:
        print("[PyFerret] PyFerret setup skipped - manual installation required")
        print("[PyFerret] QLC will use system PyFerret or module system")

    # CRITICAL: Pre-download Natural Earth data for Cartopy during installation
    # This prevents ANY runtime downloads - all map data must be pre-installed
    print("\n[Natural Earth] Pre-downloading map data for Cartopy...")
    print("[Natural Earth] IMPORTANT: All data is downloaded NOW during installation")
    print("[Natural Earth] NO runtime downloads will ever occur - this is a production requirement")
    natural_earth_installed = install_natural_earth_data()
    if natural_earth_installed:
        print("[Natural Earth] Natural Earth data setup completed successfully")
        print("[Natural Earth] All map data is pre-installed and ready for offline use")
    else:
        print("[Natural Earth] Natural Earth data setup incomplete - QLC will use basic coastlines")
        print("[Natural Earth] To retry download during installation setup, run:")
        print("[Natural Earth]   python -c 'from qlc.cli.qlc_install import install_natural_earth_data; install_natural_earth_data()'")

    print("\n[INFO] QLC installation complete.")
    print("[INFO] The following commands are now available:")
    print("  qlc, qlc-py, qlc-python, sqlc, qlc-install")
    print("  qlc-extract-stations, qlc-install-extras, qlc-install-tools, qlc-fix-dependencies")
    print("\n[INFO] QLC is ready to use! Try: qlc --help")
    print("\n[VENV USAGE]")
    print("To use QLC commands, activate the virtual environment:")
    print("  source ~/venv/qlc-dev/bin/activate    # For development")
    print("  source ~/venv/qlc-0.4.3/bin/activate  # For specific version")
    print("\n[QUICK START EXAMPLES]")
    print("To run qlc using example data when activated:")
    print("  qlc-install --mode test")
    print("  cd ~/qlc/run")
    print("  qlc --help")
    print("  qlc b2ro b2rn 2018-12-01 2018-12-21 test")
    print("\nTo run qlc using mars retrieval:")
    print("  qlc-install --mode cams")
    print("  cd ~/qlc/run")
    print("  qlc --help")
    print("\nRun qlc-py workflow:")
    print("  qlc b2ro b2rn 2018-12-01 2018-12-21 qpy")
    print("\nRun evaltools workflow on top of qpy output:")
    print("  qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools")
    print("\nRun complex collocation and evaluation workflow:")
    print("  qlc exp1 exp2 exp3 start-yyyy-mm-dd end-yyyy-mm-dd eac5")
    print("\nTo deactivate when done:")
    print("  deactivate")
    print("\n[TOOLS CHECK]")
    print("Checking required tools...")
    
    # Import and run tool checking
    try:
        from qlc.cli.qlc_install_tools import check_all_tools, get_missing_tools_commands, check_module_system
        
        tools = check_all_tools()
        modules = check_module_system()
        
        # Show tool status
        print("\n[Core Tools Status]")
        core_tools = ["cdo", "ncdump", "ncgen", "xelatex"]
        all_core_available = True
        for tool in core_tools:
            if tools[tool]["available"]:
                version = f" ({tools[tool]['version']})" if tools[tool]['version'] else ""
                source = f" via {tools[tool]['source']}" if tools[tool]['source'] else ""
                print(f"  {tool}: Available{version}{source}")
            else:
                print(f"  {tool}: Missing")
                all_core_available = False
        
        print("\n[Plotting Tools Status]")
        plotting_tools = ["pyferret", "evaltools"]
        all_plotting_available = True
        for tool in plotting_tools:
            if tools[tool]["available"]:
                version = f" ({tools[tool]['version']})" if tools[tool]['version'] else ""
                source = f" via {tools[tool]['source']}" if tools[tool]['source'] else ""
                print(f"  {tool}: Available{version}{source}")
            else:
                print(f"  {tool}: Missing")
                all_plotting_available = False
        
        # Module system info
        if modules["module_system"]:
            print(f"\n[Module System] Available")
            available_modules = []
            for module in ["python3", "texlive", "ferret", "cdo", "netcdf"]:
                if modules[module]:
                    available_modules.append(module)
            if available_modules:
                print(f"  Available modules: {', '.join(available_modules)}")
        else:
            print(f"\n[Module System] Not available (using system packages)")
        
        # Show next steps
        missing_commands = get_missing_tools_commands(tools)
        if missing_commands:
            print(f"\n[Next Steps]")
            print("To install missing tools, run:")
            for cmd in missing_commands:
                print(f"  {cmd}")
            
            # Check if evaltools is missing
            if not tools["evaltools"]["available"]:
                print(f"\nTo install evaltools only (with NumPy 2.x compatibility):")
                print(f"  qlc-install-tools --install-evaltools")
            
            print(f"\nOr install everything at once:")
            print(f"  qlc-install-tools --install-all")
            print(f"\nOr use the [all] option for complete installation:")
            print(f"  pip install rc-qlc[all]")
            print(f"\nFor testing or reinstallation, use --force:")
            print(f"  qlc-install-tools --install-all --force")
            print(f"\nTo check tool availability:")
            print(f"  qlc-install-tools --check")
        else:
            print(f"\n[Status] All tools are available! QLC is ready to use.")
            
    except ImportError:
        print("  Tool checking not available (install_tools module not found)")
        print("  Run 'qlc-install-tools --check' to check tool availability")
    
    # Final reminder about Natural Earth data if not installed
    if not natural_earth_installed:
        print("\n" + "=" * 80)
        print("[IMPORTANT] Natural Earth Data Not Installed")
        print("=" * 80)
        print("Map features (borders, states, rivers) are not available.")
        print("QLC will use basic coastlines only for maps.")
        print()
        print("To enable full map features, run:")
        print("  python -c 'from qlc.cli.qlc_install import install_natural_earth_data; install_natural_earth_data()'")
        print("=" * 80)
    
    print("\n[NOTE] Commands are only available when the venv is activated!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install QLC runtime structure")
    parser.add_argument("--mode", type=str, choices=["test", "cams", "dev"], help="Installation mode: test, cams, or dev")
    parser.add_argument("--cams", action="store_true", help="Install in CAMS mode (deprecated, use --mode cams)")
    parser.add_argument("--test", action="store_true", help="Install in TEST mode (deprecated, use --mode test)")
    parser.add_argument("--dev", action="store_true", help="Install in DEVeloper mode (deprecated, use --mode dev)")
    parser.add_argument("--interactive", type=str, help="Install using custom config path")
    parser.add_argument("--version", type=str, help="Override QLC version")
    parser.add_argument("--tools", type=str, help="Auto-install tools: essential (recommended), evaltools, pyferret, xelatex, netcdf, cartopy, or all")

    args = parser.parse_args()
    
    # Determine mode (support both old flags and new --mode argument)
    mode = None
    if args.mode:
        mode = args.mode
    elif args.cams:
        mode = "cams"
    elif args.test:
        mode = "test"
    elif args.dev:
        mode = "dev"
    elif args.interactive:
        mode = "interactive"
    
    if mode:
        setup(mode, version=args.version, config_file=args.interactive if mode == "interactive" else None)
        
        # Auto-install tools if requested
        if args.tools:
            if args.tools == "essential":
                print("\n[TOOLS] Installing essential tools...")
                print("[TOOLS] Essential includes: cdo, ncdump, xelatex, evaltools, pyferret, cartopy")
                print("[TOOLS] Preferring module load for: cdo, ncdump, xelatex, pyferret")
                print()
                
                print("[TOOLS] Installing evaltools with NumPy 2.x compatibility...")
                print("[TOOLS] Running: qlc-install-tools --install-evaltools")
                try:
                    import subprocess
                    result = subprocess.run(
                        [sys.executable, '-m', 'qlc.cli.qlc_install_tools', '--install-evaltools'],
                        capture_output=True, text=True, timeout=300
                    )
                    if result.returncode == 0:
                        print("[TOOLS] Evaltools installed successfully")
                    else:
                        print(f"[TOOLS] Evaltools installation had issues: {result.stderr[:200]}")
                        print("[TOOLS] You can install manually: qlc-install-tools --install-evaltools")
                except Exception as e:
                    print(f"[TOOLS] Error installing evaltools: {e}")
                    print("[TOOLS] You can install manually: qlc-install-tools --install-evaltools")
                
                print()
                print("[TOOLS] System tools (cdo, ncdump, xelatex, pyferret) will be detected from:")
                print("[TOOLS]   1. Module system (module load) - preferred on HPC")
                print("[TOOLS]   2. System installation - fallback")
                print()
                print("[TOOLS] NOTE: Cartopy Natural Earth data is PRE-DOWNLOADED during installation setup")
                print("[TOOLS]       This happens automatically via install_natural_earth_data()")
                print("[TOOLS]       NO runtime downloads will occur - everything is pre-installed")
                print()
                print("[TOOLS] After installation, run 'qlc-install-tools --check' to verify all tools")
            
            elif args.tools == "evaltools":
                print("\n[TOOLS] Installing evaltools with NumPy 2.x compatibility...")
                try:
                    import subprocess
                    result = subprocess.run(
                        [sys.executable, '-m', 'qlc.cli.qlc_install_tools', '--install-evaltools'],
                        capture_output=True, text=True, timeout=300
                    )
                    if result.returncode == 0:
                        print("[TOOLS] Evaltools installed successfully")
                    else:
                        print(f"[TOOLS] Evaltools installation had issues: {result.stderr[:200]}")
                        print("[TOOLS] You can install manually: qlc-install-tools --install-evaltools")
                except Exception as e:
                    print(f"[TOOLS] Error installing evaltools: {e}")
                    print("[TOOLS] You can install manually: qlc-install-tools --install-evaltools")
            
            elif args.tools == "all":
                print("\n[TOOLS] Installing all tools...")
                print("[TOOLS] All includes: cdo, ncdump, xelatex, evaltools, pyferret, cartopy")
                print("[TOOLS] Preferring module load for: cdo, ncdump, xelatex, pyferret")
                print()
                
                print("[TOOLS] Running: qlc-install-tools --install-all")
                try:
                    import subprocess
                    result = subprocess.run(
                        [sys.executable, '-m', 'qlc.cli.qlc_install_tools', '--install-all'],
                        capture_output=True, text=True, timeout=600
                    )
                    if result.returncode == 0:
                        print("[TOOLS] All tools installation completed successfully")
                    else:
                        print(f"[TOOLS] Tool installation had issues: {result.stderr[:200]}")
                        print("[TOOLS] You can install manually: qlc-install-tools --install-all")
                except Exception as e:
                    print(f"[TOOLS] Error installing tools: {e}")
                    print("[TOOLS] You can install manually: qlc-install-tools --install-all")
                
                print()
                print("[TOOLS] After installation, run 'qlc-install-tools --check' to verify all tools")
            
            else:
                # Handle individual tool installations: pyferret, xelatex, netcdf, cartopy
                tool_map = {
                    'pyferret': '--install-pyferret',
                    'xelatex': '--install-xelatex',
                    'netcdf': '--install-netcdf',
                    'cartopy': '--install-cartopy'
                }
                
                if args.tools in tool_map:
                    print(f"\n[TOOLS] Installing {args.tools}...")
                    print(f"[TOOLS] Running: qlc-install-tools {tool_map[args.tools]}")
                    try:
                        import subprocess
                        result = subprocess.run(
                            [sys.executable, '-m', 'qlc.cli.qlc_install_tools', tool_map[args.tools]],
                            capture_output=True, text=True, timeout=300
                        )
                        if result.returncode == 0:
                            print(f"[TOOLS] {args.tools} installed successfully")
                        else:
                            print(f"[TOOLS] {args.tools} installation had issues: {result.stderr[:200]}")
                            print(f"[TOOLS] You can install manually: qlc-install-tools {tool_map[args.tools]}")
                    except Exception as e:
                        print(f"[TOOLS] Error installing {args.tools}: {e}")
                        print(f"[TOOLS] You can install manually: qlc-install-tools {tool_map[args.tools]}")
                else:
                    print(f"\n[TOOLS] Unknown tool option: {args.tools}")
                    print("[TOOLS] Valid options: essential, evaltools, pyferret, xelatex, netcdf, cartopy, all")
                    print("[TOOLS] Run 'qlc-install-tools -h' for more details")
    else:
        parser.print_help()