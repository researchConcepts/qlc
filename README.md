# QLC - Quick Look Content

**An Automated Model-Observation Comparison Suite Optimized for CAMS**

> v1.0.2: Major feature release — 25 observation networks (incl. Brazilian networks), 7,855 variables, AERONET AOD mapping, and enhanced workflows.

[![PyPI](https://img.shields.io/pypi/v/rc-qlc?color=blue)](https://pypi.org/project/rc-qlc/)

---

## Overview

QLC (Quick Look Content) is a powerful command-line suite for automated model-observation comparisons, designed for climate and air quality model evaluation. Optimized for CAMS (Copernicus Atmospheric Monitoring Service) datasets, it streamlines the entire workflow from data retrieval to publication-quality reports.

**Key Features:**
- 7,855 accessible variables (IFS parameters + GHOST networks + CSV observations)
- 25 observation networks (EBAS, AirNow, AERONET, Brazil networks, GHOST harmonized, CSV-based, and more)
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
qlc exp1 exp2 2018-12-01 2018-12-21 test
```

- batch submission (same options as qlc)
```bash
sqlc exp1 exp2 2018-12-01 2018-12-21 test
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
ls -lrth ~/qlc/Plots/exp1-exp2*
```

- Reports produced (one PDF per variable, region):
```bash
ls -lrth ~/qlc/Presentations
```

---

## What's New in v1.0.2

### Major Enhancements

**Observation Network Expansion (25 networks)**
- Three new Brazilian networks: INMET meteorological (620 stations), State AQ (483 stations), São Paulo CETESB (72 stations)
- AERONET AOD mapping: `od550aero → aod550` for AERONET Level 1.5 and Level 2.0
- Central network registry (`obs_networks.conf`) defines all 25 networks in one place
- All region definitions centralised in `qlc.conf` — no per-workflow repetition

**CLI Overhaul**
- Named arguments: `--myvar=`, `--network=`, `--region=`, `--station_file=`, `--exp_labels=`, `--param=`, `--user=`
- `--network=` (station collection) and `--region=` (map extent) are now separate options
- Per-experiment MARS class: `-class=nl,nl` maps one class to each experiment
- `--obs-only` and `--mod-only` produce distinct output directories

**Variable Mapping System**
- Finalized pipe-format spec: `userVAR|modVAR[,op,val]|obsVAR[,op,val]|targetUNIT[,unitFAC]`
- Arithmetic transforms (`*`, `/`, `+`, `-`) applied independently on model or obs side at load time
- `unitFAC` field as an alternative to automatic unit conversion — useful for variables not in qlc's built-in unit table, custom model diagnostics, or quick scaling tests
- A single `--myvar=` CLI override applies the chosen spec across all active regions in one run, with no workflow file changes required
- `qlc-vars --exact` flag for precise IFS variable lookup

**Plot and Analysis Fixes**
- K-guard for log scale: temperature in °C automatically converted to K before log computation
- PyFerret percentage difference plots (`DIFF_MODE=percent`) with configurable white zone
- Degenerate zero-range diff plot guard; additive K↔°C differences handled correctly
- South America map projection corrected (Lambert Conformal center and standard parallels)

### Complete Changelog

For detailed release notes, see: [docs.researchconcepts.io/qlc/latest/reference/changelog](https://docs.researchconcepts.io/qlc/latest/reference/changelog)

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
qlc exp1      2018-12-01 2018-12-21 test # one experiment vs observations
qlc exp1 exp2 2018-12-01 2018-12-21 test # two or more experiments vs observations

# Examples (AIFS data available from June 2025):
qlc aifs1 aifs2 2025-11-01 2025-11-07 mars # only data retrieval (no processing)
qlc aifs1 aifs2 2025-11-01 2025-11-07 aifs # workflows support multi-region processing
qlc aifs1 aifs2 2025-11-01 2025-11-07 aifs --station_file=~/qlc/config/station_locations/ver0d_airnow_stations-test.csv
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
qlc aifs1 aifs2 2025-11-01 2025-11-07 aifs --mod-only

# Collocation (default - both model and observations)
qlc aifs1 aifs2 2025-11-01 2025-11-07 aifs
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
- Python 3.10 or 3.11 (Python 3.10 recommended; Python 3.12+ is not yet supported)

**Dependencies:**
- Core dependencies automatically installed via pip
- Optional tools: evaltools, pyferret, cfgrib (installed automatically / reinstall separately if neeed)

---

## Configuration

QLC uses workflow-based configurations stored in `~/qlc/config/workflows/`:

**Available Workflows:**
- `mars`      - MARS retrieval only (no conversion or analysis)
- `qpy`       - Station collocation and analysis via qlc-py (QPY chain)
- `aifs`      - AI-Integrated Forecasting System (AIFS), e.g., AI vs o-suite analysis
- `eac5`      - ECMWF Atmospheric Composition (EAC5), multi-region/species batch processing
- `evaltools` - Compute and plot model scores (based on Météo-France software)
- `pyferret`  - 3D quick-look plots (model comparison based on NOAA/PMEL software)
- `test`      - Testing and development (and template for user-specific workflows)

Example workflow configuration at `~/qlc/config/workflows/aifs/qlc_aifs.conf`.

For detailed configuration options, see: [docs.researchconcepts.io/qlc/latest/user-guide/workflows/](https://docs.researchconcepts.io/qlc/latest/user-guide/workflows/)

---

## Examples

### Using Auto-Generated JSON Configs

QLC automatically generates JSON configuration files that can be reused with `qlc-py` for quick parameter adjustments:

```bash
# Run initial analysis
qlc aifs1 aifs2 2025-11-01 2025-11-03 aifs

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

MIT License - Copyright (c) 2018-2026 ResearchConcepts io GmbH

See [LICENSE](LICENSE) file for details.

Third-party licenses: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)

---

## Acknowledgments

Developed by ResearchConcepts io GmbH for the atmospheric science community, supported through CAMS2_35_bis_KNMI [https://atmosphere.copernicus.eu/developments-reactive-gases-and-aerosol-global-system-0](https://atmosphere.copernicus.eu/developments-reactive-gases-and-aerosol-global-system-0).

Optimized for use with CAMS (Copernicus Atmospheric Monitoring Service) and ECMWF data.

---

**For complete documentation, tutorials, and examples, visit:** [docs.researchconcepts.io/qlc/latest](https://docs.researchconcepts.io/qlc/latest)
