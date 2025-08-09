#!/usr/bin/env python3
"""
Basic test script for qlc package.
This script tests basic functionality without causing segmentation faults.
"""

import sys
import os

def test_basic_import():
    """Test basic import functionality."""
    try:
        print("Testing basic qlc import...")
        import qlc
        print("✓ Basic qlc import successful")
        return True
    except Exception as e:
        print(f"✗ Basic qlc import failed: {e}")
        return False

def test_version_import():
    """Test version import."""
    try:
        print("Testing version import...")
        from qlc.py import version
        print(f"✓ Version import successful: {version.QLC_VERSION}")
        return True
    except Exception as e:
        print(f"✗ Version import failed: {e}")
        return False

def test_cli_import():
    """Test CLI import."""
    try:
        print("Testing CLI import...")
        from qlc.cli import qlc_main
        print("✓ CLI import successful")
        return True
    except Exception as e:
        print(f"✗ CLI import failed: {e}")
        return False

def main():
    """Main test function."""
    print("QLC Basic Test")
    print("=" * 30)
    
    tests = [
        test_basic_import,
        test_version_import,
        test_cli_import
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
        print()
    
    print("=" * 30)
    print(f"Tests passed: {passed}/{total}")
    
    if passed == total:
        print("✓ All tests passed!")
        return 0
    else:
        print("✗ Some tests failed!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
