# Quick Look Content (QLC): An Automated Model–Observation Comparison Suite

**Quick Look Content (QLC)** is a powerful, command-line driven suite for model–observation comparisons, designed to automate the evaluation of climate and air quality model data. It is optimized for use with CAMS (Cop Copernicus Atmospheric Monitoring Service) datasets but is flexible enough for general use cases.

The suite streamlines the entire post-processing workflow, from data retrieval and collocation to statistical analysis and the generation of publication-quality figures and reports.

| Package | Status |
|---------|--------|
| [rc-qlc on PyPI](https://pypi.org/project/rc-qlc/) | ![PyPI](https://img.shields.io/pypi/v/rc-qlc?color=blue) |

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

## Installation and Configuration

### Standard Installation

QLC is installed from PyPI. After the `pip install`, you **must** run `qlc-install` to set up the necessary local directory structure.

```bash
# For a standalone test environment with example data
pip install rc-qlc && qlc-install --mode test

# For an operational CAMS environment
pip install rc-qlc && qlc-install --mode cams
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

---

## License

© ResearchConcepts io GmbH  
Contact: [contact@researchconcepts.io](mailto:contact@researchconcepts.io)  
MIT-compatible, source-restricted under private release until publication.