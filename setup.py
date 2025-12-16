# setup.py
"""
Robust setup script for QLC.

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""
try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    import tomli as tomllib  # Python < 3.11
import datetime
from pathlib import Path
from setuptools import setup, Extension, find_packages
import sys
import platform

from Cython.Build import cythonize

from setuptools.command.build_py import build_py as _build_py
from setuptools.command.build_ext import build_ext as _build_ext
import os

import shutil

def get_ignore_patterns():
    """Returns a set of patterns to ignore during file copy."""
    return shutil.ignore_patterns(
        ".DS_Store",
        "__pycache__",
        "*.pyc",
        "ToDo"
    )

class CustomBuildPyCommand(_build_py):
    """Custom build to manually copy all data dirs, resolving symlinks."""
    def run(self):
        # Run standard build first
        _build_py.run(self)

        if not self.dry_run:
            build_dir = Path(self.build_lib)
            
            # Manually copy all data directories
            data_dirs = ["config", "doc", "examples", "sh"]
            ignore = get_ignore_patterns()
            
            for d in data_dirs:
                source_dir = Path("qlc") / d
                target_dir = build_dir / "qlc" / d
                
                print(f"Manually copying data directory: {source_dir} -> {target_dir}")
                
                if source_dir.exists():
                    shutil.copytree(
                        source_dir, 
                        target_dir, 
                        symlinks=False, 
                        dirs_exist_ok=True,
                        ignore=ignore
                    )

class CustomBuildExtCommand(_build_ext):
    """Custom build_ext with configurable optimization level.
    
    Set QLC_DEBUG_BUILD=1 environment variable for fast debug builds (-O0).
    Otherwise, uses -O3 optimization for production builds.
    
    Examples:
        # Fast debug build (no optimization):
        QLC_DEBUG_BUILD=1 pip install -e .
        
        # Production build (maximum optimization):
        pip install -e .
    """
    def build_extensions(self):
        # Check if debug build is requested via environment variable
        debug_build = os.environ.get('QLC_DEBUG_BUILD', '0') == '1'
        opt_flag = '-O0' if debug_build else '-O3'
        build_mode = "debug (fast compilation)" if debug_build else "production (optimized)"
        
        print(f"[BUILD] Build mode: {build_mode}")
        print(f"[BUILD] Optimization flag: {opt_flag}")
        
        for ext in self.extensions:
            # Get current compile args
            compile_args = list(ext.extra_compile_args or [])
            
            # Remove any existing -O flags to avoid conflicts
            compile_args = [arg for arg in compile_args if not arg.startswith('-O')]
            
            # Add appropriate optimization flag
            compile_args.append(opt_flag)
            ext.extra_compile_args = compile_args
            
            print(f"[BUILD] Extension {ext.name}: compiling with {opt_flag}")
        
        # Call parent build_extensions
        _build_ext.build_extensions(self)

# --- Helper functions ---



def get_version_from_pyproject(pyproject_path: Path) -> str:
    if tomllib.__name__ == "toml":
        with pyproject_path.open("r", encoding="utf-8") as f:
            config = tomllib.load(f)
    else:
        with pyproject_path.open("rb") as f:
            config = tomllib.load(f)
    return config["project"]["version"]

def generate_version_py(version: str, output_path: Path):
    """Generates a qlc/py/version.py file from a template."""
    template_path = Path("qlc/py/version.py.in")
    content = template_path.read_text()
    content = content.replace("@QLC_VERSION@", version)
    content = content.replace("@QLC_RELEASE_DATE@", datetime.date.today().isoformat())
    output_path.write_text(content)

# --- Main setup logic ---

root = Path(__file__).parent
version = get_version_from_pyproject(root / "pyproject.toml")

# Generate the version.py file dynamically before the build starts
generate_version_py(version, root / "qlc/py/version.py")

# Gather py files for compilation from qlc/py
# Note: Excluded from compilation:
# - __init__.py, test files, __main__.py (standard exclusions)
py_files_to_compile = [
    p for p in Path("qlc/py").glob("*.py") 
    if p.name != "__init__.py" 
    and not p.name.startswith("test_")
    and p.name != "__main__.py"
]

# Check build mode from environment
debug_build = os.environ.get('QLC_DEBUG_BUILD', '0') == '1'
build_mode = "debug mode (fast -O0)" if debug_build else "production mode (optimized -O3)"
print(f"[BUILD] Compiling {len(py_files_to_compile)} files in {build_mode}")
if debug_build:
    print("[BUILD] Tip: Unset QLC_DEBUG_BUILD for optimized production builds")

# Print build environment for debugging ABI mismatches
try:
    import numpy as _np
    _np_includes = [_np.get_include()]
    print(f"[BUILD-ENV] Python: {sys.version}")
    print(f"[BUILD-ENV] Platform: {platform.platform()}")
    print(f"[BUILD-ENV] NumPy version: {_np.__version__}")
    print(f"[BUILD-ENV] NumPy include: {_np_includes}")
except Exception as _e:
    _np_includes = []
    print(f"[BUILD-ENV] NumPy not importable during build: {_e}")

# Define Cython extensions
# NOTE: Optimization level controlled by QLC_DEBUG_BUILD environment variable
# QLC_DEBUG_BUILD=1 -> -O0 (fast compilation for debugging)
# QLC_DEBUG_BUILD=0 or unset -> -O3 (maximum optimization for production)
opt_flag = '-O0' if debug_build else '-O3'
extensions = cythonize(
    [
        Extension(
            "qlc.py." + f.stem,
            [str(f)],
            include_dirs=_np_includes,
            # Optimization flag will be enforced by CustomBuildExtCommand
            extra_compile_args=[opt_flag],
        )
        for f in py_files_to_compile
    ],
    compiler_directives={
        "language_level": "3",
        "boundscheck": False,      # Aggressive: disable bounds checking
        "wraparound": False,       # Aggressive: disable negative indexing
        "initializedcheck": False, # Aggressive: disable initialization checks
        "nonecheck": False,        # Aggressive: disable None checks
        "cdivision": True,         # Aggressive: C-style division
        "embedsignature": True,
    },
)

# Long description from doc
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://pypi.org/project/qlc/",
    packages=find_packages(exclude=["qlc.py", "qlc.py.*"]),
    ext_modules=extensions,
    include_package_data=True,
    zip_safe=False,

    package_data={},



    cmdclass={
        "build_py": CustomBuildPyCommand,
        "build_ext": CustomBuildExtCommand
    },

    # Classifiers moved to pyproject.toml to avoid setuptools warnings
)