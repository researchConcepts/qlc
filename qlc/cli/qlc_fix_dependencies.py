#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Dependency Fix: Resolve Package Conflicts

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/getting-started/installation/

Description:
    Automatically fixes dependency conflicts including pandas/xarray
    compatibility, removes deprecated basemap package, and resolves
    pyshp version conflicts. Ensures clean QLC environment.

Usage:
    qlc-fix-dependencies
    python -m qlc.cli.qlc_fix_dependencies

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import subprocess
import sys
import os


def log(message: str, level: str = "INFO") -> None:
    """Simple logging function."""
    print(f"[{level}] {message}")


def run_command(cmd: list, allow_failure: bool = False) -> bool:
    """Run a command and return success status."""
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        log(f"Command succeeded: {' '.join(cmd)}")
        return True
    except subprocess.CalledProcessError as e:
        if allow_failure:
            log(f"Command failed (expected): {' '.join(cmd)}", "INFO")
            return True
        else:
            log(f"Command failed: {' '.join(cmd)}", "ERROR")
            log(f"Error: {e.stderr}", "ERROR")
            return False


def check_package_installed(package_name: str) -> bool:
    """Check if a package is installed."""
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "show", package_name],
            check=False,
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except Exception:
        return False


def remove_incompatible_packages():
    """Remove packages that are incompatible with QLC."""
    log("Checking for incompatible packages...")
    
    pip_exe = os.path.join(os.path.dirname(sys.executable), "pip")
    packages_to_remove = []
    
    # Check for basemap (deprecated, replaced by cartopy)
    if check_package_installed("basemap"):
        log("Found basemap (deprecated) - will remove", "WARN")
        packages_to_remove.append("basemap")
    
    if packages_to_remove:
        log(f"Removing incompatible packages: {', '.join(packages_to_remove)}")
        for package in packages_to_remove:
            # Use allow_failure=True in case package is already uninstalled
            run_command([pip_exe, "uninstall", "-y", package], allow_failure=True)
        log("Incompatible packages removed")
    else:
        log("No incompatible packages found")
    
    return True


def fix_dependencies():
    """Fix pandas/xarray compatibility issues and remove incompatible packages."""
    log("=== QLC Dependency Fix ===")
    
    # Determine pip executable
    pip_exe = os.path.join(os.path.dirname(sys.executable), "pip")
    log(f"Using pip: {pip_exe}")
    
    # Step 1: Remove incompatible packages
    if not remove_incompatible_packages():
        log("Failed to remove incompatible packages", "ERROR")
        return False
    
    # Step 2: Update to compatible versions
    log("Updating packages to compatible versions...")
    compatible_packages = [
        "pandas>=1.5.0,<3.0",
        "xarray>=2022.6.0,<2025.0",
        "numpy>=1.21.0,<2.0",
        "scipy>=1.9.0,<2.0",
        "matplotlib>=3.5.0,<4.0",
        "netCDF4==1.7.3",  # Working version that fixes HDF5 errors
        "h5py==3.15.1",    # Compatible HDF5 Python bindings
        "h5netcdf==1.7.2", # Compatible version
        "adjustText>=0.7.0,<0.8.0",  # Stable version to avoid TypeError
        "pyshp>=2.0,<2.4",  # Fix pyshp version conflict (cartopy compatible)
    ]
    
    for package in compatible_packages:
        if not run_command([pip_exe, "install", "--upgrade", package]):
            log(f"Failed to update {package}", "WARN")
    
    # Step 3: Ensure cartopy is properly installed
    log("Ensuring cartopy is installed (replaces basemap)...")
    if not run_command([pip_exe, "install", "--upgrade", "cartopy>=0.21.0,<1.0"]):
        log("Failed to install/upgrade cartopy", "WARN")
    
    # Test the fix
    log("Testing the fix...")
    test_cmd = [sys.executable, "-c", 
                "import pandas, xarray, cartopy; "
                "print('Compatibility test passed!')"]
    if run_command(test_cmd):
        log("=== Dependencies fixed successfully! ===")
        return True
    else:
        log("Fix failed - manual intervention may be required", "ERROR")
        return False


def main():
    """Main entry point."""
    if fix_dependencies():
        return 0
    else:
        return 1


if __name__ == "__main__":
    sys.exit(main())
