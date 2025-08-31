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

