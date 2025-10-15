# Quick Look Content (QLC): An Automated Model–Observation Comparison Suite Optimized for CAMS

> **⚠️ BETA RELEASE - v0.4.2**: This release includes critical bug fixes for PyPI distribution and cross-platform compatibility. While core functionality has been validated, platform-specific testing is ongoing. Please report any issues you encounter.

**Quick Look Content (QLC)** is a powerful, command-line driven suite for model–observation comparisons, designed to automate the evaluation of climate and air quality model data. It is optimized for use with CAMS (Copernicus Atmospheric Monitoring Service) datasets but is flexible enough for general use cases.

The suite streamlines the entire post-processing workflow, from data retrieval and collocation to statistical analysis and the generation of publication-quality figures and reports.

| Package | Status |
|---------|--------|
| [rc-qlc on PyPI](https://pypi.org/project/rc-qlc/) | ![PyPI](https://img.shields.io/pypi/v/rc-qlc?color=blue) |

---

## What's New in v0.4.2 (Beta)

**Critical Bug Fixes for PyPI Distribution**

This patch release resolves several critical issues that prevented v0.4.1 from working correctly when installed via PyPI:

### Fixed Issues

1. **Missing Package Modules** (Critical)
   - Added missing `qlc/py/__init__.py` that prevented Python from recognizing the compiled modules package
   - Added `statistics2.py` module (renamed from `statistics` to avoid Python stdlib conflict)
   - Added `extract_stations.py` module for station filtering functionality
   - **Impact**: v0.4.1 PyPI users got `ModuleNotFoundError: No module named 'qlc.py.statistics2'`

2. **ATOS/HPC Bash Compatibility** (Critical)
   - Fixed bash array expansion in `qlc_D1.sh` that failed on older bash versions
   - Changed from indirect expansion `${!var[@]}` to eval-based expansion for better compatibility
   - **Impact**: ATOS users got `bad substitution` error and script termination

3. **NumPy Version Conflicts**
   - Constrained numpy to `>=1.21.0,<2.0` to prevent conflicts with scipy, netCDF4, and other scientific packages
   - **Impact**: Installing netCDF4 automatically upgraded to numpy 2.x, breaking scipy and other dependencies

4. **macOS Library Compatibility Issues**
   - Added comprehensive troubleshooting guide for Pillow/libtiff errors on macOS
   - Documented netCDF4/HDF5 symbol resolution issues
   - Provided solutions for system library version mismatches

### Installation Notes

- **macOS users**: If you encounter library errors (libtiff, HDF5), see the Troubleshooting section
- **HPC users**: On systems like ATOS, use system modules for compiled dependencies (numpy, netCDF4, scipy) rather than pip installing them

### Upgrade Instructions

```bash
pip install --upgrade rc-qlc
```

If you encounter issues after upgrading, clean reinstall:

```bash
pip uninstall rc-qlc -y
pip install rc-qlc
qlc-install --mode test  # or --mode cams
```

---

## What's New in v0.4.1 (Beta)

**Note**: This is a beta release undergoing active testing and validation.

This major release represents a complete architectural overhaul of QLC, transforming it from a two-experiment comparison tool into a comprehensive, flexible model-observation analysis framework. Key improvements include unlimited experiment support, multi-region analysis capabilities, advanced statistical integration, and a modern task-based configuration system.

### Known Limitations

- **Threading on macOS**: When using ThreadPoolExecutor with NetCDF/HDF5 files on some systems, set `"n_threads": "1"` in your configuration to avoid HDF5 library thread-safety issues (if needed)
- Platform-specific testing is ongoing - please report any issues you encounter

### 1. Complete Multi-Experiment Architecture

**Major Enhancement**: All QLC scripts (A1-F5, Z1) now support **unlimited experiments** - no longer limited to two.

-   **Dynamic Experiment Handling**:
    -   Compare any number of experiments: 1, 2, 3, or more
    -   Last experiment automatically designated as reference
    -   All non-reference experiments compared against reference
    -   Consistent file naming: `exp1-exp2-exp3-...-expN`
    
-   **Examples**:
    ```bash
    # Two experiments (traditional)
    qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
    
    # Three or more experiments
    qlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy
    qlc exp1 exp2 exp3 exp4 2018-12-01 2018-12-21 evaltools
    ```

-   **Smart Plot Generation**:
    -   Automated reference selection (last experiment)
    -   Difference plots for all exp vs reference comparisons
    -   Dynamic title formatting: "exp1, exp2 vs exp3"
    -   Consistent across all output formats (PNG, PDF, TeX)

### 2. Multi-Region Analysis Framework

**Transformative Capability**: Process multiple geographical regions with different observation networks in a single execution.

-   **Multi-Region Processing** (qlc_D1.sh):
    -   Analyze Europe, North America, and Asia simultaneously
    -   Region-specific observation networks (EBAS, CASTNET, AMoN, AirNow, China AQ, AERONET)
    -   Automatic variable filtering based on data availability
    -   Per-region configuration overrides (MARS retrievals, search radius, variables)
    
-   **Region-Specific Customization**:
    ```bash
    # Configure multiple regions in qlc_qpy.conf
    MULTI_REGION_MODE=true
    ACTIVE_REGIONS=("EU" "US_CASTNET" "US_AMON")
    
    # EU: Dense EBAS network
    REGION_EU_VARIABLES="NH3,NH4_as,O3,PM25"
    REGION_EU_STATION_RADIUS_DEG=0.5
    
    # US AMoN: Sparse NH3-only network
    REGION_US_AMON_VARIABLES="NH3"
    REGION_US_AMON_STATION_RADIUS_DEG=2.0
    REGION_US_AMON_MARS_RETRIEVALS=("B1_pl")
    ```

-   **Organized Output Structure**:
    -   Region-specific subdirectories: `Plots/exp_DATE/EU/`, `Plots/exp_DATE/US_CASTNET/`
    -   Combined TeX files for multi-region reports
    -   Individual region TeX files for detailed analysis

### 3. Advanced Statistical Integration: Evaltools

**New Integration**: Comprehensive statistical analysis with Taylor diagrams and 15+ advanced plot types.

-   **Evaltools Workflow** (E1, E2 scripts):
    -   Direct conversion from qlc-py collocation to evaltools format
    -   Automatic discovery of experiments and variables from collocated data
    -   Multi-experiment overlay in statistical plots
    
-   **Statistical Visualizations**:
    -   Taylor diagrams (standard deviation, correlation, RMSE)
    -   Target diagrams (bias vs unbiased RMSE)
    -   Enhanced time series with statistical metrics
    -   Seasonal cycle analysis
    -   Quantile-quantile plots
    -   Diurnal cycle analysis (hourly data)
    
-   **Scientific Applications**:
    ```bash
    # Create collocation
    qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
    
    # Generate advanced statistics
    qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools
    ```
    
-   **Multi-Region Compatible**: Automatically processes all regions when using multi-region mode

### 4. Ver0D External Tool Integration

**HPC Integration**: Seamless integration with ECMWF's ver0D verification tool for specialized analysis.

-   **Ver0D Scripts** (F1-F5):
    -   **F1**: Data retrieval for AOD and GAW modes
    -   **F2**: AOD plots with AERONET observations
    -   **F3**: GAW surface plots (Global Atmosphere Watch)
    -   **F4/F5**: Total column and surface aerosol (stub implementations)
    
-   **Multi-Experiment Support**:
    -   All ver0D scripts updated for unlimited experiments
    -   Consistent file naming and directory structure
    -   Ver0D-specific date format standardization
    
-   **Usage**:
    ```bash
    # Run ver0D analysis (ATOS/HPC systems)
    qlc exp1 exp2 exp3 2018-12-01 2018-12-21 ver0d
    ```

### 5. Task-Based Configuration System

**Flexible Workflow**: Select analysis pipeline via command-line task parameter.

-   **Available Tasks**:
    -   **`qpy`**: Fast qlc-py collocation and time series plots
    -   **`evaltools`**: Advanced statistical analysis with evaltools
    -   **`eac5`**: EAC5/CAMS reanalysis validation (K1 namelist)
    -   **`pyferret`**: PyFerret global visualization
    -   **`ver0d`**: Ver0D external verification (ATOS-specific)
    -   **`mars`**: MARS data retrieval only
    -   **default**: Standard workflow with all subscripts
    
-   **Configuration Structure**:
    ```
    qlc/config/
    ├── qlc.conf              # Base configuration
    ├── qpy/
    │   └── qlc_qpy.conf      # qlc-py specific
    ├── evaltools/
    │   └── qlc_evaltools.conf  # Evaltools specific
    └── eac5/
        └── qlc_eac5.conf      # EAC5 specific
    ```
    
-   **Configuration Inheritance**: Task configs inherit base settings and add overrides
    
-   **Usage Examples**:
    ```bash
    # qlc-py only
    qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
    
    # Advanced statistics
    qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools
    
    # EAC5 validation
    qlc b2ro b2rn 2018-12-01 2018-12-21 eac5
    ```

### 6. K1 Namelist: EAC5/CAMS Reanalysis Configuration

**Comprehensive Setup**: Pre-configured MARS retrieval optimized for atmospheric reanalysis validation.

-   **10 Surface Variables**:
    -   Temperature (T)
    -   Particulate Matter (PM2.5, PM10)
    -   Gases (O3, NO2, SO2, HNO3, NH3)
    -   Aerosol Components (NH4_as - ammonium)
    -   Optical Properties (AOD - aerosol optical depth)
    
-   **Scientific Applications**:
    -   EAC5/CAMS reanalysis validation
    -   Multi-temporal analysis (daily, weekly, monthly, seasonal)
    -   Multi-network comparison (EBAS, CASTNET, AMoN, AERONET)
    -   Urban vs rural performance assessment
    -   Seasonal skill evaluation
    
-   **Integrated Workflow**:
    ```bash
    # Complete EAC5 validation with Taylor diagrams
    qlc b2ro b2rn 2018-12-01 2018-12-21 eac5 evaltools
    ```
    
-   **Multi-Region Ready**: Automatically adapts to regional observation networks

### 7. Modern Installation Architecture

**Development-Ready**: New installation system supporting parallel PyPI and development environments.

-   **Parallel Installation Support**:
    -   Run PyPI and dev versions simultaneously without conflicts
    -   Isolated runtime directories: `~/qlc_pypi/` (production) and `~/qlc_dev/` (development)
    -   Access via stable symlinks: `~/qlc` (PyPI) and `~/qlc-dev-run` (dev)
    -   New installer mode: `qlc-install --mode dev`

-   **Intelligent Runtime Detection**:
    -   Three-tier priority system for automatic runtime selection
    -   Priority 1: `QLC_HOME` environment variable (explicit override)
    -   Priority 2: Conda environment auto-detection (if env name contains `qlc-dev`)
    -   Priority 3: Default to `~/qlc` (production)

-   **Enhanced Version Information**:
    -   `qlc --version` now shows installation type, runtime location, and detection method
    -   Clear distinction between PyPI and development installations
    -   Example output: `QLC version 0.4.1 [Development (Conda)] Runtime: ~/qlc-dev-run (conda-dev)`

-   **Conda Environment Integration**:
    -   New `setup_conda_env.sh` script for automatic runtime switching
    -   Auto-sets `QLC_HOME` when activating `qlc-dev` conda environment
    -   Seamless switching: `conda activate qlc-dev` → uses dev runtime automatically

-   **Clear Naming Convention**:
    -   Source code (hyphens): `~/qlc-pypi/` (public), `~/qlc-dev/` (private)
    -   Runtime (underscores): `~/qlc_pypi/` (PyPI), `~/qlc_dev/` (dev)

### Additional Enhancements

-   **Global Station Filtering**: 
    -   New `qlc-extract-stations` command-line tool
    -   Comprehensive database of 300+ major world cities
    -   Urban/rural classification globally (all continents)
    -   Enables targeted station subset analysis

-   **Improved Documentation**:
    -   Expanded USAGE.md with comprehensive examples
    -   Task-specific configuration guides
    -   Multi-region setup tutorials
    -   Evaltools integration documentation

-   **Enhanced Error Handling**:
    -   Graceful handling of missing data
    -   Automatic variable discovery and validation
    -   Comprehensive logging throughout pipeline
    -   Clear error messages and diagnostic information

### Migration from v0.3.27

**Important**: v0.4.1 represents a major architectural change. Fresh installation recommended.

-   New installation structure (`~/qlc_pypi/` or `~/qlc_dev/`)
-   Task-based configuration system
-   Updated shell script architecture
-   No automatic migration from v0.3.x

**Use Cases**: Global model evaluation, multi-network validation campaigns, urban/rural comparisons, reanalysis validation, seasonal analysis, dataset-specific studies

---

## What's New in v0.3.27

This release focuses on improving the out-of-the-box installation experience, especially for HPC environments, and significantly expanding the user documentation.

-   **Installer Overhaul**: The `qlc-install` script is now more robust.
    -   It automatically creates the `qlc` -> `qlc_latest` -> `qlc_vX.Y.Z/<mode>` symlink structure, removing the need for manual setup.
    -   It now provides clear, actionable instructions on how to update your `PATH` if needed.
-   **Enhanced HPC & Batch Job Support**:
    -   The batch submission script (`sqlc`) is more reliable, no longer using hardcoded paths.
    -   Shell scripts are now more compatible with typical HPC environments that may only have a `python3` executable.
-   **Expanded Documentation**:
    -   The `USAGE.md` guide now includes comprehensive, exhaustive lists of currently available plotting regions, observation datasets, and supported chemical/meteorological variables.
    -   A new "Advanced Workflow" section has been added to `USAGE.md`, explaining the underlying shell script pipeline, the `param/ncvar/myvar` variable mapping system, and how to use your own data with the `qlc-py` engine.
    -   Added a note on the future integration with the GHOST database.
-   **Dependency Fix**: The `adjustText` library is now included as a core dependency.

---

## What's New in v0.3.26

This version introduces a completely new, high-performance Python processing engine and a more robust installation system.
- **New Python Engine (`qlc-py`)**: The core data processing and plotting is now handled by a powerful Python-based tool, compiled with Cython for maximum performance. This replaces much of the previous shell-script-based logic.
- **Standalone `qlc-py` Tool**: In addition to being used by the main `qlc` pipeline, `qlc-py` can be run as a standalone tool for rapid, iterative analysis using a simple JSON configuration.
- **New `cams` Installation Mode**: A dedicated installation mode for operational CAMS environments that automatically links to standard data directories.
- **Simplified and Robust Installation**: The installer now uses a consistent directory structure based in `$HOME/qlc`, with a smart two-stage symlink system to manage data-heavy directories for different modes (`test` vs. `cams`).
- **Dynamic Variable Discovery**: The shell pipeline now automatically discovers which variables to process based on the available NetCDF files, simplifying configuration.
- **Flexible Model Level Handling**: The Python engine can intelligently select the correct vertical model level for each variable or use a user-defined default.

---

## Core Features

- **Automated End-to-End Workflow**: A single `qlc` command can drive the entire pipeline: MARS data retrieval, data processing, statistical analysis, plotting, and final PDF report generation.
- **High-Performance Engine**: The core data processing logic is written in Python and compiled with Cython into native binary modules, ensuring high performance for large datasets.
- **Publication-Ready Outputs**: Automatically generates a suite of plots (time series, bias, statistics, maps) and integrates them into a final, professionally formatted PDF presentation using a LaTeX backend.
- **Flexible Installation Modes**: The `qlc-install` script supports multiple, co-existing modes:
    - `--mode test`: A standalone mode with bundled example data, perfect for new users. All data is stored locally in `$HOME/qlc_pypi/v<version>/test/`.
    - `--mode cams`: An operational mode that links to standard CAMS data directories and uses environment variables like `$SCRATCH` and `$PERM` for data storage in shared HPC environments.
    - `--mode dev`: **New in v0.4.1** - Development mode for parallel testing. Creates isolated runtime in `$HOME/qlc_dev/v<version>/dev/`.
- **Parallel Development Support**: Run PyPI (production) and development versions simultaneously without conflicts. Easy switching via conda environments or `QLC_HOME` variable.
- **Simplified Configuration**: The entire suite is controlled by a single, well-documented configuration file (`$HOME/qlc/config/qlc.conf`) where you can set paths, experiment labels, and plotting options.

---

## Quickstart

**1. Install the Package**
```bash
pip install rc-qlc
qlc --version
```

**2. Set Up the Test Environment**
This creates a local runtime environment in `$HOME/qlc_v<version>/test` and links `$HOME/qlc` to it. It includes all necessary configurations and example data.
```bash
qlc-install --mode test
```

**3. Verify Installation**
Check that QLC is properly installed:
```bash
qlc --version
qlc --help
```

**4. Run the Full Pipeline**
Navigate to the working directory and run the `qlc` command. This will process the example data (comparing any number of experiments) and generate a full PDF report in `$HOME/qlc/Presentations`.
```bash
cd $(readlink -f $HOME/qlc)

# Compare two experiments (standard)
qlc b2ro b2rn 2018-12-01 2018-12-21

# Compare three or more experiments
qlc exp1 exp2 exp3 2018-12-01 2018-12-21
```

---

## Command-Line Tools

Once installed, QLC provides the following command-line entry points:

- **`qlc`**: The main pipeline driver. Supports task-based workflows via optional `[task]` parameter
- **`qlc-py`**: Standalone Python engine for rapid analysis with JSON configuration
- **`qlc-extract-stations`**: Station metadata extraction with global urban/rural classification
- **`qlc-install`**: Installation and environment setup tool
- **`sqlc`**: Batch job submission wrapper for HPC environments

For detailed usage of each tool, see the [USAGE.md](USAGE.md) guide

---

## Prerequisites

Before running the QLC suite, please ensure the following system-level software is installed and accessible in your environment's `PATH`:

- **`pdflatex`**: Required for generating the final PDF reports. It is part of the **TeX Live** distribution.
- **`CDO` (Climate Data Operators)**: Used for processing NetCDF data.
- **`eccodes`**: The ECMWF library for decoding and encoding GRIB files.
- **`netcdf`**: The core NetCDF libraries.

On HPC systems, these tools are typically made available by loading the appropriate modules (e.g., `module load cdo`). On personal machines, they can be installed using system package managers like `apt-get` (Debian/Ubuntu), `yum` (Red Hat/CentOS), or `brew` (macOS).

---

## Installation and Configuration

### Standard Installation

QLC is installed from PyPI. After the `pip install`, you **must** run `qlc-install` to set up the necessary local directory structure.

**First-Time Installation**
```bash
pip install rc-qlc
```

**Upgrading an Existing Installation**
To ensure you have the latest version, always use the `--upgrade` flag:
```bash
pip install --upgrade rc-qlc
```

After installing, set up your desired environment:
```bash
# For a standalone test environment with example data
qlc-install --mode test

# For an operational CAMS environment
qlc-install --mode cams
```

### Installation in Restricted Environments (HPC/ATOS)

In environments where you do not have root permissions, `pip` will install packages into your local user directory. You may need to take a couple of extra steps.

**1. Update your PATH (Recommended)**
The executable scripts (`qlc`, `qlc-py`, etc.) will be placed in `$HOME/.local/bin`. Add this to your shell's `PATH` to run them directly.
```bash
# Example for bash shell
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**2. Load the Correct Python Module**
Ensure you are using a compatible Python version.
```bash
module load python3/3.10.10-01
```

**3. Install and Run**
Now you can install as normal.
```bash
pip install rc-qlc && qlc-install --mode test
```
If you chose not to update your `PATH`, you must call the installer script by its full path:
```bash
pip install rc-qlc && $HOME/.local/bin/qlc-install --mode test
```

### Where Files Are Installed

**PyPI Installation**:
- **Python Package Source**: `$HOME/.local/lib/python3.10/site-packages/qlc/`
- **Executable Scripts**: `$HOME/.local/bin/`
- **QLC Runtime Environment**: `$HOME/qlc_pypi/v<version>/<mode>`
- **Stable Symlink**: `$HOME/qlc` (points to `qlc_pypi/current/test`)

**Development Installation** (when using `pip install -e`):
- **Python Package Source**: `$HOME/.conda/envs/qlc-dev/lib/python3.10/site-packages/qlc/` (editable link)
- **Executable Scripts**: `$HOME/.conda/envs/qlc-dev/bin/`
- **QLC Runtime Environment**: `$HOME/qlc_dev/v<version>/dev`
- **Stable Symlink**: `$HOME/qlc-dev-run` (points to `qlc_dev/current/dev`)


### Configuration Structure

The primary configuration file is located at `$HOME/qlc/config/qlc.conf` (for PyPI) or `$HOME/qlc-dev-run/config/qlc.conf` (for dev). The installation process uses a two-stage symlink system to manage data directories, allowing the config file to remain simple and portable.

**PyPI Installation (test mode)**:
- `$HOME/qlc/Results` (the path in your config) → is a symlink to
- `$HOME/qlc_pypi/v<version>/test/data/Results` → which is a real directory.

**Development Installation (dev mode)**:
- `$HOME/qlc-dev-run/Results` (the path in your config) → is a symlink to
- `$HOME/qlc_dev/v<version>/dev/data/Results` → which is a real directory.

In `cams` mode, the final target is a symlink to a shared directory (e.g., `$SCRATCH/Results`), but the path in your config file remains the same.

---

## Developer Setup

**New in v0.4.1**: QLC now supports parallel PyPI and development installations with complete isolation. This allows you to test new features alongside stable releases without conflicts.

### Quick Development Setup

```bash
# 1. Clone the repository
git clone https://github.com/researchConcepts/qlc.git ~/qlc-dev
cd ~/qlc-dev

# 2. Create and activate a dedicated conda environment (use 'qlc-dev' name)
conda create -n qlc-dev python=3.10 -y
conda activate qlc-dev

# 3. Install in editable mode with development dependencies
pip install -e ".[dev]"

# 4. Set up the isolated development runtime
qlc-install --mode dev

# 5. Setup conda environment auto-switching (recommended)
bash bin/tools/setup_conda_env.sh qlc-dev

# 6. Verify installation
conda deactivate && conda activate qlc-dev
qlc --version
# Should show: Runtime: /Users/<user>/qlc-dev-run (conda-dev)
```

### Parallel PyPI and Dev Testing

With v0.4.1, you can run both versions simultaneously:

```bash
# Terminal 1: Test with PyPI version
conda deactivate
cd ~/qlc
qlc b2ro b2rn 2018-12-01 2018-12-21

# Terminal 2: Test with dev version (in parallel!)
conda activate qlc-dev
cd ~/qlc-dev-run
qlc b2ro b2rn 2018-12-01 2018-12-21

# Compare results
diff -r ~/qlc/Plots ~/qlc-dev-run/Plots
```

### Version Switching

```bash
# Method 1: Conda Environment (Automatic - Recommended)
conda deactivate          # Use PyPI version
conda activate qlc-dev    # Use dev version

# Method 2: Environment Variable (Manual)
export QLC_HOME=~/qlc          # Use PyPI
export QLC_HOME=~/qlc-dev-run  # Use dev
```

### Advanced Setup Options

For advanced development, you can use `--mode interactive` for custom configurations:
```bash
qlc-install --mode interactive --config /path/to/your/custom_qlc.conf
```

### Development Utilities

QLC includes several development and debugging utilities in the `bin/tools/` directory:

- **`setup_conda_env.sh`**: **New in v0.4.1** - Setup conda environment auto-switching for dev mode
- **`qlc-extract-stations-examples.sh`**: Ready-to-use examples for station extraction workflows
- **`qlc-inspect-evaluator.sh`**: Inspect evaltools evaluator pickle files with detailed diagnostics
- **`qlc_dev_env.sh`**: Development environment helper with utility functions:
  - `qlc-rebuild`: Rebuild the development package
  - `qlc-test-extract`: Test station extraction
  - `qlc-find-evaluators`: Find evaluator files
  - `qlc-inspect-all`: Inspect all evaluators
- **`qlc_test_config_loading.sh`**: Test configuration file loading and inheritance

To use the development helpers:
```bash
source ~/qlc-dev-run/bin/tools/qlc_dev_env.sh
qlc-rebuild
qlc-test-extract
```

For complete developer documentation, see:
- **INSTALL_DEV.md**: Detailed development installation guide
- **bin/tools/README.md**: Complete documentation of development utilities

## Advanced Topics

### Installing Optional Packages

QLC supports several optional packages for extended functionality.

#### PyFerret for Global Plots

The `qlc_C5.sh` script, which generates global map plots, requires the `pyferret` library.

-   **To install with `pyferret` support:**
    ```bash
    pip install "rc-qlc[ferret]"
    ```
-   **If you do not need these plots**, you can either skip the `pyferret` installation or, if it's already installed, disable the script by commenting out `"C5"` in the `SUBSCRIPT_NAMES` array in your `$HOME/qlc/config/qlc.conf` file.
-   **For HPC environments**, `pyferret` is often available as a module that can be loaded (e.g., `module load ferret/7.6.3`).

#### Evaltools for Advanced Statistical Plots

The evaltools integration requires the [evaltools package from Météo-France](https://opensource.umr-cnrm.fr/projects/evaltools/wiki). This enables a comprehensive suite of 15+ statistical and comparative plot types.

**Installation** (manual setup required):

Download and install evaltools v1.0.9 from the official repository:

```bash
mkdir -p ~/download_evaltools && cd ~/download_evaltools
wget https://redmine.umr-cnrm.fr/attachments/download/5300/evaltools_v1.0.9.zip
wget https://redmine.umr-cnrm.fr/attachments/download/4014/simple_example_v1.0.6.zip
wget https://redmine.umr-cnrm.fr/attachments/download/5298/documentation_v1.0.9.zip
unzip evaltools_v1.0.9.zip
unzip simple_example_v1.0.6.zip
unzip documentation_v1.0.9.zip -d documentation_v1.0.9

# Create conda environment
cat > environment.yml <<EOF
name: evaltools
channels:
  - conda-forge
dependencies:
  - pip=20.0.2
  - python=3.8
  - shapely==1.8.0
  - cartopy=0.20.2
  - cython=0.29.32
  - numpy=1.22.2
  - scipy=1.9.1
  - matplotlib=3.5.1
  - pandas=1.3.5
  - packaging
  - pyyaml=6.0
  - netCDF4==1.5.8
  - pip:
    - ./evaltools_1.0.9
variables:
  PYTHONNOUSERSITE: True
EOF

conda deactivate
conda env create -f environment.yml
conda env update -f environment.yml
conda activate evaltools

# View documentation
open documentation_v1.0.9/index.html
```

**Note:** The evaltools conda environment name should match the `EVALTOOLS_CONDA_ENV` setting in `~/qlc/config/evaltools/qlc_evaltools.conf` (default: `"evaltools"`).

**Resources**:
- **Evaltools Wiki**: https://opensource.umr-cnrm.fr/projects/evaltools/wiki
- **Local Documentation**: `~/download_evaltools/documentation_v1.0.9/index.html` (after installation)
- **Examples**: `~/download_evaltools/simple_example_v1.0.6/` (after installation)

### Manual PyFerret Installation for macOS / Apple Silicon

If you are using a Mac with Apple Silicon (M1/M2/M3) or if the standard installation fails, `pyferret` may require a manual setup using a dedicated `conda` environment. `pip` installations are not recommended for this package on macOS as they may not work correctly with the ARM architecture.

The most reliable method is to use `conda` with the Rosetta 2 translation layer.

**1. (If needed) Install Conda**
If you do not have `conda` installed, we recommend **Miniforge**, which is a minimal installer that is optimized for Apple Silicon and includes the high-performance `mamba` package manager.
```bash
# Download and run the installer for Apple Silicon
curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh"
bash Miniforge3-MacOSX-arm64.sh
# Follow the prompts and restart your terminal after installation
```

**2. Create a Dedicated x86_64 Environment for PyFerret**
This command creates a new `conda` environment named `pyferret_env` and installs the Intel (`x86_64`) version of `pyferret`, which will run seamlessly on Apple Silicon via Rosetta 2. It also pins `numpy` to a version older than 2.0 to ensure compatibility.

```bash
CONDA_SUBDIR=osx-64 conda create -n pyferret_env -c conda-forge pyferret ferret_datasets "numpy<2" --yes
```

**3. Configure QLC to Use the New Environment**
The QLC scripts need to know where to find this new `pyferret` installation. You can achieve this by modifying the `qlc_C5.sh` script to activate the environment.

Open the file `$HOME/qlc/bin/qlc_C5.sh` and add the following lines near the top, after `source $FUNCTIONS`:

```bash
# ... after 'source $FUNCTIONS'
# Activate the dedicated conda environment for pyferret
if [ -f "$HOME/miniforge3/bin/activate" ]; then
    . "$HOME/miniforge3/bin/activate"
    conda activate pyferret_env
fi
# ... rest of the script
```
*Note: The path to the activate script may differ if you installed Anaconda/Miniforge in a custom location.*

### MARS Data Retrieval
The `qlc_A1.sh` script is responsible for retrieving data from the ECMWF MARS archive. It uses a mapping system to associate the experiment prefix with a MARS `class`. 

By default, the script is configured for `nl` (Netherlands), `be` (Belgium), and `rd` (Research Department) experiments. If you are working with data from other classes (e.g., `fr` for France, `de` for Germany), you will need to manually edit `$HOME/qlc/bin/qlc_A1.sh` and uncomment / edit the corresponding `XCLASS` line to ensure data is retrieved correctly.

---

## Troubleshooting

### Pillow/PIL ImportError on macOS (libtiff Library Missing)

**Symptom**: You see an error like:
```
ImportError: dlopen(...PIL/_imaging.cpython-310-darwin.so, 0x0002): 
Library not loaded: /opt/homebrew/opt/libtiff/lib/libtiff.5.dylib
```

**Root Cause**: This occurs when Pillow (PIL) binary wheels were built against a specific version of `libtiff` that doesn't match your system's installed version, or when system libraries are missing. This is common on macOS after Homebrew updates or fresh installations.

**Solution 1: Install/Update System Libraries** (Recommended)
```bash
# Install libtiff via Homebrew
brew install libtiff

# If libtiff is already installed but a different version, create a symlink
# First check what version you have
ls -la /opt/homebrew/opt/libtiff/lib/

# If you have libtiff.6.dylib but Pillow needs libtiff.5.dylib:
cd /opt/homebrew/opt/libtiff/lib/
ln -s libtiff.6.dylib libtiff.5.dylib
```

**Solution 2: Reinstall Pillow** (Alternative)
```bash
# Reinstall Pillow to rebuild against your current system libraries
pip uninstall Pillow -y
pip install --no-cache-dir --force-reinstall Pillow
```

**Solution 3: Use Conda Environment** (Most Reliable for macOS)
```bash
# Create a conda environment with all dependencies
conda create -n qlc-user python=3.10 -y
conda activate qlc-user
conda install -c conda-forge matplotlib pillow libtiff -y
pip install rc-qlc
qlc-install --mode test
```

**Verification**:
```bash
python -c "from PIL import Image; print('Pillow OK')"
```

### macOS "Permission Denied" or Quarantine Issues

On macOS, the Gatekeeper security feature may "quarantine" files, including shell scripts that have been downloaded or modified. This can prevent them from being executed, sometimes with a "Permission Denied" error, even if the file has the correct execute permissions (`+x`).

This is most likely to occur if you manually edit the `qlc` shell scripts (`.sh` files) directly in their `site-packages` installation directory.

To resolve this, you can manually remove the quarantine attribute from the script directory using the `xattr` command in your terminal.

1.  **First, find the exact location of the `qlc` package:**
    ```bash
    pip show rc-qlc
    ```
    Look for the `Location:` line in the output. This is your `site-packages` path.

2.  **Then, use the `xattr` command to remove the quarantine flag:**
    Use the path from the previous step to build the full path to the `qlc/sh` directory.
    ```bash
    # The path will depend on your Python installation. Use the location from 'pip show'.
    xattr -rd com.apple.quarantine /path/to/your/site-packages/qlc/sh/
    ```

This should immediately resolve the execution issues.

---

## License

© ResearchConcepts io GmbH  
Contact: [contact@researchconcepts.io](mailto:contact@researchconcepts.io)  
MIT-compatible, source-restricted under private release until publication.

---
