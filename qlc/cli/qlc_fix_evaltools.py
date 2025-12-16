#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Evaltools Compatibility Patch: NumPy 2.x Support

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/advanced/evaltools/

Description:
    Patches evaltools 1.0.9 to work with NumPy >= 1.24.0 by replacing
    deprecated np.warnings with the standard warnings module. Automatically
    applied during evaltools installation.

Background:
    - NumPy removed np.warnings in version 1.24.0 (Dec 2022)
    - evaltools 1.0.9 still uses the deprecated np.warnings API
    - This patch fixes compatibility without downgrading NumPy

Usage:
    qlc-fix-evaltools [--dry-run] [--force]

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import subprocess
import sys
import os
import re
from pathlib import Path
from typing import Optional, Tuple
import shutil


def log(message: str, level: str = "INFO") -> None:
    """Simple logging function."""
    timestamp = ""
    if level == "ERROR":
        prefix = "✗"
    elif level == "WARN":
        prefix = "WARNING"
    elif level == "SUCCESS":
        prefix = "✓"
    else:
        prefix = "→"
    print(f"[{level}] {prefix} {message}")


def find_evaltools_path() -> Optional[Path]:
    """Find the evaltools installation path in the active environment."""
    try:
        result = subprocess.run(
            [sys.executable, "-c", "import evaltools; import inspect; print(inspect.getfile(evaltools))"],
            capture_output=True,
            text=True,
            check=True
        )
        evaltools_init = Path(result.stdout.strip())
        evaltools_dir = evaltools_init.parent
        return evaltools_dir
    except Exception as e:
        log(f"Could not find evaltools installation: {e}", "ERROR")
        return None


def get_evaltools_version() -> Optional[str]:
    """Get the installed evaltools version."""
    try:
        result = subprocess.run(
            [sys.executable, "-c", "import evaltools; print(evaltools.__version__)"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except Exception:
        return None


def check_numpy_version() -> Tuple[bool, str]:
    """Check if NumPy version requires the patch."""
    try:
        result = subprocess.run(
            [sys.executable, "-c", "import numpy as np; print(np.__version__)"],
            capture_output=True,
            text=True,
            check=True
        )
        version = result.stdout.strip()
        
        # Parse version
        major, minor = map(int, version.split('.')[:2])
        needs_patch = (major == 1 and minor >= 24) or major >= 2
        
        return needs_patch, version
    except Exception as e:
        log(f"Could not check NumPy version: {e}", "ERROR")
        return False, "unknown"


def backup_file(file_path: Path) -> Optional[Path]:
    """Create a backup of the original file."""
    backup_path = file_path.with_suffix(file_path.suffix + '.backup')
    try:
        shutil.copy2(file_path, backup_path)
        log(f"Created backup: {backup_path}")
        return backup_path
    except Exception as e:
        log(f"Could not create backup: {e}", "ERROR")
        return None


def patch_evaluator(evaluator_path: Path, dry_run: bool = False) -> bool:
    """
    Patch the evaluator.py file to use warnings instead of np.warnings.
    
    Returns:
        True if patch was applied (or would be applied in dry-run), False otherwise
    """
    if not evaluator_path.exists():
        log(f"File not found: {evaluator_path}", "ERROR")
        return False
    
    try:
        # Read the file
        content = evaluator_path.read_text()
        
        # Check if already patched
        if 'import warnings' in content and 'np.warnings' not in content:
            log("evaltools is already patched", "SUCCESS")
            return True
        
        # Count occurrences before patching
        np_warnings_count = content.count('np.warnings')
        
        if np_warnings_count == 0:
            log("No np.warnings found in evaluator.py - patch not needed", "SUCCESS")
            return True
        
        log(f"Found {np_warnings_count} occurrence(s) of 'np.warnings'")
        
        # Check if warnings is already imported
        has_warnings_import = 'import warnings' in content
        
        modified = False
        
        # Add warnings import if needed
        if not has_warnings_import:
            # Find the import section (after module docstring, before first class/def)
            # Look for the line with "import numpy as np" and add warnings import nearby
            import_pattern = r'(import numpy as np\n)'
            if re.search(import_pattern, content):
                new_import = r'\1import warnings\n'
                content = re.sub(import_pattern, new_import, content, count=1)
                log("Added 'import warnings' to imports section")
                modified = True
            else:
                log("Could not find suitable location for warnings import", "WARN")
                # Add it after pandas import as fallback
                import_pattern = r'(import pandas as pd\n)'
                if re.search(import_pattern, content):
                    new_import = r'\1import warnings\n'
                    content = re.sub(import_pattern, new_import, content, count=1)
                    log("Added 'import warnings' after pandas import")
                    modified = True
        
        # Replace np.warnings with warnings
        original_content = content
        content = content.replace('np.warnings', 'warnings')
        
        if content != original_content:
            modified = True
            replaced_count = original_content.count('np.warnings')
            log(f"Replaced {replaced_count} occurrence(s) of 'np.warnings' with 'warnings'")
        
        if not modified:
            log("No changes needed", "SUCCESS")
            return True
        
        if dry_run:
            log("DRY RUN: Changes would be applied (use without --dry-run to apply)", "WARN")
            return True
        
        # Create backup before writing
        backup_path = backup_file(evaluator_path)
        if not backup_path:
            log("Backup failed - aborting patch", "ERROR")
            return False
        
        # Write the patched content
        evaluator_path.write_text(content)
        log(f"Successfully patched: {evaluator_path}", "SUCCESS")
        log(f"Backup saved to: {backup_path}", "SUCCESS")
        
        return True
        
    except Exception as e:
        log(f"Error patching file: {e}", "ERROR")
        return False


def verify_patch(evaluator_path: Path) -> bool:
    """Verify that the patch was applied correctly."""
    try:
        content = evaluator_path.read_text()
        
        # Check that warnings is imported
        if 'import warnings' not in content:
            log("Verification failed: 'import warnings' not found", "ERROR")
            return False
        
        # Check that np.warnings is gone
        if 'np.warnings' in content:
            log("Verification failed: 'np.warnings' still present", "ERROR")
            return False
        
        # Check that warnings.catch_warnings exists
        if 'warnings.catch_warnings' not in content:
            log("Verification failed: 'warnings.catch_warnings' not found", "ERROR")
            return False
        
        log("Patch verification successful", "SUCCESS")
        return True
        
    except Exception as e:
        log(f"Error verifying patch: {e}", "ERROR")
        return False


def test_evaltools() -> bool:
    """Test that evaltools can be imported and used after patching."""
    log("Testing evaltools import...")
    try:
        result = subprocess.run(
            [sys.executable, "-c", 
             "import evaltools; "
             "from evaltools.evaluator import Evaluator; "
             "print('Import test passed')"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10
        )
        log("evaltools import test passed", "SUCCESS")
        return True
    except subprocess.TimeoutExpired:
        log("Import test timed out", "WARN")
        return False
    except Exception as e:
        log(f"Import test failed: {e}", "ERROR")
        return False


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Patch evaltools for compatibility with NumPy >= 1.24.0",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  qlc-fix-evaltools              # Apply patch
  qlc-fix-evaltools --dry-run    # Show what would be changed
  qlc-fix-evaltools --force      # Apply even if not needed
        """
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be changed without applying'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Apply patch even if NumPy version check suggests it is not needed'
    )
    parser.add_argument(
        '--verify-only',
        action='store_true',
        help='Only verify if patch has been applied'
    )
    
    args = parser.parse_args()
    
    log("QLC Evaltools Compatibility Patch")
    log("=" * 50)
    
    # Check NumPy version
    needs_patch, numpy_version = check_numpy_version()
    log(f"NumPy version: {numpy_version}")
    
    if not needs_patch and not args.force:
        log(f"NumPy version {numpy_version} does not require this patch", "SUCCESS")
        log("Use --force to apply patch anyway")
        return 0
    
    if needs_patch:
        log(f"NumPy version {numpy_version} requires the patch", "WARN")
    
    # Find evaltools
    evaltools_dir = find_evaltools_path()
    if not evaltools_dir:
        log("evaltools is not installed in the current environment", "ERROR")
        log("Install evaltools first, then run this patch script", "ERROR")
        return 1
    
    evaltools_version = get_evaltools_version()
    log(f"evaltools version: {evaltools_version}")
    log(f"evaltools location: {evaltools_dir}")
    
    evaluator_path = evaltools_dir / "evaluator.py"
    
    if not evaluator_path.exists():
        log(f"evaluator.py not found at {evaluator_path}", "ERROR")
        return 1
    
    # Verify only mode
    if args.verify_only:
        log("Verification mode - checking if patch is applied")
        if verify_patch(evaluator_path):
            return 0
        else:
            return 1
    
    # Apply patch
    log("=" * 50)
    log("Applying patch...")
    log("=" * 50)
    
    if not patch_evaluator(evaluator_path, dry_run=args.dry_run):
        log("Patch failed", "ERROR")
        return 1
    
    if args.dry_run:
        return 0
    
    # Verify patch
    log("=" * 50)
    log("Verifying patch...")
    log("=" * 50)
    
    if not verify_patch(evaluator_path):
        log("Patch verification failed", "ERROR")
        return 1
    
    # Test import
    log("=" * 50)
    log("Testing evaltools import...")
    log("=" * 50)
    
    if not test_evaltools():
        log("Import test failed - patch may need manual review", "WARN")
        return 1
    
    log("=" * 50)
    log("Patch completed successfully!", "SUCCESS")
    log("=" * 50)
    log("evaltools is now compatible with NumPy >= 1.24.0")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
