#!/usr/bin/env python3
"""
Test script to debug segmentation fault in qlc package.
This script imports modules one by one to identify which module causes the crash.
"""

import sys
import traceback

def test_import(module_name):
    """Test importing a specific module."""
    try:
        print(f"Testing import of {module_name}...")
        if module_name == "qlc":
            import qlc
            print(f"✓ Successfully imported {module_name}")
        elif module_name == "qlc.py":
            import qlc.py
            print(f"✓ Successfully imported {module_name}")
        elif module_name.startswith("qlc.py."):
            # Import specific submodule
            module = __import__(module_name, fromlist=[''])
            print(f"✓ Successfully imported {module_name}")
        else:
            module = __import__(module_name)
            print(f"✓ Successfully imported {module_name}")
        return True
    except Exception as e:
        print(f"✗ Failed to import {module_name}: {e}")
        traceback.print_exc()
        return False

def main():
    """Main test function."""
    print("Starting qlc import tests...")
    print("=" * 50)
    
    # Test basic imports first
    basic_modules = [
        "numpy",
        "pandas", 
        "matplotlib",
        "xarray",
        "netCDF4",
        "scipy",
        "cartopy",
        "tqdm"
    ]
    
    for module in basic_modules:
        if not test_import(module):
            print(f"Basic dependency {module} failed - this might be the issue")
            return
    
    print("\n" + "=" * 50)
    print("Testing qlc package imports...")
    
    # Test qlc package import
    if not test_import("qlc"):
        print("Failed to import qlc package")
        return
    
    # Test qlc.py import
    if not test_import("qlc.py"):
        print("Failed to import qlc.py module")
        return
    
    # Test individual qlc.py submodules
    qlc_modules = [
        "qlc.py.version",
        "qlc.py.utils", 
        "qlc.py.style",
        "qlc.py.control",
        "qlc.py.loadmod",
        "qlc.py.loadobs",
        "qlc.py.processing",
        "qlc.py.plotting",
        "qlc.py.map_plots",
        "qlc.py.timeseries_plots",
        "qlc.py.bias_plots",
        "qlc.py.scatter_plots",
        "qlc.py.statistics",
        "qlc.py.stations",
        "qlc.py.matched",
        "qlc.py.averaging",
        "qlc.py.io",
        "qlc.py.plot_config",
        "qlc.py.logging_utils",
        "qlc.py.plugin_loader"
    ]
    
    for module in qlc_modules:
        if not test_import(module):
            print(f"Failed to import {module} - this might be causing the segmentation fault")
            return
    
    print("\n" + "=" * 50)
    print("All imports successful! The segmentation fault might be in the CLI code.")
    
    # Test CLI import
    if not test_import("qlc.cli"):
        print("Failed to import qlc.cli")
        return
    
    print("✓ All imports successful!")

if __name__ == "__main__":
    main()
