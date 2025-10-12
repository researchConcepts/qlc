# QLC Development Version Installation Guide

This guide helps you install the development version (0.4.1+) alongside the stable PyPI release. Starting with v0.4.1, QLC supports **parallel PyPI and development installations** with complete isolation.

## Overview

**Key Changes in v0.4.1:**
- ✅ Parallel installations without conflicts
- ✅ Isolated runtime directories (`qlc_pypi/` vs `qlc_dev/`)
- ✅ Intelligent runtime detection based on conda environment
- ✅ Easy version switching via conda or `QLC_HOME`

**Directory Structure:**
- **PyPI Runtime**: `~/qlc_pypi/v0.4.1/test/` → accessed via `~/qlc`
- **Dev Runtime**: `~/qlc_dev/v0.4.1/dev/` → accessed via `~/qlc-dev-run`

## Quick Setup

```bash
# 1. Create and activate development environment (use 'qlc-dev' name)
conda create -n qlc-dev python=3.10 -y
conda activate qlc-dev

# 2. Install system dependencies (optional but recommended)
conda install -c conda-forge cdo eccodes netcdf4 -y

# 3. Navigate to development directory
cd $HOME/qlc-dev

# 4. Install development version with optional dependencies
pip install -e ".[dev]"

# 5. Setup dev runtime (creates isolated qlc_dev/ runtime)
qlc-install --mode dev

# 6. Setup conda environment auto-switching (recommended)
bash qlc/sh/tools/setup_conda_env.sh qlc-dev

# 7. Test the setup
conda deactivate && conda activate qlc-dev
qlc --version
# Should show: Runtime: /Users/<user>/qlc-dev-run (conda-dev)
```

## Install Options

### Minimal Installation
```bash
pip install -e .
```

### With PyFerret Support
```bash
pip install -e ".[ferret]"
```

### Full Development Setup (Recommended)
```bash
pip install -e ".[dev]"
```

**Note**: Evaltools must be installed separately following instructions in `qlc/doc/EVALTOOLS.md` (manual download required).

## Setting Up Evaltools (Manual Method)

If automatic installation fails, use the manual conda approach:

```bash
# Install evaltools following the detailed instructions in qlc/doc/EVALTOOLS.md

# Quick summary:
cd ~/download_evaltools
wget https://redmine.umr-cnrm.fr/attachments/download/5300/evaltools_v1.0.9.zip
wget https://redmine.umr-cnrm.fr/attachments/download/5298/documentation_v1.0.9.zip
# ... (download and setup - see EVALTOOLS.md for complete steps)

conda env create -f environment.yml
conda activate evaltools

# Verify
python -c "import evaltools; print(evaltools.__version__)"
# Should output: 1.0.9

# Return to qlc-dev environment
conda activate qlc-dev
```

**Note**: See `qlc/doc/EVALTOOLS.md` for complete installation instructions including all download URLs and dependencies.

## Environment Management

### Switch Between Versions

Starting with v0.4.1, version switching is seamless:

```bash
# Method 1: Use Conda Environment (Automatic - Recommended)
# Use PyPI release (production)
conda deactivate  # or conda activate base
cd ~/qlc
qlc --version
# Output: QLC version 0.4.1 [PyPI (User)]
#         Runtime: /Users/<user>/qlc (default)

# Use development version
conda activate qlc-dev
cd ~/qlc-dev-run
qlc --version
# Output: QLC version 0.4.1 [Development (Conda)]
#         Runtime: /Users/<user>/qlc-dev-run (conda-dev)

# Method 2: Use QLC_HOME Environment Variable (Manual)
export QLC_HOME=~/qlc          # Use PyPI
export QLC_HOME=~/qlc-dev-run  # Use dev
qlc --version

# Method 3: Use Different Terminals
# Terminal 1: Production
cd ~/qlc && qlc b2ro b2rn 2018-12-01 2018-12-21

# Terminal 2: Development (in parallel!)
conda activate qlc-dev
cd ~/qlc-dev-run && qlc b2ro b2rn 2018-12-01 2018-12-21
```

### Runtime Detection Priority

QLC uses intelligent runtime detection with three-tier priority:

1. **Explicit Override**: `QLC_HOME` environment variable (highest priority)
2. **Conda Auto-detection**: Based on active conda environment name
   - If conda env contains `qlc-dev` → uses `~/qlc-dev-run`
   - Auto-configured if you ran `setup_conda_env.sh`
3. **Default**: `~/qlc` (production runtime)

### Rebuild After Code Changes

For Cython-compiled modules:

```bash
conda activate qlc-dev
cd $HOME/qlc-dev

# Rebuild Cython extensions
python setup.py build_ext --inplace

# Or force reinstall
pip install -e ".[dev]" --force-reinstall --no-deps
```

## Testing New Features

### Test Station Extraction Tool

```bash
conda activate qlc-dev

# Extract all stations
qlc-extract-stations \
    --obs-path ~/qlc-dev-run/obs/data/ver0d \
    --obs-type ebas_daily \
    --output ~/qlc-dev-run/obs/data/test_stations.csv

# Extract urban stations only
qlc-extract-stations \
    --obs-path ~/qlc-dev-run/obs/data/ver0d \
    --obs-type ebas_daily \
    --obs-version latest/201801 \
    --station-type urban \
    --output ~/qlc-dev-run/obs/data/urban_stations.csv
```

### Test Evaltools Integration

```bash
conda activate qlc-dev
cd ~/qlc-dev-run/run

# Step 1: Create collocation
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Step 2: Generate evaltools plots
# (This will auto-activate the evaltools conda environment)
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools

# View results
open ~/qlc-dev-run/Presentations/CAMS2_35_summary.pdf
```

### Compare PyPI vs Dev Results

```bash
# Run with PyPI version
conda deactivate
cd ~/qlc/run
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Run with dev version
conda activate qlc-dev
cd ~/qlc-dev-run/run
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Compare outputs
diff -r ~/qlc/Plots ~/qlc-dev-run/Plots
```

## Troubleshooting

### Wrong Runtime Being Used

If `qlc --version` shows unexpected runtime:

```bash
# Check detection
conda activate qlc-dev
qlc --version
# Should show: Runtime: /Users/<user>/qlc-dev-run (conda-dev)
#  e.g., a symlink to ~/qlc_dev/v0.4.1/dev)

# If not, manually setup conda environment
bash ~/qlc-dev-run/bin/tools/setup_conda_env.sh qlc-dev

# Then reactivate
conda deactivate && conda activate qlc-dev
qlc --version
```

### Runtime Directory Not Found

If you see "QLC runtime directory not found":

```bash
# Make sure you ran the installer
conda activate qlc-dev
qlc-install --mode dev

# Verify it was created
ls -la ~/qlc_dev/
ls -la ~/qlc-dev-run
```

### Missing Dependencies

If you see dependency warnings during installation:

```bash
conda activate qlc-dev
pip install tomli pyproject-hooks keyring readme-renderer \
            requests requests-toolbelt rfc3986 rich urllib3
```

### Evaltools Environment Not Found

Check the environment name in config:

```bash
# View current setting
grep EVALTOOLS_CONDA_ENV ~/qlc-dev-run/config/evaltools/qlc_evaltools.conf

# Should output: EVALTOOLS_CONDA_ENV="evaltools"
```

If using a different environment name, update the config or rename your environment:

```bash
conda rename -n your_evaltools_env evaltools
```

### Build/Cython Errors

If you encounter Cython compilation errors:

```bash
conda activate qlc-dev
pip install --upgrade cython numpy
cd $HOME/qlc-dev
pip install -e . --no-build-isolation
```

### Conda Auto-switching Not Working

If conda activation doesn't auto-set `QLC_HOME`:

```bash
# Verify activation scripts exist
ls ~/.conda/envs/qlc-dev/etc/conda/activate.d/qlc-dev-env.sh
ls ~/.conda/envs/qlc-dev/etc/conda/deactivate.d/qlc-dev-env.sh

# If missing, run setup script again
bash ~/qlc-dev-run/bin/tools/setup_conda_env.sh qlc-dev

# Test manually
conda deactivate
conda activate qlc-dev
echo $QLC_HOME
# Should output: /Users/<user>/qlc-dev-run
```

## Uninstall

```bash
# Remove development installation
conda activate qlc-dev
pip uninstall rc-qlc -y

# Remove conda environment
conda deactivate
conda env remove -n qlc-dev

# Optionally remove runtime directories
rm -rf ~/qlc_dev/
rm -f ~/qlc-dev-run
```

## Architecture Details

### Directory Naming Convention

Starting with v0.4.1, QLC uses a clear naming convention:

**Source Code (Hyphens):**
- `~/qlc-pypi/` - Public source code repository (synced to GitHub public)
- `~/qlc-dev/` - Private source code repository (GitHub private)

**Runtime (Underscores):**
- `~/qlc_pypi/` - PyPI runtime installations
- `~/qlc_dev/` - Development runtime installations

### Complete Directory Structure

```
# Source Repositories
~/qlc-dev/                      # Private dev source
~/qlc-pypi/                     # Public PyPI source (optional)

# PyPI Runtime
~/qlc_pypi/
  └── v0.4.1/
      ├── test/                 # Test mode
      │   ├── config/
      │   ├── bin/
      │   ├── obs/
      │   ├── mod/
      │   ├── Results/
      │   ├── Plots/
      │   └── Presentations/
      └── cams/                 # CAMS mode
~/qlc -> ~/qlc_pypi/v0.4.1/test

# Development Runtime
~/qlc_dev/
  └── v0.4.1/
      ├── dev/                  # Active development
      │   ├── config/
      │   ├── bin/
      │   ├── obs/
      │   ├── mod/
      │   ├── Results/
      │   ├── Plots/
      │   └── Presentations/
      └── test/                 # Dev testing
~/qlc-dev-run -> ~/qlc_dev/v0.4.1/dev

# Package Installations
~/.local/lib/python3.10/site-packages/qlc/     # PyPI package
~/.conda/envs/qlc-dev/lib/.../qlc/             # Dev package (editable)
```

### How It Works

1. **Installation**: `pip install` puts code in site-packages
2. **Runtime Setup**: `qlc-install --mode dev` creates runtime directory
3. **Detection**: QLC detects which runtime to use:
   - Checks `QLC_HOME` environment variable
   - Auto-detects from conda environment name
   - Defaults to `~/qlc`
4. **Execution**: Commands run in detected runtime directory

## References

- **Evaltools Documentation**: https://opensource.umr-cnrm.fr/projects/evaltools/wiki
- **QLC Main Documentation**: ~/qlc/doc/README.md
- **Usage Guide**: ~/qlc/doc/USAGE.md
