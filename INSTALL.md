# QLC Installation Guide

Quick installation guide for QLC. For detailed instructions, advanced configurations, and HPC-specific setup, visit: [docs.researchconcepts.io/qlc/latest/getting-started/installation/](https://docs.researchconcepts.io/qlc/latest/getting-started/installation/)

---

## Installation Options

Choose one of three installation methods:

### Option A: PyPI Installation

**Step-by-step installation:**

```bash
# 1. Create virtual environment
python3 -m venv ~/venv/qlc

# 2. Activate virtual environment
source ~/venv/qlc/bin/activate

# 3. Upgrade pip
pip install --upgrade pip

# 4. Install QLC from PyPI
pip install rc-qlc

# 5. Setup runtime environment
qlc-install --mode test                    # For testing with example data
qlc-install --mode test --tools essential  # With essential tools (recommended)
# or
qlc-install --mode cams                    # For production (MARS compartible workflows)
qlc-install --mode cams --tools essential  # With essential tools (recommended)
# or
qlc-install --mode dev                     # For development (creates qlc-dev runtime)
qlc-install --mode dev --tools essential   # With essential tools (recommended)
```

**Important:** Add `source ~/venv/qlc/bin/activate` to your `~/.profile`, `~/.bashrc`, or `~/.login` for automatic activation on login.

### Option B: GitHub Script Download

```bash
# Download installation script
curl -sSL https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh -o qlc_install.sh

# View available options
bash qlc_install.sh -h

# Install with essential tools (recommended)
# Essential includes: cdo, ncdump, xelatex, evaltools, pyferret, cartopy
# Prefers module load for cdo, ncdump, xelatex, pyferret where available
bash qlc_install.sh --mode test --tools essential
```

### Option C: Direct GitHub Installation (One Command - Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh | bash -s -- --mode test --tools essential
```

This single command:
- Creates virtual environment
- Installs QLC and dependencies
- Sets up runtime directory
- Auto-installs essential tools:
  - evaltools (with NumPy 2.x compatibility)
  - cartopy Natural Earth data (**PRE-DOWNLOADED during installation, never at runtime**)
  - cdo, ncdump, xelatex, pyferret (via module load or system installation)
- **QLC operates completely offline after installation** - no runtime downloads

---

## Verify Installation

After installation, verify QLC is working:

```bash
# Activate environment (if not already active)
source ~/venv/qlc/bin/activate

# Check version
qlc --version

# Check tool availability
qlc-install-tools --check

# Check available variables
qlc-vars list --sources

# List workflows
ls ~/qlc/config/workflows/

# View help
qlc -h
```

---

## System Requirements

### Operating Systems
- **macOS:** 11+ (Big Sur and later) - Apple Silicon & Intel
- **Linux:** Ubuntu 20.04+, RHEL 8+, or equivalent
- **Windows:** Via WSL2 (Windows Subsystem for Linux)
- **HPC:** ATOS/ECMWF systems, SLURM-based clusters

### Python Version
- **Required:** Python 3.10 or 3.11 (Python 3.12+ is not yet supported)
- **Recommended:** Python 3.10

### Disk Space
- **Core installation:** ~1.1 GB (includes venv without dependencies)
- **Full installation:** ~1.4 GB (includes venv with all dependencies, evaltools, and Natural Earth data)
- **With external pyferret and example data:** ~1.5 GB (adds ~288 + 80 MB)

### Memory
- **Minimum:** 4 GB RAM
- **Recommended:** 8 GB RAM for multi-region processing

---

## Installation Modes

The `qlc-install` command supports three modes (both syntaxes work):

```bash
# Test mode - Testing with bundled example data
qlc-install --mode test                    # Basic installation
qlc-install --mode test --tools essential  # With essential tools (recommended)

# CAMS mode - Production CAMS workflows (for ATOS/HPC with MARS access)
qlc-install --mode cams                    # Basic installation
qlc-install --mode cams --tools essential  # With essential tools (recommended)

# Dev mode - Development mode (parallel testing)
qlc-install --mode dev                     # Basic installation
qlc-install --mode dev --tools essential   # With essential tools (recommended)
```

**Mode Details:**
- **test:** Creates `~/qlc/ -> $PERM/qlc_pypi/v1.0.2/test` (or `$HOME/qlc_pypi/...` if `$PERM` not set) with example data - best for learning and testing
- **cams:** Creates `~/qlc/ -> $PERM/qlc_pypi/v1.0.2/cams` (or `$HOME/qlc_pypi/...` if `$PERM` not set) for operational CAMS analysis - requires MARS access
- **dev:**  Creates `~/qlc-dev-run/ -> $PERM/qlc_pypi/v1.0.2/dev` (or `$HOME/qlc_pypi/...` if `$PERM` not set) for development - allows parallel testing

**Note:** 
- Both `--mode <mode>` and legacy flags (`--test`, `--cams`, `--dev`) are supported for backward compatibility
- Installation uses `$PERM/qlc_pypi` if `$PERM` is set, otherwise defaults to `$HOME/qlc_pypi`
- The stable symlink (`~/qlc` or `~/qlc-dev-run`) always points to the active installation
- Data directories use separate environment variables (`$SCRATCH`, `$HPCPERM`, `$PERM`) for optimized storage in CAMS mode

---

## Optional Components

### Essential Tools (Recommended)

For complete QLC functionality, use the `--tools essential` option during installation:

```bash
# During installation
bash qlc_install.sh --mode test --tools essential
# or
qlc-install --mode test --tools essential
```

**Essential tools include:**
- **evaltools:** Installed with NumPy 2.x compatibility patch
- **cartopy:** Natural Earth data PRE-DOWNLOADED during installation (never at runtime)
- **cdo, ncdump, xelatex, pyferret:** Detected from module system (HPC) or system installation

**Important Notes:**
- Cartopy map data is downloaded during installation, NEVER at runtime - this is required for production
- On HPC systems, cdo, ncdump, xelatex, and pyferret are preferably loaded via module load
- After installation, QLC operates completely offline with no external downloads

### Manual Tool Installation

If you didn't use `--tools essential` during installation, you can install tools separately:

```bash
# Install evaltools only
qlc-install-tools --install-evaltools

# Check tool availability
qlc-install-tools --check

# Install all missing tools (attempts installation)
qlc-install-tools --install-all
```

### PyFerret Manual Installation

PyFerret is typically available on HPC via `module load ferret`. For manual installation:

```bash
qlc-install-extras --pyferret
```

This installs PyFerret in a dedicated venv at `~/venv/pyferret`.

**Options:**
- `--venv`: Install in dedicated Python venv (default, recommended)
- `--force`: Force reinstallation

In case of issues, try the command line script:

```bash
~/qlc/bin/tools/qlc_install_pyferret.sh 
```

---

## Platform-Specific Tools

QLC requires several tools for full functionality. The `--tools essential` option (recommended) ensures all required tools are available.

**Essential tools:**
- **cdo** - Climate Data Operators (via module load or system)
- **ncdump** - NetCDF utilities (via module load or system)
- **xelatex** - PDF generation (via module load or system)
- **evaltools** - Evaluation metrics (installed with NumPy 2.x compatibility)
- **pyferret** - 3D visualization (via module load or system)
- **cartopy** - Map generation with Natural Earth data (PRE-DOWNLOADED during installation)

**IMPORTANT:** Cartopy Natural Earth data is downloaded during installation, NEVER at runtime. This ensures QLC operates completely offline in production environments.

**Check and install tools:**

```bash
# Check available tools (shows what's available via module/system/installed)
qlc-install-tools --check

# Install evaltools with NumPy 2.x compatibility
qlc-install-tools --install-evaltools

# Install all missing tools (attempts installation of unavailable tools)
qlc-install-tools --install-all

# Install specific tools
qlc-install-tools --install-xelatex      # PDF generation
qlc-install-tools --install-netcdf       # NetCDF utilities
qlc-install-tools --install-bash         # Bash 5.x (for older systems)
```

**Note:** On HPC systems, most tools (cdo, ncdump, xelatex, pyferret) are typically available via `module load` and don't require installation.

---

## Troubleshooting

### Dependency Conflicts

If you encounter dependency version conflicts:

```bash
qlc-fix-dependencies
```

Resolves common issues with basemap, numpy, pandas, xarray, netCDF4, and HDF5 versions.

### NumPy 2.x Compatibility (Evaltools)

If using evaltools with NumPy 2.x:

```bash
qlc-fix-evaltools
```

This patches evaltools to work with NumPy 2.x (replaces deprecated `np.warnings` API).

### SSL Certificate Issues (macOS) - resolved through using ~/venv/qlc

If you encounter SSL errors during cartography downloads:

```bash
# Install/update certificates for system Python
/Applications/Python*/Install\ Certificates.command
```

### Library Version Mismatches (macOS) - resolved through using ~/venv/qlc

If you encounter libtiff, HDF5, or netCDF4 errors:

```bash
# Reinstall problematic packages
pip install --upgrade --force-reinstall Pillow netCDF4 h5py
```

### Command Not Found

If QLC commands aren't found after installation:

```bash
# Ensure virtual environment is activated
source ~/venv/qlc/bin/activate

# Verify installation
pip list | grep rc-qlc

# Check command availability
which qlc
```

---

## HPC / ATOS Installation

For HPC systems, QLC automatically detects and loads required modules. No manual module loading needed.

**Installation Path Configuration (ATOS/HPC):**

QLC supports HPC-specific storage paths. Set these environment variables before installation:

```bash
# Define HPC paths (optional, only recommended for ATOS/HPC in case defaults do not suffice)
export PERM="/perm/$USER"                  # Installation base + permanent storage
export HPCPERM="/ec/res4/hpcperm/$USER"    # Analysis data storage
export SCRATCH="/ec/res4/scratch/$USER"    # Results data storage
```

**Installation Base:**
- If `$PERM` is set: `$PERM/qlc_pypi`
- Otherwise: `$HOME/qlc_pypi`

**Data Directory Mapping:**
- **CAMS mode (shared across versions):**
  - `~/qlc/Results` → `$SCRATCH/qlc_pypi/Results`
  - `~/qlc/Analysis` → `$HPCPERM/qlc_pypi/Analysis`
  - `~/qlc/Plots` → `$PERM/qlc_pypi/Plots`
  - `~/qlc/Presentations` → `$PERM/qlc_pypi/Presentations`
  
- **Test/Dev modes (isolated per version):**
  - Data directories created within version directory
  - Example: `$PERM/qlc_pypi/v1.0.2/test/data/Results`

A stable symlink will always be created at `~/qlc` pointing to the installation base.

**Basic installation:**

```bash
# Auto-resolve HPC paths (if set, e.g., on ATOS/HPC)

# Activate environment and install
source ~/venv/qlc/bin/activate
pip install rc-qlc
qlc-install --mode cams # for ATOS/HPC 
```

**Module environment:**

QLC's environment detection automatically:
- Detects all required modules (e.g., netcdf4, hdf5, eccodes, python3)
- Loads required modules on demand and in the correct order
- Handles module dependencies
- Configures environment variables

For detailed HPC setup: [docs.researchconcepts.io/qlc/latest/integration-guides/hpc-atos/](https://docs.researchconcepts.io/qlc/latest/integration-guides/hpc-atos/)

---

## Upgrading

### Upgrade to Latest Version

```bash
# Activate environment
source ~/venv/qlc/bin/activate

# Upgrade QLC
pip install --upgrade rc-qlc
```

### Clean Reinstall

If you encounter issues after upgrade:

```bash
# Uninstall
pip uninstall rc-qlc -y

# Clear pip cache
pip cache purge

# Reinstall
pip install rc-qlc

# Reconfigure runtime
qlc-install --mode test
```

---

## Directory Structure

After installation, you'll have:

```
~/venv/qlc/              # Virtual environment (~1.3 GB)
~/qlc/                   # Runtime directory
  ├── config/            # Configuration files
  │   ├── workflows/     # Workflow configurations (aifs, eac5, evaltools, mars, pyferret, test)
  │   ├── tables/        # Variable mapping tables
  │   │   ├── obs_database/       # Observation network definitions (including GHOST data base)
  │   │   └── model_variables/    # Model parameter definitions (including IFS grib parameters)
  │   ├── station_locations/      # Station location CSV files (examples for all, rural, urban station locations)
  │   ├── qlc-py/        # Standalone qlc-py resources
  │   │   └── json/      # Example JSON configs (keep here e.g. copies of auto-generated json files)
  │   └── qlc.conf       # Main configuration file
  ├── bin/               # Scripts and tools (no need for changes)
  ├── obs/               # Observation data (for ALTOS/HPC links to shared cams observation)
  ├── Analysis/          # Analysis output (content created during qlc or sqlc execution, for ATOS/HPC links to $HPCPERM)
  ├── Plots/             # Plot output (content created during qlc-py or qlc/sqlc execution, for ATOS/HPC links to $PERM)
  └── Results/           # MARS retrieval data (content created when using qlc_A1-MARS.sh, for ATOS/HPC links to $SCRATCH)
```

---

## Virtual Environment Activation

### Manual Activation

```bash
source ~/venv/qlc/bin/activate
```

### Automatic Activation (Recommended)

Add to `~/.profile`, `~/.bashrc`, or `~/.login`:

```bash
# QLC environment
if [ -f "$HOME/venv/qlc/bin/activate" ]; then
    source "$HOME/venv/qlc/bin/activate"
fi
```

---

## Next Steps

Once installed:

1. **Quick Start:** [docs.researchconcepts.io/qlc/latest/getting-started/quickstart/](https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/)
2. **First Analysis:** [docs.researchconcepts.io/qlc/latest/getting-started/first-analysis/](https://docs.researchconcepts.io/qlc/latest/getting-started/first-analysis/)
3. **User Guide:** [docs.researchconcepts.io/qlc/latest/user-guide/usage/](https://docs.researchconcepts.io/qlc/latest/user-guide/usage/)

### Run Example Analysis

```bash
# Activate environment
source ~/venv/qlc/bin/activate

# Run AIFS analysis (data from June 2025 onwards)
qlc 9191 0001 2025-11-01 2025-11-03 aifs

# View results
ls ~/qlc/Plots/9191_0001_20251101-20251103/
```

---

## Getting Help

All QLC commands have built-in help:

```bash
qlc -h                     # Main driver help
sqlc -h                    # Batch job help  
qlc-py -h                  # Python standalone help
qlc-vars -h                # Variable discovery help
qlc-install -h             # Installation help
qlc-install-extras -h      # Optional tools help
qlc-install-tools -h       # Platform tools help
qlc-fix-dependencies -h    # Dependency fixer help
qlc-fix-evaltools -h       # Evaltools patcher help
```

**Documentation:**
- **Website:** [docs.researchconcepts.io/qlc](https://docs.researchconcepts.io/qlc)
- **GitHub:** [github.com/researchConcepts/qlc](https://github.com/researchConcepts/qlc)
- **Issues:** [github.com/researchConcepts/qlc/issues](https://github.com/researchConcepts/qlc/issues)
- **Email:** qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>

---

## Development Installation

For developers who want to build from source or contribute to QLC:

See: [docs.researchconcepts.io/qlc/latest/developer/building/](https://docs.researchconcepts.io/qlc/latest/developer/building/) *(upcoming)*
