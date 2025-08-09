# setup.py
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

# --- Helper functions ---



def get_version_from_pyproject(pyproject_path: Path) -> str:
    if tomllib.__name__ == "toml":
        with pyproject_path.open("r", encoding="utf-8") as f:
            config = tomllib.load(f)
    else:
        with pyproject_path.open("rb") as f:
            config = tomllib.load(f)
    return config["project"]["version"]



# --- Main setup logic ---

root = Path(__file__).parent

# Gather py files for compilation from qlc/py
# Note: __init__.py is excluded as it shouldn't be compiled itself.
py_files_to_compile = [
    p for p in Path("qlc/py").glob("*.py") if p.name != "__init__.py"
]

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

# Define Cython extension(s)
extensions = cythonize(
    [
        Extension(
            "qlc.py." + f.stem,
            [str(f)],
            include_dirs=_np_includes,
        )
        for f in py_files_to_compile
    ],
    compiler_directives={
        "language_level": "3",
        "boundscheck": False,
        "wraparound": False,
        "initializedcheck": False,
        "nonecheck": False,
        "cdivision": True,
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
        "build_py": CustomBuildPyCommand
    },

    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: Unix"
    ],
)