# QLC Quick Start Guide

For complete installation options and detailed instructions, see the online documentation:  
**https://docs.researchconcepts.io/qlc/latest/getting-started/installation**

---

## 1. One-Command Installation (using qlc_install.sh)

The `qlc_install.sh` script performs four tasks:
- a) Creates a QLC virtual environment (`~/venv/qlc`)
- b) Installs QLC from latest PyPI release (`pip install rc-qlc`)
- c) Installs all required tools (cartopy data, evaltools, etc.)
- d) Sets up QLC runtime environment with links to shared directories (`$SCRATCH`, `$HPCPERM`, `$PERM`)

### Optional: Define HPC Paths

```bash
export SCRATCH="/ec/res4/scratch/$USER"
export HPCPERM="/ec/res4/hpcperm/$USER"
export PERM="/perm/$USER"
```

### Test Mode (local/example data)

```bash
curl -sSL https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh | bash -s -- --mode test --tools essential
```

Continue with section 3.

### Production Mode (HPC/ATOS using MARS archive)

```bash
curl -sSL https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh | bash -s -- --mode cams --tools essential
```

Continue with section 5.

---

## 2. Or download and Install Locally

Download the installer and run it locally (e.g., for production mode):

```bash
cd $SCRATCH
curl -O https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh
bash qlc_install.sh --mode cams --tools essential
```

Continue with section 5.

---

## 3. Test QLC Installation

### Activate QLC environment

```bash
source ~/venv/qlc/bin/activate
```

### Verify installation

```bash
cd ~/qlc/run
pwd -P
qlc --version
qlc --help
```

### Run first test

```bash
qlc b2ro b2rn 2018-12-01 2018-12-21 test
```

Continue with section 4.

---

## 4. Switch to Production Mode (HPC)

To switch from test mode to CAMS production mode:

```bash
qlc-install --mode cams
```

This links `~/qlc` to `$PERM/qlc_pypi/v1.0.1-beta/cams`.

Continue with section 5.

---

## 5. Execute QLC (local/HPC) or SQLC (HPC/ATOS)

### Basic usage

```bash
cd ~/qlc/run
pwd -P
qlc --version
qlc --help
```

### Search and inspect variables

```bash
qlc-vars search O3
qlc-vars info O3
```

### Bash execution (workflow test for quick execution)

```bash
qlc b2ro b2rn 2018-12-01 2018-12-21 test
```

### Batch submission (complete analysis with downloads of required data from MARS archive using dependency job)

```bash
sqlc b2ro b2rn 2018-12-01 2018-12-21 test
```

### Analysis options

Observation only (quick test without model comparison):
```bash
sqlc b2ro b2rn 2018-12-01 2018-12-21 test --obs-only
```

Model results only (quick test without observation comparison):
```bash
sqlc b2ro b2rn 2018-12-01 2018-12-21 test --mod-only
```

With command line overrides (class, vars, region):
```bash
sqlc b2ro b2rn 2018-12-01 2018-12-21 test -class=nl,nl -vars="pl:O3,210203" -region=EU
```

With command line overrides (class, param, myvar, levtype, region):
```bash
sqlc b2ro b2rn 2018-12-01 2018-12-21 test -class=nl,nl -param=72.210,73.210 -myvar=PM1,PM2p5 -levtype=sfc -region=EU
```

### View results

GRIB data downloaded from MARS:
```bash
ls -lrth ~/qlc/Results
```

NetCDF data processed (converted from GRIB):
```bash
ls -lrth ~/qlc/Analysis
```

Plot results for active workflow:
```bash
ls -lrth ~/qlc/Plots/b2ro-b2rn*
```

Reports produced (one PDF per variable, region):
```bash
ls -lrth ~/qlc/Presentations
```

Continue with section 9 or 10.

---

## 6. Developer Mode (using local wheel)

### Setup

```bash
source ~/.profile  # if needed
```

### Define wheel and paths

```bash
WPATH=~/qlc_wheels
WHEEL=$WPATH/rc_qlc-1.0.1b0-cp310-cp310-macosx_10_9_universal2.whl  # macOS
WHEEL=$WPATH/rc_qlc-1.0.1b0-cp310-cp310-linux_x86_64.whl            # Linux
```

### Define installation mode

```bash
mode="cams"  # HPC/ATOS
mode="test"  # local/tests with example data

echo "Using $WHEEL and installation mode=$mode"
```

### Clean up previous venv (optional)

```bash
cd                              # start in home directory
deactivate                      # deactivate active venv if active
mv ~/venv/qlc ~/venv/qlc_backup # backup previous venv if it exists
```

### First-time installation from wheel

```bash
bash $WPATH/qlc_install.sh --mode $mode --wheel $WHEEL --tools essential
```

### Quick re-install (QLC only, keeps dependencies)

```bash
bash $WPATH/qlc_install.sh --mode $mode --wheel $WHEEL --qlc-only
```

**Note:** Type `y` to continue with reinstallation of `~/venv/qlc`, or `n` to avoid venv reinstallation (faster for QLC source updates only).

Continue with section 3 or 5.

---

## 7. Install Additional Tools (if needed)

### Activate QLC environment

```bash
source ~/venv/qlc/bin/activate
```

### Check current installation

```bash
qlc-install-tools --help
qlc-install-tools --check
```

### Install individual tools

Install evaltools (if missing):
```bash
qlc-install-tools --install-evaltools         # Install with NumPy 2.x compatibility
qlc-install-tools --install-evaltools --force # Force reinstall
```

Install Cartopy data (if missing):
```bash
qlc-install-tools --install-cartopy           # Download Natural Earth data
```

Install PyFerret (if missing):
```bash
qlc-install-tools --install-pyferret          # Install PyFerret
qlc-install-tools --install-pyferret --force  # Force reinstall
```

Install Bash 5.x (if needed for QLC operation):
```bash
qlc-install-tools --install-bash              # Install Bash 5.x into venv
```

### Verify installation

```bash
qlc-install-tools --check
```

Continue with section 8.

---

## 8. Test QLC Execution

Continue with section 3 or 5.

---

## 9. Documentation

- **Online Docs:**    https://docs.researchconcepts.io/qlc/latest/
- **Installation:**   https://docs.researchconcepts.io/qlc/latest/getting-started/installation/
- **Quick Start:**    https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/
- **Usage Guide:**    https://docs.researchconcepts.io/qlc/latest/user-guide/usage/
- **GitHub:**         https://github.com/researchConcepts/qlc
- **PyPI:**           https://pypi.org/project/rc-qlc/

---

## 10. Questions/Comments

**BETA RELEASE:** Under development, requires further testing.

© 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.

Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
