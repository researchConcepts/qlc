# QLC Usage Guide

This guide provides detailed instructions on how to use the QLC command-line tools and configure the workflow.

---

## Installed CLI Tools

Once installed, QLC provides the following command-line entry points:

- **`qlc`**: The main driver. Runs the full shell-based QLC pipeline, which now integrates the `qlc-py` engine for all data processing and plotting. Use this for standard, end-to-end model evaluation runs.
- **`qlc-py`**: The standalone Python engine. Can be run directly with a JSON configuration file for rapid, iterative analysis without re-running the entire shell pipeline.
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
qlc <exp1> <exp2> <start_date> <end_date> [mars]
```

**Examples**
```bash
# Run a comparison of experiments b2ro and b2rn for the first three weeks of Dec 2018
# This uses the example data included in the 'test' installation.
qlc b2ro b2rn 2018-12-01 2018-12-21

# Run the same comparison, but first retrieve the data from MARS
qlc b2ro b2rn 2018-12-01 2018-12-21 mars

# Run without options to see the help message
qlc
```

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

# Submit with specific experiments and dates, including MARS retrieval
sqlc b2ro b2rn 2018-12-01 2018-12-21 mars
```

---

## Python Workflow and Configuration

The new Python-based workflow is integrated into the main `qlc` pipeline via the `qlc_D1.sh` script. This script dynamically discovers available variables (e.g., `NH3`, `NH4_as`) from your NetCDF files in the `Analysis` directory. It then generates a temporary JSON configuration file and passes it to `qlc-py` for processing.

You can customize this workflow by editing the variables in your main configuration file: **`$HOME/qlc/config/qlc.conf`**.

### Key Configuration Variables

| Variable | Description | Example |
| --- | --- | --- |
| `STATION_FILE` | Path to the CSV file containing station metadata (ID, name, lat, lon). | `"${QLC_HOME}/obs/data/ebas_station-locations.csv"` |
| `OBS_DATA_PATH` | Root path to the observation NetCDF files. | `"${QLC_HOME}/obs/data/ver0d"` |
| `OBS_DATASET_TYPE`| The specific observation dataset to use (e.g., `ebas_hourly`, `ebas_daily`, ...). | `"ebas_daily"` |
| `MODEL_LEVEL` | The model level index to extract. If left empty (`""`), the code intelligently defaults to the highest index (closest to the surface). | 9 |
| `TIME_AVERAGE` | The time averaging to apply to the data (e.g., `daily`, `monthly`, `yearly`, ...). | `"daily"` |
| `REGION` | The geographical region to focus on for plots and analysis (e.g., `"EU"`, `"US"`, `"ASIA"` , `"Globe"`, ...). | `"EU"` |
| `EXP_LABELS` | Comma-separated labels for experiments, used in plot legends. Must match the order of experiments passed to `qlc`. | `"MyExp,MyREF"` |
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
-   **Aerosol Number Concentration**: `N`, `N_ks` (nucleation mode), `N_as` (aitken mode), `N_cs` (coarse mode)
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

