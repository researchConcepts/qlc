# QLC - Quick Look Content

**An Automated Model-Observation Comparison Suite Optimized for CAMS**

> BETA RELEASE v1.0.1-beta: Major feature release with GHOST integration, 7,855 accessible variables, and enhanced workflows.

[![PyPI](https://img.shields.io/pypi/v/rc-qlc?color=blue)](https://pypi.org/project/rc-qlc/)

---

## Overview

QLC (Quick Look Content) is a powerful command-line suite for automated model-observation comparisons, designed for climate and air quality model evaluation. Optimized for CAMS (Copernicus Atmospheric Monitoring Service) datasets, it streamlines the entire workflow from data retrieval to publication-quality reports.

**Key Features:**
- 7,855 accessible variables (IFS parameters + GHOST networks + CSV observations)
- 16 observation networks (EBAS, AirNow, GHOST harmonized, CSV-based, and more)
- Automated MARS data retrieval and processing
- Statistical analysis with comprehensive metrics
- Publication-quality maps, time series, and reports
- Native GRIB support with forecast step preservation
- One-command installation with automatic tool setup

---

## Installation

See [qlc/doc/QuickStart.md](qlc/doc/QuickStart.md). For complete installation instructions, see [INSTALL.md](INSTALL.md).

**Quick Install:**

One-Command Installation (using qlc_install.sh)

The `qlc_install.sh` script performs four tasks:
- a) Creates a QLC virtual environment (`~/venv/qlc`)
- b) Installs QLC from latest PyPI release (`pip install rc-qlc`)
- c) Installs all required tools (cartopy data, evaltools, etc.)
- d) Sets up QLC runtime environment with links to shared directories (`$SCRATCH`, `$HPCPERM`, `$PERM`)

```bash
curl -sSL https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh | bash -s -- --mode test --tools essential
```

**Quick Start:**

Activate QLC environment

```bash
source ~/venv/qlc/bin/activate
```

Verify installation

```bash
cd ~/qlc/run
pwd -P
qlc --version
qlc --help
```

Run test analysis (example data from 01-21 December 2018)

- one or more experiments using workflow 'test' configuration
```bash
qlc b2ro b2rn 2018-12-01 2018-12-21 test
```

- batch submission (same options as qlc)
```bash
sqlc b2ro b2rn 2018-12-01 2018-12-21 test
```

View results

- GRIB data downloaded from MARS:
```bash
ls -lrth ~/qlc/Results
```

- NetCDF data processed (converted from GRIB):
```bash
ls -lrth ~/qlc/Analysis
```

- Plot results for active workflow:
```bash
ls -lrth ~/qlc/Plots/b2ro-b2rn*
```

- Reports produced (one PDF per variable, region):
```bash
ls -lrth ~/qlc/Presentations
```

---

## What's New in v1.0.1-beta

### Major Enhancements

**GHOST Integration & Variable System**
- 7,855 accessible variables (vs ~50 previously)
- Table-driven variable mapping system
- 7 GHOST networks integrated (282 harmonized variables)
- Variable discovery CLI: `qlc-vars search`, `qlc-vars info`, `qlc-vars list`

**Simplified Variable Syntax**
```bash
# Before (v0.4.x):
MARS_RETRIEVALS=("sfc_O3,203.210,Ozone mass mixing ratio")

# Now (v1.0.1):
MARS_RETRIEVALS=("O3,go3")  # Auto-resolves to correct parameter using IFS variable table and model type surface (default)
```

**Native GRIB Support**
- Read GRIB files directly without conversion (in addition to netCDF/csv support)
- Supports forecast step information (forecats plots currently not yet implemented)
- Automatic variable mapping (IFS only and model observation variable matching)

**Performance Improvements**
- 95% faster regional map rendering
- Optimized contour processing with region-aware filtering

**Enhanced CLI**
- Named arguments, e.g.: `--exp_ids`, `--start_date`, `--end_date`
- Mode flags, e.g.: `--obs-only`, `--mod-only`
- Flexible configuration overrides (see complete documentation)

### Complete Changelog

For detailed release notes, see: [docs.researchconcepts.io/qlc/latest/reference/whatsnew](https://docs.researchconcepts.io/qlc/latest/reference/whatsnew/)

---

## Documentation

**Complete documentation available at:** [docs.researchconcepts.io/qlc/latest](https://docs.researchconcepts.io/qlc/latest)

### Getting Started
- [Installation Guide](https://docs.researchconcepts.io/qlc/latest/getting-started/installation/)
- [Quick Start Tutorial](https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/)
- [First Analysis](https://docs.researchconcepts.io/qlc/latest/getting-started/first-analysis/)

### User Guide
- [CLI Reference](https://docs.researchconcepts.io/qlc/latest/user-guide/cli-reference/)
- [Variable System](https://docs.researchconcepts.io/qlc/latest/user-guide/variable-system/)
- [Workflow Configuration](https://docs.researchconcepts.io/qlc/latest/user-guide/workflows/)
- [Complete Usage Guide](https://docs.researchconcepts.io/qlc/latest/user-guide/usage/)

### Advanced Topics
- [GHOST Integration](https://docs.researchconcepts.io/qlc/latest/advanced/ghost-integration/)
- [GRIB Support](https://docs.researchconcepts.io/qlc/latest/advanced/grib-support/)
- [Evaltools Integration](https://docs.researchconcepts.io/qlc/latest/advanced/evaltools/)
- [Performance Optimization](https://docs.researchconcepts.io/qlc/latest/advanced/performance/)

### Developer Guide
- [Building from Source](https://docs.researchconcepts.io/qlc/latest/developer/building/)
- [Contributing](https://docs.researchconcepts.io/qlc/latest/developer/contributing/)

---

## Basic Usage

### Command Syntax

```bash
# Standard workflow
qlc <exp1> <expN> <start_date> <end_date> <workflow>

# Run test analysis (example data from 01-21 December 2018)
qlc b2ro      2018-12-01 2018-12-21 test # one experiment vs observations
qlc b2ro b2rn 2018-12-01 2018-12-21 test # two or more experiments vs observations

# Examples (AIFS data available from June 2025):
qlc 9191 0001 2025-11-01 2025-11-07 mars # only data retrieval (no processing)
qlc 9191 0001 2025-11-01 2025-11-07 aifs # workflows support multi-region processing
qlc 9191 0001 2025-11-01 2025-11-07 aifs --station_selection=~/qlc/config/station_locations/AirNow_stations-test.csv  
```

### Variable Discovery

```bash
# Search for variables
qlc-vars search ozone

# List available sources
qlc-vars list --sources

# Get variable details
qlc-vars info O3

# Validate configuration
qlc-vars validate ~/qlc/config/workflows/aifs/qlc_aifs.conf
```

### Processing Modes

```bash
# Observation-only (no model data)
qlc None None 2025-11-01 2025-11-07 aifs --obs-only

# Model-only (no observations)
qlc 9191 0001 2025-11-01 2025-11-07 aifs --mod-only

# Collocation (default - both model and observations)
qlc 9191 0001 2025-11-01 2025-11-07 aifs
```

### Help Commands

All QLC tools have built-in help:

```bash
qlc -h                     # Main driver help
sqlc -h                    # Batch job help
qlc-py -h                  # Python standalone help
qlc-vars -h                # Variable discovery help
qlc-install -h             # Installation help
qlc-install-tools -h       # Optional tools help
```

---

## System Requirements

**Operating Systems:**
- macOS (Apple Silicon & Intel)
- Linux (Ubuntu 20.04+, RHEL 8+)
- Windows (via WSL2)
- HPC systems (ATOS/ECMWF, SLURM clusters)

**Python:**
- Python 3.10 or later (Python 3.10 recommended/tested)

**Dependencies:**
- Core dependencies automatically installed via pip
- Optional tools: evaltools, pyferret, cfgrib (installed automatically / reinstall separately if neeed)

---

## Configuration

QLC uses workflow-based configurations stored in `~/qlc/config/workflows/`:

**Available Workflows:**
- `mars`      - Generic MARS retrieval and analysis (no data processing)
- `aifs`      - AI-Integrated Forecasting System (AIFS), e.g., AI vs o-suite analyis
- `eac5`      - ECMWF Atmospheric Composition (EAC5), multi-region/species batch processing
- `evaltools` - Compute and plot model scores (based on Meteo France software)
- `pyferret`  - 3D quick look plots (model comparison based on NOAA/PMEL software)
- `test`      - Testing and development (and template for user specfic workflows)

Example workflow configuration at `~/qlc/config/workflows/aifs/qlc_aifs.conf`.

For detailed configuration options, see: [docs.researchconcepts.io/qlc/latest/user-guide/workflows/](https://docs.researchconcepts.io/qlc/latest/user-guide/workflows/)

---

## Examples

### Using Auto-Generated JSON Configs

QLC automatically generates JSON configuration files that can be reused with `qlc-py` for quick parameter adjustments:

```bash
# Run initial analysis
qlc 9191 0001 2025-11-01 2025-11-03 aifs

# Reuse the generated config with modifications
qlc-py --config=~/qlc/Plots/9191_20251101-20251103/US_AIRNOW/qlc_D1-ANAL_config.json
```

The JSON config allows quick experimentation with different qlc-py options (which is used in various workflows):
- `show_stations`: Individual station plots
- `use_log_scale`: Logarithmic scale for maps/timeseries
- `enable_diff_plots`: Difference plots in collocation mode
- `plot_type`: Map types (map, burden, zonal, meridional, scatter, taylor)
- `time_average`: Time averaging (raw, hourly, 3hourly, daily, monthly)
- `plot_region`: Different regions (Globe, US, EU, Asia)
- `map_projection`: Global map projections (Robinson, PlateCarree, EqualEarth)
- `publication_style`: Higher quality plots (300 DPI)
- `plot_dpi`: Explicit DPI control (100=fast, 150=balanced, 300+=publication)
- `map_colormap`: Map colormap (turbo, viridis, plasma)
- And many more options

---

## Troubleshooting

### Common Issues

**QLC commands not found After Installation**
```bash
# Activate virtual environment (see [INSTALL.md](INSTALL.md) for details)
source ~/venv/qlc/bin/activate
```

**Import Errors After Installation**
```bash
# Fix dependency compatibility
qlc-fix-dependencies
```

**Evaltools NumPy 2.x Issues**
```bash
# Patch evaltools for NumPy 2.x
qlc-fix-evaltools
```

**Missing Natural Earth Data**
```bash
# Download cartography data
qlc-install-extras --cartopy_downloads
```

### Get Help

- **Documentation:** [docs.researchconcepts.io/qlc/latest](https://docs.researchconcepts.io/qlc/latest)
- **GitHub Issues:** [github.com/researchConcepts/qlc/issues](https://github.com/researchConcepts/qlc/issues)
- **Contact:** qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>

---

## License

MIT License - Copyright (c) 2018-2025 ResearchConcepts io GmbH

See [LICENSE](LICENSE) file for details.

Third-party licenses: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)

---

## Acknowledgments

Developed by ResearchConcepts io GmbH for the atmospheric science community, supported through CAMS2_35_bis_KNMI [https://atmosphere.copernicus.eu/developments-reactive-gases-and-aerosol-global-system-0](https://atmosphere.copernicus.eu/developments-reactive-gases-and-aerosol-global-system-0).

Optimized for use with CAMS (Copernicus Atmospheric Monitoring Service) and ECMWF data.

---

**For complete documentation, tutorials, and examples, visit:** [docs.researchconcepts.io/qlc/latest](https://docs.researchconcepts.io/qlc/latest)
