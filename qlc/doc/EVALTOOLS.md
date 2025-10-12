# Evaltools Integration

> **⚠️ BETA RELEASE - v0.4.1**: This major release is currently under development and requires further testing. Please report any issues you encounter.

QLC integrates with the `evaltools` Python package (developed by Météo France) for advanced statistical analysis and comprehensive model-observation comparison plots.

---

## Quick Start

After running qlc-py collocation:

```bash
cd ~/qlc/run

# Step 1: Create qlc-py collocation data
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Step 2: Create evaltools statistical plots
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools
```

---

## What is Evaltools?

**Evaltools** is a third-party Python package for air quality model evaluation, providing:

- 15+ statistical and comparative plot types
- Advanced metrics (MBE, RMSE, R², FAC2, etc.)
- Time series decomposition
- Diurnal/seasonal analysis
- Taylor diagrams
- Target plots
- Q-Q plots
- Spatial correlation analysis

---

## Configuration

### Main Configuration File

Edit `qlc/config/evaltools/qlc_evaltools.conf` to customize:

```bash
# Example settings
EVALUATORS=("time_series" "scatter" "taylor" "target")
STATISTICS=("MBE" "RMSE" "R2" "FAC2")
TIME_AGGREGATION="daily"
```

See `qlc/config/evaltools/README.md` for complete configuration options.

### Multi-Region Support

Evaltools works with multi-region qlc-py output (v0.4.1+):

```bash
# Create collocation for multiple regions
MULTI_REGION_MODE=true qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Run evaltools on all regions
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools
```

---

## Documentation

### Official Resources

- **Evaltools Wiki **: https://opensource.umr-cnrm.fr/projects/evaltools/wiki 

### QLC-Specific Documentation

- **Integration Guide**: `qlc/config/evaltools/README.md`
- **Workflow Examples**: `qlc/doc/USAGE.md` (Task-Based Configuration section)
- **Detailed Evaltools Docs**: Available from the download directory, see `Wiki`

The detailed evaltools documentation (v1.0.9) includes:
- HTML API documentation
- Plot examples (PNG)
- Usage notes (TXT)
- Release notes


---

## Workflow Integration

### Standard Two-Step Workflow

```bash
# Step 1: qlc-py collocation (creates collocated .nc files)
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Step 2: evaltools analysis (uses collocated .nc from step 1)
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools
```

---

## Plot Types Available

Evaltools provides these plot types (configurable in `qlc_evaltools.conf`):

1. **Time Series Plots**
   - Observed vs modeled time series
   - Min/max ranges
   - Bias evolution

2. **Scatter Plots**
   - 1:1 comparison
   - Regression lines
   - Density coloring

3. **Statistical Summary**
   - Bar charts of metrics
   - Multi-variable comparison
   - Multi-experiment comparison

4. **Taylor Diagrams**
   - Normalized standard deviation
   - Correlation coefficient
   - RMSE contours

5. **Target Plots**
   - Normalized bias
   - Normalized error
   - Acceptance criteria

6. **Q-Q Plots**
   - Quantile-quantile comparison
   - Distribution matching

7. **Diurnal Cycles**
   - Hourly patterns
   - Day/night differences

8. **Seasonal Analysis**
   - Monthly aggregations
   - Seasonal trends

9. **Spatial Analysis**
   - Station-by-station metrics
   - Geographic patterns

---

## Requirements

Evaltools is not automatically installed with QLC via:

```bash
pip install rc-qlc
```

Install evaltools separately:

```bash
mkdir -p ~/download_evaltools && cd ~/download_evaltools
wget https://redmine.umr-cnrm.fr/attachments/download/5300/evaltools_v1.0.9.zip
wget https://redmine.umr-cnrm.fr/attachments/download/4014/simple_example_v1.0.6.zip
wget https://redmine.umr-cnrm.fr/attachments/download/5298/documentation_v1.0.9.zip
unzip evaltools_v1.0.9.zip
unzip simple_example_v1.0.6.zip
unzip documentation_v1.0.9.zip -d documentation_v1.0.9
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
conda env create -f environment.yml
conda activate evaltools
which pip
open documentation_v1.0.9/index.html
```

---

## Output Files

Evaltools generates:

```
Plots/exp1-exp2_DATE/
├── evaltools_time_series_VAR.png
├── evaltools_scatter_VAR.png
├── evaltools_taylor_diagram.png
├── evaltools_target_plot.png
├── evaltools_statistics_summary.png
└── evaltools_report.html  (if configured)
```

In multi-region mode:
```
Plots/exp1-exp2_DATE/
├── EU/
│   └── evaltools_*.png
├── US_CASTNET/
│   └── evaltools_*.png
└── combined_evaltools_report.html
```

---

## Tips and Best Practices

**Performance**:
- Run qlc-py first to create collocation files
- Evaltools directly uses these files (no re-interpolation)
- This ensures consistency between qlc-py and evaltools plots

**Multi-Experiment Comparison**:
- Evaltools supports comparing 3+ experiments
- All experiments processed together for direct comparison
- Example: `qlc exp1 exp2 exp3 2018-12-01 2018-12-21 evaltools`

**Station Selection**:
- Uses the same station file as qlc-py
- Automatically filters to stations with valid data
- Configure in `qlc_qpy.conf`: `STATION_FILE=...`

**Variable Mapping**:
- QLC automatically maps variable names between:
  - MARS parameters (e.g., "param35.212.192")
  - NetCDF variables (e.g., "var73")
  - User-friendly names (e.g., "NH4_as")
- Evaltools uses the user-friendly names

---

## Troubleshooting

**No plots generated**:
- Ensure qlc-py step completed successfully
- Check for collocated `.nc` files in output directory
- Verify `qlc_evaltools.conf` settings

**Missing statistics**:
- Some metrics require minimum data points
- Check station coverage and time period
- Review evaltools log messages

**Variable not found**:
- Ensure variable is in qlc-py collocation output
- Check variable name mapping in `qlc.conf`
- Verify MARS_RETRIEVALS includes required data

---

## Example Configuration

Minimal `qlc_evaltools.conf`:

```bash
# Source QLC base configuration
source "${CONFIG_DIR}/../qlc.conf"

# Define evaluators to run
EVALUATORS=("time_series" "scatter" "statistics" "taylor" "target")

# Statistical metrics
STATISTICS=("MBE" "RMSE" "MAE" "R2" "FAC2" "FB" "NMSE")

# Time aggregation
TIME_AGGREGATION="daily"  # or hourly, weekly, monthly

# Output format
PLOT_FORMAT="png"
SAVE_HTML_REPORT=true

# Station filtering (optional)
MIN_DATA_POINTS=10
MAX_MISSING_PERCENT=30
```

---

## Further Information

- **QLC Usage Guide**: `qlc/doc/USAGE.md`
- **Task Configuration**: `qlc/config/evaltools/`
- **Integration Examples**: `~/download_evaltools/simple_example_v1.0.6dev/README.md/`
- **Development Docs**: `~/download_evaltools/documentation_v1.0.9/index.html` (full API docs)

---

**Version**: Compatible with QLC v0.4.1+  
**Last Updated**: October 2025  
**Evaltools Version**: 1.0.9+

