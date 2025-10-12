# QLC Usage Guide

> **⚠️ BETA RELEASE - v0.4.1**: This major release is currently under development and requires further testing. While the core functionality has been validated, some edge cases and platform-specific issues may exist. Please report any issues you encounter.

This guide provides detailed instructions on how to use the QLC command-line tools and configure the workflow.

---

## Known Issues and Workarounds

### Threading with HDF5/NetCDF Files

On some systems (particularly macOS), you may encounter segmentation faults when using multi-threaded file loading. This is due to the HDF5 library's thread-safety limitations.

**Workaround**: Set `"n_threads": "1"` in your configuration file:

```json
{
  "n_threads": "1",
  "multiprocessing": false
}
```

---

## Installed CLI Tools

Once installed, QLC provides the following command-line entry points:

- **`qlc`**: The main driver. Runs the full shell-based QLC pipeline, which now integrates the `qlc-py` engine for all data processing and plotting. Use this for standard, end-to-end model evaluation runs.
- **`qlc-py`**: The standalone Python engine. Can be run directly with a JSON configuration file for rapid, iterative analysis without re-running the entire shell pipeline.
- **`qlc-extract-stations`**: Station extraction and filtering utility. Extracts station metadata from observation datasets with global urban/rural classification support.
- **`qlc-install`**: Installation and environment setup tool. Creates the QLC runtime environment in test or cams mode.
- **`sqlc`**: A wrapper to submit a `qlc` run as a batch job to a scheduling system like SLURM.

---

## Running QLC

After installation (`qlc-install --mode test` or `--mode cams`), you can immediately run the main drivers. It's recommended to run `qlc` from within the active installation directory.

```bash
# Navigate to the active QLC directory
cd $(readlink -f $HOME/qlc)
```

### `qlc`: The Main Pipeline

This is the standard workflow. It performs data retrieval (if needed), processes model and observation data, and generates all plots and a final PDF report.

**Syntax**
```
qlc <exp1> [exp2 ...] <start_date> <end_date> [task|mars]
qlc --version
qlc --help
```

**Parameters**
- `<exp1> [exp2 ...]`: One or more experiment identifiers to compare
- `<start_date>`, `<end_date>`: Date range in YYYY-MM-DD format
- `[task]`: Optional task name (e.g., `qpy`, `evaltools`) - uses task-specific config from `qlc/config/<task>/`
- `[mars]`: Optional flag to retrieve data from MARS archive first
- `--version`: Display version information
- `--help`: Display help message with usage instructions

**Examples**
```bash
# Standard workflow with two experiments
qlc b2ro b2rn 2018-12-01 2018-12-21

# Compare three or more experiments
qlc exp1 exp2 exp3 2018-12-01 2018-12-21
qlc exp1 exp2 exp3 exp4 2018-12-01 2018-12-21

# Run with task-specific configuration for qlc-py only
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
qlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy

# Run with evaltools integration for advanced statistical plots
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools

# Retrieve data from MARS first, then process
qlc exp1 exp2 exp3 2018-12-01 2018-12-21 mars

# Run without options to see the help message
qlc
```

**Typical Two-Step Workflow**
For the most comprehensive analysis, run both qlc-py and evaltools:
```bash
cd ~/qlc/run

# Step 1: Create qlc-py collocation and standard plots (supports multiple experiments)
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
qlc exp1 exp2 exp3 2018-12-01 2018-12-21 qpy

# Step 2: Create evaltools statistical plots (uses collocation from step 1)
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools
qlc exp1 exp2 exp3 2018-12-01 2018-12-21 evaltools
```

---

## Multi-Region Analysis (v0.4.1+)

**New in v0.4.1**: Process multiple geographical regions and observation networks in a single workflow.

### Overview

Multi-region analysis allows you to:
- Compare model performance across different continents (Europe, US, Asia)
- Use different observation networks per region (EBAS, CASTNET, AMoN, AirNow, China AQ)
- Optimize settings per region (variables, search radius, MARS retrievals)
- Generate combined reports with all regions

### Enabling Multi-Region Mode

Edit `qlc/config/qpy/qlc_qpy.conf`:

```bash
# Enable multi-region processing
MULTI_REGION_MODE=true

# Define which regions to process
ACTIVE_REGIONS=("EU" "US_CASTNET" "US_AMON")
```

### Region Configuration

Each region requires these settings (replace `{CODE}` with your region identifier):

```bash
REGION_{CODE}_NAME="RegionName"              # Display name
REGION_{CODE}_OBS_PATH="path/to/obs/data"    # Observation data directory
REGION_{CODE}_OBS_DATASET_TYPE="dataset"     # e.g., ebas_daily, castnet, AMoN
REGION_{CODE}_OBS_DATASET_VERSION="latest"   # Dataset version
REGION_{CODE}_STATION_FILE="stations.csv"    # Station locations
REGION_{CODE}_PLOT_REGION="PlotRegion"       # Region for qlc-py (EU, US, Asia)
REGION_{CODE}_VARIABLES="var1,var2"          # Variables to process
```

**Optional overrides**:
```bash
REGION_{CODE}_MARS_RETRIEVALS=("B1_pl" "C1_sfc")     # Override MARS retrievals
REGION_{CODE}_STATION_RADIUS_DEG=1.0                 # Override search radius
```

### Example: Multi-Region NH3/NH4 Analysis

```bash
# Global settings
MULTI_REGION_MODE=true
ACTIVE_REGIONS=("EU" "US_CASTNET" "US_AMON")
MARS_RETRIEVALS=("B1_pl" "C1_sfc")  # NH3 + NH4_as globally

# Europe: EBAS daily, both variables
REGION_EU_NAME="EU"
REGION_EU_OBS_DATASET_TYPE="ebas_daily"
REGION_EU_STATION_FILE="${QLC_HOME}/config/qpy/csv/Ebas_station-locations.csv"
REGION_EU_PLOT_REGION="EU"
REGION_EU_VARIABLES="NH3,NH4_as"
REGION_EU_STATION_RADIUS_DEG=0.5  # Dense network

# US CASTNET: Weekly aerosols (no NH3)
REGION_US_CASTNET_NAME="US_CASTNET"
REGION_US_CASTNET_OBS_DATASET_TYPE="castnet"
REGION_US_CASTNET_STATION_FILE="${QLC_HOME}/config/qpy/csv/Castnet_station-locations.csv"
REGION_US_CASTNET_PLOT_REGION="US"
REGION_US_CASTNET_VARIABLES="NH4_as,SO4_as,NO3_as"  # No NH3 in CASTNET
REGION_US_CASTNET_STATION_RADIUS_DEG=1.0  # Moderate spacing
REGION_US_CASTNET_MARS_RETRIEVALS=("C1_sfc")  # Aerosols only (efficiency)

# US AMoN: Biweekly NH3 only
REGION_US_AMON_NAME="US_AMON"
REGION_US_AMON_OBS_DATASET_TYPE="AMoN"
REGION_US_AMON_STATION_FILE="${QLC_HOME}/config/qpy/csv/AMoN_station-locations.csv"
REGION_US_AMON_PLOT_REGION="US"
REGION_US_AMON_VARIABLES="NH3"  # Only NH3 available
REGION_US_AMON_STATION_RADIUS_DEG=2.0  # Very sparse network
REGION_US_AMON_MARS_RETRIEVALS=("B1_pl")  # NH3 only (efficiency)
```

Run as normal:
```bash
cd ~/qlc/run
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
```

### Output Structure

```
Plots/exp1-exp2_20181201-20181221/
├── EU/
│   ├── temp_qlc_D1_config.json                    # Region config used
│   ├── qlc_D1_*_NH3_*_collocated_*.nc             # Collocation data
│   ├── qlc_D1_*_NH3_*_collocated_*.png            # Collocation plots
│   ├── qlc_D1_*_NH3_*_regional_mean*.png          # Time series
│   ├── qlc_D1_*_NH3_*_regional_bias*.png          # Bias plots
│   ├── qlc_D1_*_NH3_*_stats_plot_*.png            # Statistics
│   ├── qlc_D1_*_NH4_as_*_collocated_*.nc          # NH4 data
│   ├── qlc_D1_*_NH4_as_*_plots...                 # NH4 plots
│   └── texPlotfiles_qlc_D1.tex                    # Region TeX
├── US_CASTNET/
│   ├── qlc_D1_*_NH4_as_*_collocated_*.nc          # NH4 only
│   ├── qlc_D1_*_plots...
│   └── texPlotfiles_qlc_D1.tex
├── US_AMON/
│   ├── qlc_D1_*_NH3_*_collocated_*.nc             # NH3 only
│   ├── qlc_D1_*_plots...
│   └── texPlotfiles_qlc_D1.tex
├── texPlotfiles_qlc_D1_all_regions.tex            # Combined report
└── texPlotfiles_qlc_D1.tex                        # Standard name (for Z1)
```

### Common Scenarios

**Urban vs Rural Comparison**:
```bash
ACTIVE_REGIONS=("EU_urban" "EU_rural")

REGION_EU_urban_STATION_FILE="${QLC_HOME}/config/qpy/csv/Ebas_station-locations-urban.csv"
REGION_EU_urban_STATION_RADIUS_DEG=0.25  # Dense urban

REGION_EU_rural_STATION_FILE="${QLC_HOME}/config/qpy/csv/Ebas_station-locations-rural.csv"
REGION_EU_rural_STATION_RADIUS_DEG=1.0   # Sparse rural
```

**Global Multi-Network Analysis**:
```bash
ACTIVE_REGIONS=("EU" "US_CASTNET" "US_AMON" "Asia")

# Configure each region with appropriate dataset
# EBAS for EU, CASTNET/AMoN for US, China AQ for Asia
```

**Single Region with Multiple Datasets**:
```bash
ACTIVE_REGIONS=("US_CASTNET" "US_AMON" "US_AIRNOW")

# Three US networks with different temporal resolutions:
# CASTNET (weekly), AMoN (biweekly), AirNow (hourly)
```

### Tips and Best Practices

**Variable Filtering**:
- Variables are automatically filtered based on:
  1. MARS_RETRIEVALS (or region override)
  2. Observation dataset capabilities
  3. Actual file availability
- Requesting unavailable variables logs a warning but continues processing

**Search Radius Guidance**:
- Dense urban/hourly networks: 0.25-0.5 degrees
- Moderate daily/weekly networks: 0.5-1.0 degrees
- Sparse biweekly networks: 1.0-2.0 degrees
- Remote/background sites: 2.0-2.5 degrees
- Note: 1 degree ≈ 111 km at equator

**MARS Optimization**:
- Use region-specific MARS_RETRIEVALS to avoid retrieving unnecessary variables
- Example: AMoN only needs NH3, so override to `REGION_US_AMON_MARS_RETRIEVALS=("B1_pl")`

**Missing Data Handling**:
- Regions with no observation data are skipped with a log message
- Script continues with remaining regions
- Check logs for "Skipping region" messages

**TeX File Modes**:
```bash
TEX_FILE_MODE="combined"    # One file with all regions (default)
TEX_FILE_MODE="per_region"  # Separate file per region
```

### Backward Compatibility

To use single-region mode (v0.4.1 behavior):
```bash
MULTI_REGION_MODE=false  # or leave unset
# Use legacy variables: STATION_FILE, OBS_DATASET_TYPE, etc.
```

All existing configurations continue to work without modification.

---

### `qlc-py`: Standalone Python Engine

Use this tool for rapid data analysis and plotting without the overhead of the full shell pipeline. It is controlled by a JSON configuration file. By default, it uses the configuration file located at `$HOME/qlc/config/json/qlc_config.json`, but you can provide your own.

This is useful for developers or for regenerating plots with different settings after an initial `qlc` run has completed.

**Examples**
```bash
# Run with the default configuration
# This can be used to re-run the Python analysis after a 'qlc' run
qlc-py

# Run with a specific, user-defined configuration file
qlc-py --config /path/to/my_config.json
```

### `sqlc`: Submitting a Batch Job

For long-running jobs, you can submit the QLC pipeline to a batch scheduling system like SLURM.

**Examples**
```bash
# Submit a job with default parameters from qlc.conf
sqlc

# Submit with two experiments
sqlc b2ro b2rn 2018-12-01 2018-12-21 mars

# Submit with multiple experiments
sqlc exp1 exp2 exp3 2018-12-01 2018-12-21 mars
```

---

## Task-Based Configuration

QLC now supports task-based workflows where different processing pipelines can be selected using the optional `[task]` parameter. Each task has its own configuration directory under `$HOME/qlc/config/<task_name>/`.

### Available Tasks

- **Default** (no task specified): Standard QLC workflow with all subscripts
- **`qpy`**: qlc-py only - fast Python-based collocation and plotting
- **`evaltools`**: Advanced statistical plots using evaltools (requires `qpy` to be run first)
- **`ver0d`**: Ver0D external verification tool integration (ATOS-specific, optional)

**Task Configuration Structure**
```
qlc/config/
├── qlc.conf              # Base configuration
├── qpy/
│   └── qlc_qpy.conf      # qlc-py specific settings
└── evaltools/
    ├── qlc_evaltools.conf         # Evaltools settings
    ├── qlc_evaluator4evaltools.py # Converter script
    └── qlc_aqtool_1.0.9.py       # Plotting wrapper
```

Each task configuration inherits base settings from `qlc.conf` and adds task-specific overrides.

---

## Python Workflow and Configuration

The Python-based workflow is integrated into the main `qlc` pipeline via the `qlc_D1.sh` script. This script dynamically discovers available variables (e.g., `NH3`, `NH4_as`) from your NetCDF files in the `Analysis` directory. It then generates a temporary JSON configuration file and passes it to `qlc-py` for processing.

**Multi-Experiment Support**: The workflow now supports comparing any number of experiments. The `experiments` field in the JSON configuration accepts a comma-separated list (e.g., `"b2ro,b2rn,b2rm"`), and all experiments will be processed and compared in the output plots and statistics.

You can customize this workflow by editing the variables in your main configuration file: **`$HOME/qlc/config/qlc.conf`** or task-specific configuration files.

### Key Configuration Variables

| Variable | Description | Example |
| --- | --- | --- |
| `STATION_FILE` | Path to the CSV file containing station metadata (ID, name, lat, lon). | `"${QLC_HOME}/obs/data/ebas_station-locations.csv"` |
| `OBS_DATA_PATH` | Root path to the observation NetCDF files. | `"${QLC_HOME}/obs/data/ver0d"` |
| `OBS_DATASET_TYPE`| The specific observation dataset to use (e.g., `ebas_hourly`, `ebas_daily`, ...). | `"ebas_daily"` |
| `MODEL_LEVEL` | The model level index to extract. If left empty (`""`), the code intelligently defaults to the highest index (closest to the surface). | 9 |
| `TIME_AVERAGE` | The time averaging to apply to the data (e.g., `daily`, `monthly`, `yearly`, ...). | `"daily"` |
| `REGION` | The geographical region to focus on for plots and analysis (e.g., `"EU"`, `"US"`, `"ASIA"` , `"Globe"`, ...). | `"EU"` |
| `EXP_LABELS` | Comma-separated labels for experiments, used in plot legends. Must match the order and number of experiments passed to `qlc`. | `"MyExp,MyREF"` or `"Exp1,Exp2,Exp3"` |
| `PLOTEXTENSION` | The file format for the output plots (e.g., `pdf`, `png`, ...). | `"png"` |

---

## Available `qlc-py` Options

The Python engine is highly configurable through the `qlc.conf` file or a custom JSON configuration. Below is an overview of the most common options available.

### Plotting Regions (`REGION`)

You can set the `REGION` variable to any of the following codes to automatically set the map bounds for plots.

| Category | Region Codes |
| --- | --- |
| **Continents & Global** | `Globe`, `EU` (Europe), `ASIA`, `AFRICA`, `NA` (North America), `SA` (South America), `OC` (Oceania), `ANT` (Antarctica), `NP` (North Pole) |
| **Oceans & Water Bodies** | `PAC` (Pacific), `ATLA` (Atlantic), `INDO` (Indian), `ARC` (Arctic), `SOU` (Southern) |
| **Major Deserts** | `SAH` (Sahara), `ARA` (Arabian), `GOBI`, `OUTBACK` (Australian), `ATACAMA` |
| **Key Countries** | `GB` (Great Britain), `US` (United States), `CN` (China), `JP` (Japan), `SA` (Saudi Arabia), `IR` (Iran), `EG` (Egypt), `MA` (Morocco), `NG` (Nigeria), `KE` (Kenya), `ZA` (South Africa), `IS` (Iceland) |
| **European Countries**| `DE` (Germany), `FR` (France), `IT` (Italy), `ES` (Spain), `PL` (Poland), `SE` (Sweden), `FI` (Finland), `NO` (Norway), `NL` (Netherlands), `BE` (Belgium), `AT` (Austria), `CH` (Switzerland), `CZ` (Czech Rep.), `GR` (Greece) |
| **US States** | `CA-US` (California), `NY-US` (New York), `TX-US` (Texas), `FL-US` (Florida), `IL-US` (Illinois), `WA-US` (Washington), `CO-US` (Colorado), `AZ-US` (Arizona) |
| **Specific Regions** | `MENA` (Middle East/North Africa), `SSA` (Sub-Saharan Africa) |
| **Major Cities** | `LA-US`, `NYC-US`, `SHA-CN` (Shanghai), `BEI-CN` (Beijing), `TOK-JP` (Tokyo), `FR-PAR` (Paris), `DE-MUC` (Munich), `DE-FRA` (Frankfurt), `IT-ROM` (Rome), `ES-MAD` (Madrid), `PL-WAW` (Warsaw), `NL-AMS` (Amsterdam), `BE-BRU` (Brussels), `AT-VIE` (Vienna), `CZ-PRG` (Prague), `GR-ATH` (Athens), `CH-ZUR` (Zurich) |
| **German Regions** | `BW-DE` (Baden-Württemberg), `B-DE` (Berlin), `HH-DE` (Hamburg), `FR-DE` (Freiburg) |

### Time Averaging (`TIME_AVERAGE`)

The `TIME_AVERAGE` variable controls the temporal aggregation of the time series data.

- **`raw`**: No averaging is applied.
- **`mean`**: The mean over the entire time period is calculated.
- **Time Frequencies**: `1min`, `10min`, `30min`, `hourly`, `3hourly`, `6hourly`, `12hourly`, `daily`, `weekly`, `monthly`, `annual`, `seasonal`, `decadal`.

### Observation Datasets (`OBS_DATASET_TYPE`)

The `OBS_DATASET_TYPE` variable specifies which observation network data to use. The following datasets are supported:

- `ebas` / `ebas_hourly` / `ebas_daily` (EBAS - European Monitoring and Evaluation Programme)
- `airbase` / `airbase_ineris` (European air quality database)
- `airnow` (U.S. EPA's AirNow program)
- `castnet` (Clean Air Status and Trends Network)
- `AMoN` (Ammonia Monitoring Network)
- `NNDMN` (National Network of Deposition Monitoring in the Netherlands)
- `china_gsv` / `china_aq` (Chinese air quality data)

### Supported Variables (`variable`)

The `qlc` pipeline automatically discovers variables from your data files. The system supports a wide range of chemical species and physical properties. The list below contains all variables recognized by the EBAS observation dataset mapping, which is the most extensive. Other datasets may support a subset of these.

-   **Gases**: `NO2`, `SO2`, `SO4`, `HNO3`, `NO3`, `NH3`, `NH4`, `NO`, `NOx`, `O3`, `CO`, `HONO` (Nitrous Acid), `ethanal`, `methanol`, `ethene`, `ethyne`, `propene`, `benzene`, `ethane`, `propane`, `ethylbenzene`, `m-p-xylene`, `o-xylene`, `toluene`.
-   **Mole Fractions**: `SO2_mf`, `NH3_mf`, `NO_mf`, `NO2_mf`, `NOx_mf`, `O3_mf`, `CO_mf`, `ethanal_mf`, `methanol_mf`, `ethene_mf`, `ethyne_mf`, `propene_mf`, `benzene_mf`, `ethane_mf`, `propane_mf`, `ethylbenzene_mf`, `m-p-xylene_mf`, `o-xylene_mf`, `toluene_mf`.
-   **Halocarbons (Mole Fractions)**: `CCl4_mf`, `CH3Cl_mf`, `CH2Br2_mf`, `CH2Cl2_mf`, `CHCl3_mf`.
-   **Greenhouse Gases (Mole Fractions)**: `carbon_dioxide_mf`, `methane_mf`, `hydrogen_mf`, `nitrous_oxide_mf`.
-   **Aerosol Properties**:
    -   **Mass Density**: `PM1`, `PM2.5`, `PM10`.
    -   **Composition (Dry Aerosol)**: `Dry_Nitrate`, `Dry_Ammonium`, `Dry_Chloride`, `Dry_Calcium`, `Dry_Sodium`, `Dry_Iron`, `Dry_Sulphate_Corrected`.
    -   **Composition (PM2.5)**: `PM2.5_Nitrate`, `PM2.5_Sodium`, `PM2.5_Calcium`, `PM2.5_Ammonium`, `PM2.5_Chloride`, `PM2.5_Total_Sulphate`, `PM2.5_Sulphate_Corrected`, `PM2.5_EC` (Elemental Carbon), `PM2.5_OC` (Organic Carbon), `PM2.5_TC` (Total Carbon).
    -   **Composition (PM10)**: `PM10_Nitrate`, `PM10_Sodium`, `PM10_Calcium`, `PM10_Ammonium`, `PM10_Chloride`, `PM10_Lead`, `PM10_Iron`, `PM10_Manganese`, `PM10_Total_Sulphate`, `PM10_Sulphate_Corrected`, `PM10_EC`, `PM10_OC`, `PM10_TC`.
    -   **Number Concentration**: `Dry_NA_NumConc`.
-   **Optical Properties**:
    -   **Aerosol Optical Depth (AOD)**: `AOD_380`, `AOD_500`, `AOD_675` (and many other wavelengths).
    -   **Scattering Coefficient**: `Scatt_450`, `Scatt_525`, `Scatt_550`, `Scatt_635`, `Scatt_700`.
    -   **Absorption Coefficient**: `Abs_370`, `Abs_470`, `Abs_520`, `Abs_660`, `Abs_880` (and many other wavelengths between 370nm and 950nm).
    -   **Backscattering**: `Backscatt_700`.
-   **Meteorology**: `Pressure`, `Temperature`.

#### Model-Specific Variables

The following variables are specifically mapped for model (`mod`) data types. These often include different aerosol size bins or speciated components.

-   **Aerosol Mass**: `PM1`, `PM2.5`, `PM10`
-   **Aerosol Number Concentration**: `N`, `N_ks` (Aitken mode soluble), `N_as` (accumulation mode soluble), `N_cs` (coarse mode soluble)
-   **Sulphate Species**: `SO4`, `SO4_ks`, `SO4_as`, `SO4_cs`
-   **Ammonium Species**: `NH4`, `NH4_ks`, `NH4_as`, `NH4_cs`
-   **Nitrate Species**: `NO3`, `NO3a`, `NO3b`, `NO3_ks`, `NO3_as`, `NO3_cs`
-   **Gases (Mass Mixing Ratios)**: `NH3`, `HNO3`, `NO2`, `SO2`, `CO`, `O3`

*Note: The list of supported variables is actively being expanded. Future releases will include a more comprehensive mapping and direct integration with the GHOST (Globally Harmonised Observations in Space and Time) database [[Bowdalo et al., 2024]](https://essd.copernicus.org/articles/16/4417/2024/).*

---

## Advanced `qlc-py` Configuration

The `qlc-py` engine offers several advanced configuration options for more complex analysis workflows.

### Using Custom Station Lists

For targeted analysis, you can provide a custom list of stations via the `station_file` parameter in your configuration. This should be a path to a CSV file containing station metadata (e.g., ID, name, latitude, longitude).

-   This is useful for focusing on specific station types (e.g., urban, rural) or networks.
-   If a station from your list is not found in the observation dataset for a given period, it will still be included in the model-only analysis and plots.
-   In addition to plots showing the average across all stations, you can configure `qlc-py` to generate plots and statistics for each individual station in the list.

### Multi-Entry and Parallel Processing

The JSON configuration file passed to `qlc-py` can be a single JSON object or an array of multiple objects. This enables powerful and flexible workflow designs.

-   **Serial Processing**: If you provide an array of configuration objects, `qlc-py` will process them sequentially. This is useful for workflows with distinct steps, such as:
    1.  An entry for processing observations only.
    2.  An entry for processing model results only.
    3.  A final entry that uses both outputs for a combined collocation analysis.
-   **Parallel Processing**: Within a single configuration entry, you can enable parallel processing for time-consuming tasks (like loading and processing many model files at once) by setting `"multiprocessing": true`.

### Example: Multi-Variable Observation Configuration

Below is an example of a single configuration entry for processing daily EBAS observations for two variables (`NH3` and `NH4_as`). It also includes the optional `global_attributes` block, which allows you to embed custom metadata into the output NetCDF files.

```json
{
    "name": "CAMS",
    "logdir": "./log",
    "workdir": "./run",
    "output_base_name": "$HOME/qlc/Plots/PY",
    "station_file": "$HOME/qlc/obs/data/ebas_station-locations.csv",
    "obs_path": "$HOME/qlc/obs/data/ver0d",
    "obs_dataset_type": "ebas_daily",
    "obs_dataset_version": "latest",
    "start_date": "2018-12-01",
    "end_date": "2018-12-21",
    "variable": "NH3,NH4_as",
    "station_radius_deg": 0.5,
    "plot_type": "",
    "plot_region": "EU",
    "time_average": "daily",
    "station_plot_group_size": 5,
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": true,
    "show_station_timeseries_obs": true,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": false,
    "save_plot_format": "pdf",
    "save_data_format": "nc",
    "multiprocessing": false,
    "n_threads": "20",
    "debug": false,
    "global_attributes": {
      "title": "Air pollutants over Europe, SO2,SO4,HNO3,NO3,NH3,NH4",
      "summary": "Custom summary for netCDF output: Ebas daily observations for selected EU stations.",
      "author": "Swen Metzger, sm@researchconcepts.io",
      "history": "Processed for CAMS2_35bis (qlc_v0.3.27)",
      "Conventions": "CF-1.8"
    }
}
```

---

## Utilities

QLC includes several utility scripts for data preparation and station management.

### Station Extraction and Filtering (`qlc-extract-stations`)

This utility extracts station metadata from observation datasets and supports urban/rural classification based on proximity to major cities worldwide.

**Features:**
- Extracts station metadata from NetCDF observation files
- Global urban/rural classification using a database of 300+ major world cities
- Filters stations by type (all, urban, or rural)
- Supports date range filtering
- Compatible with all observation dataset types
- Available as command-line tool after installation

**Usage:**
```bash
# Extract all stations from observation data
qlc-extract-stations \
    --obs-path ~/qlc/obs/data/ver0d \
    --obs-type ebas_daily \
    --obs-version latest/201801 \
    --output ~/qlc/obs/data/ebas_stations_all.csv

# Extract only urban stations (within 50km of major cities)
qlc-extract-stations \
    --obs-path ~/qlc/obs/data/ver0d \
    --obs-type ebas_daily \
    --obs-version latest/201801 \
    --station-type urban \
    --urban-radius-km 50.0 \
    --output ~/qlc/obs/data/ebas_stations_urban.csv

# Extract rural stations only
qlc-extract-stations \
    --obs-path ~/qlc/obs/data/ver0d \
    --obs-type ebas_daily \
    --station-type rural \
    --output ~/qlc/obs/data/ebas_stations_rural.csv

# Filter by date range
qlc-extract-stations \
    --obs-path ~/qlc/obs/data/ver0d \
    --obs-type ebas_daily \
    --start-date 2018-12-01 \
    --end-date 2018-12-31 \
    --output ~/qlc/obs/data/ebas_stations_dec2018.csv
```

**Global City Database:**
The utility includes coordinates for 300+ major cities worldwide:
- **Asia**: China (20 cities), Japan (10), South Korea (8), India (11), Middle East (20)
- **Americas**: USA (25), Canada (9), Mexico (9), South America (23)
- **Europe**: 57 cities across Western, Southern, Central/Eastern Europe
- **Africa**: 36 cities across North, West, East, and Southern Africa
- **Oceania**: Australia (8), New Zealand (4)
- **Russia & Central Asia**: 14 major cities

This enables proper urban/rural classification for air quality studies in any region of the world.

**Usage Examples:**
For ready-to-use examples, see the script `bin/tools/qlc-extract-stations-examples.sh` included in the package. This script demonstrates all common usage patterns and can be customized for your workflows.

---

## K1 Namelist: EAC5/CAMS Reanalysis Analysis

**New in v0.4.1**: The K1 namelist provides a comprehensive, pre-configured setup for CAMS atmospheric reanalysis validation.

### Overview

The **K1 namelist** (`mars_K1_sfc.nml`) retrieves 10 carefully selected surface variables optimized for air quality assessment and reanalysis validation:

| Variable | Description | MARS Param | Typical Networks |
|----------|-------------|------------|------------------|
| **T** | Temperature (2m) | 130 | All networks |
| **PM2.5** | Fine Particulate Matter | 210073 | EBAS, AirNow, China AQ |
| **PM10** | Coarse Particulate Matter | 210074 | EBAS, CASTNET, AirNow |
| **O3** | Ozone | 210203 | All networks |
| **NO2** | Nitrogen Dioxide | 210121 | EBAS, AirNow, China AQ |
| **SO2** | Sulfur Dioxide | 210122 | EBAS, CASTNET, GAW |
| **HNO3** | Nitric Acid | 217006 | EBAS |
| **NH3** | Ammonia | 217019 | EBAS, AMoN |
| **NH4_as** | Ammonium (Accumulation mode) | 212035 | EBAS |
| **AOD** | Aerosol Optical Depth | 210207 | AERONET |

### Quick Start

#### Basic Usage

```bash
cd ~/qlc/run

# Configure K1 in qlc.conf
export MARS_RETRIEVALS=("K1_sfc")

# Run complete analysis with evaltools
qlc b2ro b2rn 2018-12-01 2018-12-21 eac5
qlc b2ro b2rn 2018-12-01 2018-12-21 eac5 evaltools
```

#### Multi-Experiment Comparison

```bash
# Compare two CAMS reanalysis versions
qlc eac5_v1 eac5_v2 2020-01-01 2020-12-31 qpy evaltools

# Compare three versions with Taylor diagrams
qlc cams_v1 cams_v2 cams_v3 2020-01-01 2020-12-31 evaltools
```

### Workflow Integration

The K1 configuration integrates seamlessly with the standard QLC workflow:

```
1. A1 (MARS)      → Retrieve 10 K1 variables from CAMS archive
2. B1a/B2         → Convert GRIB to NetCDF
3. D1 (qlc-py)    → Collocate with stations, generate plots
4. E1/E2 (evaltools) → Taylor diagrams, statistical analysis
5. Z1 (PDF)       → Generate final report
```

### Evaltools Taylor Diagrams

When using K1 with evaltools, you get advanced statistical visualizations:

**Taylor Diagrams** show model performance at a glance:
- Correlation coefficient (angular position)
- Standard deviation ratio (radial distance)
- Centered RMS difference (distance from reference)
- Multi-experiment comparison on single diagram

**Target Diagrams** show bias characteristics:
- Bias vs. unbiased RMSE
- Quick identification of systematic errors

**Enhanced Time Series**:
- Statistical metrics overlay
- Multi-experiment comparison
- Confidence intervals

### Example: European Air Quality Validation

```bash
# Configure for European domain
cd ~/qlc/run

# Edit qlc/config/qpy/qlc_qpy.conf:
MARS_RETRIEVALS=("K1_sfc")
REGION="EU"
STATION_FILE="${QLC_HOME}/config/qpy/csv/Ebas_station-locations.csv"
OBS_DATASET_TYPE="ebas_daily"
TIME_AVERAGE="daily"

# Run analysis
qlc b2ro b2rn 2018-12-01 2018-12-21 eac5
qlc b2ro b2rn 2018-12-01 2018-12-21 eac5 evaltools

# Results in ~/qlc/Plots/eac5_20200101-20201231/:
# - Taylor diagrams for all 10 variables
# - Time series with statistics
# - Scatter plots (model vs observations)
# - Statistical summary tables
```

### Example: Seasonal Analysis

```bash
# Winter
qlc b2ro b2rn 2020-12-01 2021-02-28 eac5 evaltools

# Summer  
qlc b2ro b2rn 2021-06-01 2021-08-31 eac5 evaltools

# Compare seasonal performance via Taylor diagrams
```

### Example: Multi-Region with K1

```bash
# Configure multi-region in qlc_qpy.conf
MULTI_REGION_MODE=true
ACTIVE_REGIONS=("EU" "US_CASTNET" "Asia")
MARS_RETRIEVALS=("K1_sfc")

# EU: All variables where available
REGION_EU_VARIABLES="T,PM25,PM10,O3,NO2,SO2,HNO3,NH3,NH4_as,AOD"
REGION_EU_OBS_DATASET_TYPE="ebas_daily"

# US CASTNET: Subset of variables
REGION_US_CASTNET_VARIABLES="PM25,PM10,SO2,O3"
REGION_US_CASTNET_OBS_DATASET_TYPE="castnet"

# Asia: Urban pollution focus
REGION_Asia_VARIABLES="PM25,PM10,O3,NO2"
REGION_Asia_OBS_DATASET_TYPE="china_aq"

# Run
qlc b2ro b2rn 2018-12-01 2018-12-21 eac5 evaltools
```

### Time Aggregations

K1 supports multiple temporal aggregations:

```bash
# Daily (default, matches most networks)
TIME_AVERAGE="daily"

# Weekly (useful for CASTNET)
TIME_AVERAGE="weekly"

# Monthly climatology
TIME_AVERAGE="monthly"

# Seasonal
TIME_AVERAGE="seasonal"
```

### Configuration

**Enable K1 in `qlc.conf`**:
```bash
# MARS retrieval configuration
MARS_RETRIEVALS=("K1_sfc")

# Variable definitions (already configured)
param_K1_sfc=("130" "210073" "210074" "210203" "210121" "210122" "217006" "217019" "212035" "210207")
ncvar_K1_sfc=("var130" "var73" "var74" "go3" "no2" "var122" "var6" "nh3" "param35.212.192" "var207")
myvar_K1_sfc=("T" "PM25" "PM10" "O3" "NO2" "SO2" "HNO3" "NH3" "NH4_as" "AOD")
```

### Custom K1 Variants

Create specialized versions for specific applications:

**K1_gases** (gases only):
```bash
param_K1_gases=("210203" "210121" "210122" "217006" "217019")
ncvar_K1_gases=("go3" "no2" "var122" "var6" "nh3")
myvar_K1_gases=("O3" "NO2" "SO2" "HNO3" "NH3")
```

**K1_aerosol** (aerosol properties):
```bash
param_K1_aerosol=("210073" "210074" "212035" "210207")
ncvar_K1_aerosol=("var73" "var74" "param35.212.192" "var207")
myvar_K1_aerosol=("PM25" "PM10" "NH4_as" "AOD")
```

**K1_nitrogen** (nitrogen cycle):
```bash
param_K1_nitrogen=("210121" "217006" "217019" "212035")
ncvar_K1_nitrogen=("no2" "var6" "nh3" "param35.212.192")
myvar_K1_nitrogen=("NO2" "HNO3" "NH3" "NH4_as")
```

### Observation Network Compatibility

| Network | Coverage | K1 Variables Available |
|---------|----------|------------------------|
| **EBAS** | Europe | All 10 variables |
| **CASTNET** | US | PM2.5, PM10, SO2, O3 |
| **AMoN** | US | NH3 only |
| **AirNow** | US | PM2.5, PM10, O3, NO2 |
| **China AQ** | Asia | PM2.5, PM10, O3, NO2, SO2 |
| **AERONET** | Global | AOD |
| **GAW** | Global | O3, NO2, SO2 |

### Performance Notes

**Data Volume** (approximate):
- Single month, global: ~500 MB GRIB
- Full year: ~6 GB GRIB
- After NetCDF conversion: ~8 GB/year

**Processing Time** (full workflow):
- Single month: 15-30 minutes
- Full year: 2.5-4.5 hours

### Documentation

For complete K1 documentation, see: `dev/ToDo/doc/0.4.02/K1_NAMELIST_EAC5_CONFIGURATION.md`

**Evaltools Resources**:
- **Online Wiki**: https://opensource.umr-cnrm.fr/projects/evaltools/wiki
- **Local Documentation**: `~/download_evaltools/documentation_v1.0.9/index.html` (after installation)
- **Examples**: `~/download_evaltools/simple_example_v1.0.6/` (after installation)

---

## Advanced Workflow: Data Processing and Configuration

For advanced users, it is helpful to understand the underlying data processing pipeline, which is controlled by a series of shell scripts and configured via `qlc.conf`. This allows for significant customization of data retrieval and analysis.

### The Shell Script Pipeline

When you run the main `qlc` command, it executes a chain of scripts to process data. The scripts to be run are defined by the `SUBSCRIPT_NAMES` array in `$HOME/qlc/config/qlc.conf`. A typical workflow is:

1.  **`qlc_A1.sh`**: Handles data retrieval from the MARS archive. It fetches the required variables in GRIB format. The specific variables are defined by the `MARS_RETRIEVALS` array in `qlc.conf`, which must correspond to entries in the `nml/mars_*.nml` namelist files.
2.  **`qlc_B1a.sh`**: Converts the retrieved GRIB files into NetCDF format.
3.  **`qlc_B2.sh`**: Performs post-processing and variable substitution on the NetCDF files. This step is crucial as it renames the variables to the user-friendly names (`myvar_*`) expected by the plotting scripts.
4.  **`qlc_D1.sh`**: Drives the station time-series analysis by generating a configuration and calling `qlc-py`.
5.  **`qlc_C5.sh`**: Generates global overview plots, including 3D surface maps, vertical integrals (burden), and zonal/meridional means for selected variables.

The raw data retrieved from MARS is stored in the `$HOME/qlc/Results` directory, while the final, post-processed NetCDF files used for analysis are placed in `$HOME/qlc/Analysis`.

### Variable Mapping Explained

QLC uses a flexible three-part system defined in `qlc.conf` to map variables from the MARS archive to user-defined names for plotting.

-   **`param_*`**: This is the official ECMWF parameter ID from the GRIB tables (e.g., `param_A1_sfc="73.210"`). This value is required by MARS for data retrieval and must be correct.
-   **`ncvar_*`**: This is the short name that is automatically assigned to the variable when the GRIB file is converted to NetCDF (e.g., `ncvar_A1_sfc="var73"`). This name can differ depending on the data type (surface, pressure levels, model levels).
-   **`myvar_*`**: This is the final, user-defined name for the variable (e.g., `myvar_A1_sfc="PM25"`). This is the name that will be used in plot labels, titles, and filenames throughout the QLC system.

This system allows you to work with consistent, human-readable variable names (`PM25`) while ensuring the underlying retrieval from MARS uses the correct, official parameter codes.

### Automatic Unit Conversion and Collocation

During the collocation step (comparing model data to observations), `qlc-py` automatically handles variable mapping and unit conversion. For example, when comparing model output (`mod`) to `castnet` observations:

-   If a model variable named `SO4` or `SO4_as` (in units of `kg/kg`) is being compared to a `castnet` observation variable also named `SO4` (in units of `ug/m3`), the system will automatically convert the model data to `ug/m3` before calculating statistics. The observational unit is always treated as the target for conversion.

### Using Custom Data with `qlc-py`

While the shell script pipeline is designed for a seamless workflow, you can also use `qlc-py` as a standalone tool with your own NetCDF data. Simply provide absolute paths to your data files in the `mod_path` and `obs_path` fields of your JSON configuration. The data must be CF-compliant, but this allows you to bypass the MARS retrieval and processing steps entirely.

### Example Report

An example of the final PDF report generated by the `qlc` pipeline can be found in the `$HOME/qlc/doc/` directory. This provides a complete overview of all selected plots and analyses produced. The `$HOME/qlc/Presentations/` directory contains the report of a successful run.

### Accessing Raw Outputs for Custom Analysis

The QLC pipeline generates a wide range of outputs that can be used for further analysis outside of the main workflow.

-   **Comprehensive Plots**: The `$HOME/qlc/Plots` directory contains all of the individual plots created during the run, e.g., in higher resolution or with more detail than what is included in the final summary report.
-   **Exportable Data**: You can configure `qlc-py` to save the intermediate, collocated data in either NetCDF (`.nc`) or CSV (`.csv`) format.
-   **Multiple Plot Formats**: Plots can be saved in various formats, including `.pdf`, `.png`, and `.jpg`.

This flexibility allows you to easily import QLC-processed data and graphics into your own analysis scripts, presentations, or reports.

---

## Ver0D Integration (Optional)

**New in v0.4.1**: The ver0D scripts (F1-F5) now support multiple experiments with consistent naming and architecture.

### Overview

Ver0D (verification 0-dimensional) is an external IDL-based verification tool developed at ECMWF for specialized model-observation comparisons. QLC provides optional integration with ver0D through scripts F1-F5.

**Supported Ver0D Modes**:
- **AOD**: Aerosol Optical Depth (AERONET observations)
- **GAW**: Global Atmosphere Watch surface measurements
- **TCOL**: Total column measurements (stub)
- **SURFAER**: Surface aerosol properties (stub)

### Requirements

Ver0D integration requires:
- Access to ATOS or similar HPC environment
- Ver0D tools installed: `v0d_get_model_data`, `v0d_verify`
- Ver0D settings configured in `~/ver0D/mode_*/ver_settings/`
- Data storage paths: `~/perm/ver0D/data/` and `$SCRATCH/ver0D/`

**Note**: Ver0D is primarily available on ECMWF ATOS systems and requires IDL runtime.

### Multi-Experiment Support (v0.4.1+)

Ver0D scripts now support unlimited experiments, consistent with the main QLC workflow:

```bash
# Two experiments (original)
qlc exp1 exp2 2018-12-01 2018-12-21 ver0d

# Three or more experiments (new capability)
qlc exp1 exp2 exp3 2018-12-01 2018-12-21 ver0d
qlc exp1 exp2 exp3 exp4 exp5 2018-12-01 2018-12-21 ver0d
```

### Ver0D Workflow

#### Step 1: Data Retrieval (F1)

F1 script retrieves model data for ver0D analysis:

```bash
# Retrieve data for multiple experiments and modes (AOD, GAW)
qlc exp1 exp2 exp3 2018-12-01 2018-12-21 ver0d

# Creates:
# - Settings files: exp1-exp2-exp3_settings.txt
# - Model data: ~/perm/ver0D/data/mode_aod/model_data/exp1/
#               ~/perm/ver0D/data/mode_aod/model_data/exp2/
#               ~/perm/ver0D/data/mode_aod/model_data/exp3/
```

#### Step 2: Generate Plots (F2-F5)

After F1 completes, run ver0D verification and plotting:

**F2 - AOD Plots**:
```bash
# Taylor diagrams and site plots for Aerosol Optical Depth
# Uses AERONET observation network
# Output: ~/perm/ver0D/data/mode_aod/results/exptsets/exp1-exp2-exp3/
```

**F3 - GAW Plots**:
```bash
# Global Atmosphere Watch plots
# Includes bias, scatter, histogram plots
# Output: ~/perm/ver0D/data/mode_gaw/results/exptsets/exp1-exp2-exp3/
```

**F4/F5 - TCOL/SURFAER** (stubs for future implementation)

### Ver0D Output Structure

```
~/perm/ver0D/data/
├── mode_aod/
│   ├── model_data/
│   │   ├── exp1/
│   │   │   └── exp1_20181201_00.nc
│   │   ├── exp2/
│   │   └── exp3/
│   └── results/
│       └── exptsets/
│           └── exp1-exp2-exp3/
│               └── 20181201-20181221/
│                   └── images/
│                       ├── taylor_vs_site_24hr.gif
│                       ├── siteplot_500_inst.gif
│                       └── ...
└── mode_gaw/
    └── results/
        └── exptsets/
            └── exp1-exp2-exp3/
                └── 20181201-20181221/
                    └── images/
                        ├── taylor_vs_site_global_24hrs.gif
                        ├── bias_vs_fcr_global.gif
                        ├── scatter_global_24hrs.gif
                        └── ...
```

### TeX Integration

Ver0D plots are collected into TeX files for PDF generation:

```
~/qlc/Plots/exp1-exp2-exp3_20181201-20181221/
├── texPlotfiles_qlc_F2.tex   # AOD plots
├── texPlotfiles_qlc_F3.tex   # GAW plots
└── ...
```

These can be manually integrated into the main QLC PDF report or processed separately.

### Ver0D Commands

**Internal Commands Used** (automatic):

```bash
# Data retrieval (F1):
v0d_get_model_data -s -q ${RETRIEVE} aod exp1-exp2-exp3 201812-201812

# Verification (F2/F3):
v0d_verify aod exp1-exp2-exp3 20181201
v0d_verify gaw exp1-exp2-exp3 20181201-20181221
```

**Check Job Status** (on ATOS):
```bash
v0d_joblist      # List running ver0D jobs
v0d_jobcancel    # Cancel ver0D jobs
squeue -u $USER  # Check SLURM queue
```

### Ver0D Configuration

Ver0D uses settings files that are automatically created from templates:

**AOD Settings**:
```
~/ver0D/mode_aod/ver_settings/init_settings.txt          # Template
~/ver0D/mode_aod/ver_settings/exp1-exp2-exp3_settings.txt  # Generated
~/ver0D/mode_aod/ver_settings/exp1-exp2-exp3,angstrom_settings.txt
```

**GAW Settings**:
```
~/ver0D/mode_gaw/ver_settings/init_settings.txt          # Template
~/ver0D/mode_gaw/ver_settings/exp1-exp2-exp3_settings.txt  # Generated
~/ver0D/mode_gaw/ver_settings/exp1-exp2-exp3,china_settings.txt
~/ver0D/mode_gaw/ver_settings/exp1-exp2-exp3,airbase_settings.txt
```

### Limitations and Notes

1. **External Tool**: Ver0D is not part of QLC; it must be installed separately
2. **ATOS-Specific**: Primary usage on ECMWF ATOS systems
3. **IDL Dependency**: Requires IDL runtime environment
4. **Manual Integration**: Ver0D plots not automatically included in main QLC PDF
5. **Testing**: Ver0D functionality testing performed separately on ATOS

### Backward Compatibility

Ver0D scripts maintain full backward compatibility with 2-experiment usage:

```bash
# Original 2-experiment syntax still works
qlc exp1 exp2 2018-12-01 2018-12-21 ver0d
# Equivalent to: experiments_hyphen="exp1-exp2"
```

For more details, see: `dev/ToDo/doc/0.4.02/F1_F5_MULTI_EXPERIMENT_SUPPORT.md`

---

## Development and Debugging Tools

For developers and advanced users, QLC includes several utility scripts in the package at `bin/tools/`:

### Evaluator Inspection

Inspect evaltools evaluator pickle files:
```bash
# Inspect a specific evaluator
qlc-inspect-evaluator.sh ~/qlc/Analysis/evaluators/Europe_b2ro_*.evaluator.evaltools

# Find and inspect all evaluators
find ~/qlc/Analysis/evaluators -name "*.evaluator.evaltools" \
     -exec qlc-inspect-evaluator.sh {} \;
```

### Development Environment

Load development helper functions:
```bash
source ~/qlc-dev-run/bin/tools/qlc_dev_env.sh

# Available functions:
qlc-rebuild           # Rebuild development package
qlc-test-extract      # Test station extraction
qlc-find-evaluators   # Find evaluator files
qlc-inspect-all       # Inspect all evaluators
```

### Station Extraction Examples

Ready-to-use example script for common extraction workflows:
```bash
# Review and customize the script
~/qlc-dev-run/bin/tools/qlc-extract-stations-examples.sh
```

### Configuration Testing

Test configuration file loading and task-based inheritance:
```bash
~/qlc-dev-run/bin/tools/qlc_test_config_loading.sh
```

For complete documentation of all development utilities, see `bin/tools/README.md` in the package source.

---

