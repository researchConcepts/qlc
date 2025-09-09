# Quick Look Content (QLC): An Automated Model–Observation Comparison Suite

**Quick Look Content (QLC)** is a powerful, command-line driven suite for model–observation comparisons, designed to automate the evaluation of climate and air quality model data. It is optimized for use with CAMS (Cop Copernicus Atmospheric Monitoring Service) datasets but is flexible enough for general use cases.

The suite streamlines the entire post-processing workflow, from data retrieval and collocation to statistical analysis and the generation of publication-quality figures and reports.

| Package | Status |
|---------|--------|
| [rc-qlc on PyPI](https://pypi.org/project/rc-qlc/) | ![PyPI](https://img.shields.io/pypi/v/rc-qlc?color=blue) |

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
    - `--mode test`: A standalone mode with bundled example data, perfect for new users. All data is stored locally in `$HOME/qlc_v<version>/test/`.
    - `--mode cams`: An operational mode that links to standard CAMS data directories and uses environment variables like `$SCRATCH` and `$PERM` for data storage in shared HPC environments.
- **Simplified Configuration**: The entire suite is controlled by a single, well-documented configuration file (`$HOME/qlc/config/qlc.conf`) where you can set paths, experiment labels, and plotting options.

---

## Quickstart

**1. Install the Package**
```bash
pip install rc-qlc
```

**2. Set Up the Test Environment**
This creates a local runtime environment in `$HOME/qlc_v<version>/test` and links `$HOME/qlc` to it. It includes all necessary configurations and example data.
```bash
qlc-install --mode test
```

**3. Run the Full Pipeline**
Navigate to the working directory and run the `qlc` command. This will process the example data (comparing experiments `b2ro` and `b2rn`) and generate a full PDF report in `$HOME/qlc/Presentations`.
```bash
cd $(readlink -f $HOME/qlc)
qlc b2ro b2rn 2018-12-01 2018-12-21
```

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
- **Python Package Source**: `$HOME/.local/lib/python3.10/site-packages/qlc/`
- **Executable Scripts**: `$HOME/.local/bin/`
- **QLC Runtime Environment**: `$HOME/qlc_v<version>/<mode>`
- **Stable Symlink**: `$HOME/qlc` (points to the latest installed runtime environment)


### Configuration Structure

The primary configuration file is located at `$HOME/qlc/config/qlc.conf`. The installation process uses a two-stage symlink system to manage data directories, allowing the config file to remain simple and portable.

For example, in `test` mode:
- `$HOME/qlc/Results` (the path in your config) -> is a symlink to
- `$HOME/qlc_v<version>/test/Results` -> which is a symlink to
- `$HOME/qlc_v<version>/test/data/Results` -> which is a real directory.

In `cams` mode, the final target is a symlink to a shared directory (e.g., `$SCRATCH/Results`), but the path in your config file remains the same.

---

## Developer Setup

To work on the `qlc` source code, clone the repository and install it in "editable" mode.

```bash
# 1. Clone the repository
git clone https://github.com/researchConcepts/qlc.git
cd qlc

# 2. (Recommended) Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# 3. Install in editable mode (this compiles the Cython modules)
pip install -e .

# 4. Set up the test environment for development
qlc-install --mode test
```

For advanced development, you can also use `--mode interactive`, which requires you to provide a path to a custom configuration file using the `--config` flag. This is useful for testing with non-standard setups.
```bash
qlc-install --mode interactive --config /path/to/your/custom_qlc.conf
```

## Advanced Topics

### Installing PyFerret for Global Plots

The `qlc_C5.sh` script, which generates global map plots, requires the `pyferret` library. This is an optional dependency.

-   **To install with `pyferret` support:**
    ```bash
    pip install "rc-qlc[ferret]"
    ```
-   **If you do not need these plots**, you can either skip the `pyferret` installation or, if it's already installed, disable the script by commenting out `"C5"` in the `SUBSCRIPT_NAMES` array in your `$HOME/qlc/config/qlc.conf` file.
-   **For HPC environments**, `pyferret` is often available as a module that can be loaded (e.g., `module load ferret/7.6.3`).

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

Open the file `$HOME/qlc/sh/qlc_C5.sh` and add the following lines near the top, after `source $FUNCTIONS`:

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

By default, the script is configured for `nl` (Netherlands), `be` (Belgium), and `rd` (Research Department) experiments. If you are working with data from other classes (e.g., `fr` for France, `de` for Germany), you will need to manually edit `$HOME/qlc/sh/qlc_A1.sh` and uncomment / edit the corresponding `XCLASS` line to ensure data is retrieved correctly.

---

## Troubleshooting

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
