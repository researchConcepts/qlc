# QLC Development Tools

This directory contains utility scripts for QLC development and debugging.


## Quick Start: Using Development Functions

**Step 1: Source the development environment**
```bash
# Switch to bash (required - functions use bash-specific features)
bash

# Navigate to your development directory (e.g., a symlink to ~/qlc_dev/v0.4.1/dev)
cd ~/qlc-dev-run 

# Activate your development conda environment
conda activate qlc

# Source the helper functions
source bin/tools/qlc_dev_env.sh
```

This will display your environment status and load helper functions into your shell.

## Development Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `qlc-rebuild` | Rebuild after code changes | `qlc-rebuild` |
| `qlc-test-extract` | Test station extraction | `qlc-test-extract` |
| `qlc-find-evaluators [path]` | Find evaluator files | `qlc-find-evaluators` |
| `qlc-inspect-all [path]` | Inspect all evaluators | `qlc-inspect-all` |


**Step 2: Use the development functions**
```bash
# After making code changes, rebuild the package
qlc-rebuild

# Test the station extraction tool
qlc-test-extract

# Find evaluator files from your last run
qlc-find-evaluators

# Inspect all evaluator files with detailed output
qlc-inspect-all
```

**Step 3: Test your changes**
```bash
# Navigate to your QLC runtime directory

# Run qlc-py workflow
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy

# Run evaltools workflow
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools

# Inspect the results
qlc-find-evaluators
qlc-inspect-all
```

**Pro Tip:** Add this to your `~/.bashrc` or `~/.zshrc` for automatic loading:
```bash
# Auto-load QLC dev functions when activating qlc environment
if [ "$CONDA_DEFAULT_ENV" = "qlc" ]; then
    [ -f bin/tools/qlc_dev_env.sh ] && \
        source bin/tools/qlc_dev_env.sh
fi
```

---

## Active Tools

### qlc-extract-stations-examples.sh
**Status**: Active  
**Purpose**: Example script demonstrating station extraction usage patterns  
**Usage**:
```bash
# Review and customize the script, then run
bin/tools/qlc-extract-stations-examples.sh
```

**Features**:
- Extracts all stations, urban only, and rural only
- Configurable observation path and version
- Additional commented examples for various use cases
- Useful as a template for your own extraction workflows

### qlc-inspect-evaluator.sh
**Status**: Active (Merged tool)  
**Purpose**: Inspect evaltools evaluator pickle files  
**Usage**:
```bash
# Inspect a single evaluator
bin/tools/qlc-inspect-evaluator.sh Analysis/evaluators/EU_rural_b2rm_20181201-20181221_NH3_daily.evaluator.evaltools

# Inspect all evaluators
find Analysis/evaluators -name "*.evaluator.evaltools" \
     -exec bin/tools/qlc-inspect-evaluator.sh {} \;
```


## Development Workflow

```bash
# 1. Set up environment
conda activate qlc-dev
source bin/tools/qlc_dev_env.sh

# 2. Make code changes
# ... edit files ...

# 3. Rebuild
qlc-rebuild

# 4. Test
cd run
qlc b2ro b2rn 2018-12-01 2018-12-21 qpy
qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools

# 5. Inspect results
qlc-find-evaluators
qlc-inspect-all
```

## Support

For questions or issues:
- Check logs: `log/`
- Enable debug: Set `EVALTOOLS_DEBUG=1` in config
- Contact: Swen Metzger, ResearchConcepts io GmbH, <sm@researchconcepts.io>  