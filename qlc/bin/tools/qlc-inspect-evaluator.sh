#!/bin/bash
#
# QLC Evaluator Inspector
#
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
#log  "----------------------------------------------------------------------------------------"
#
# Inspects evaltools evaluator pickle files and displays their structure
#
# Usage:
#   qlc-inspect-evaluator.sh <evaluator_file>
#   qlc-inspect-evaluator.sh --help
#

show_help() {
    cat << EOF
QLC Evaluator Inspector

Inspects evaltools evaluator pickle files and displays their structure.

Usage:
  qlc-inspect-evaluator.sh <evaluator_file>
  qlc-inspect-evaluator.sh --help

Arguments:
  <evaluator_file>    Path to .evaluator.evaltools file

Examples:
  # Inspect a specific evaluator
  qlc-inspect-evaluator.sh ~/qlc/Analysis/evaluators/Europe_b2ro_20181201-20181221_NH3.evaluator.evaltools

  # Find and inspect all evaluators
  find ~/qlc/Analysis/evaluators -name "*.evaluator.evaltools" -exec qlc-inspect-evaluator.sh {} \;

Requirements:
  - evaltools package must be installed
  - evaltools conda environment (or qlc environment with evaltools)

EOF
    exit 0
}

# Handle help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ -z "$1" ]; then
    show_help
fi

EVALUATOR_FILE="$1"

# Check if file exists
if [ ! -f "$EVALUATOR_FILE" ]; then
    echo "ERROR: File not found: $EVALUATOR_FILE" >&2
    exit 1
fi

# Try to find Python with evaltools
PYTHON_CMD=""

# Check if evaltools environment exists
if command -v conda &> /dev/null; then
    # Try evaltools environment first
    if conda env list | grep -q "^evaltools "; then
        eval "$(conda shell.bash hook)"
        conda activate evaltools 2>/dev/null
        PYTHON_CMD=$(which python 2>/dev/null)
    fi
    
    # Try qlc environment if evaltools not found
    if [ -z "$PYTHON_CMD" ] && conda env list | grep -q "^qlc "; then
        eval "$(conda shell.bash hook)"
        conda activate qlc 2>/dev/null
        PYTHON_CMD=$(which python 2>/dev/null)
    fi
fi

# Fall back to system python
if [ -z "$PYTHON_CMD" ]; then
    if command -v python3 &> /dev/null; then
        PYTHON_CMD=python3
    elif command -v python &> /dev/null; then
        PYTHON_CMD=python
    else
        echo "ERROR: Python not found" >&2
        exit 1
    fi
fi

# Check if evaltools is available
if ! $PYTHON_CMD -c "import evaltools" 2>/dev/null; then
    echo "ERROR: evaltools package not found" >&2
    echo "Please install evaltools following instructions in:" >&2
    echo "  ~/qlc/doc/EVALTOOLS.md" >&2
    echo "Or activate evaltools conda environment: conda activate evaltools" >&2
    exit 1
fi

# Run the inspector Python code inline
$PYTHON_CMD - "$EVALUATOR_FILE" << 'PYTHON_SCRIPT'
import sys
import pickle
import os

evaluator_file = sys.argv[1]

print(f"\n{'='*80}")
print(f"Inspecting: {os.path.basename(evaluator_file)}")
print(f"Full path: {evaluator_file}")
print(f"File size: {os.path.getsize(evaluator_file) / 1024:.2f} KB")
print(f"{'='*80}\n")

try:
    with open(evaluator_file, 'rb') as f:
        evaluator = pickle.load(f)
except Exception as e:
    print(f"ERROR: Failed to load evaluator: {e}", file=sys.stderr)
    sys.exit(1)

print("Evaluator Structure:")
print(f"  Type: {type(evaluator).__name__}")
print(f"  Module: {type(evaluator).__module__}")
print(f"  Has observations: {hasattr(evaluator, 'observations')}")
print(f"  Has simulations: {hasattr(evaluator, 'simulations')}")

# Inspect observations
if hasattr(evaluator, 'observations') and evaluator.observations:
    obs = evaluator.observations
    print(f"\nObservations:")
    print(f"  Type: {type(obs).__name__}")
    
    # Try to get metadata
    if hasattr(obs, 'seriesType'):
        print(f"  Series type: {obs.seriesType}")
    if hasattr(obs, 'species'):
        print(f"  Species: {obs.species}")
    if hasattr(obs, 'dataset') and obs.dataset:
        print(f"  Dataset type: {type(obs.dataset).__name__}")
        if hasattr(obs.dataset, 'data'):
            data = obs.dataset.data
            print(f"  Data shape: {data.shape} (time x stations)")
            print(f"  Stations: {len(data.columns)}")
            print(f"  Time range: {data.index[0]} to {data.index[-1]}")
            print(f"  Sample stations: {', '.join(map(str, list(data.columns[:5])))}...")
            
            # Statistics
            total_values = data.size
            nan_count = data.isna().sum().sum()
            valid_count = total_values - nan_count
            print(f"  Data coverage: {valid_count}/{total_values} ({100*valid_count/total_values:.1f}%)")
            print(f"  NaN count: {nan_count}")
            
            # Value range
            valid_data = data.values[~data.isna().values]
            if len(valid_data) > 0:
                print(f"  Value range: [{valid_data.min():.3f}, {valid_data.max():.3f}]")
                print(f"  Mean: {valid_data.mean():.3f}, Std: {valid_data.std():.3f}")

# Inspect simulations
if hasattr(evaluator, 'simulations') and evaluator.simulations:
    sim = evaluator.simulations
    print(f"\nSimulations:")
    print(f"  Type: {type(sim).__name__}")
    
    if hasattr(sim, 'datasets') and sim.datasets:
        print(f"  Number of models: {len(sim.datasets)}")
        
        for i, ds in enumerate(sim.datasets):
            print(f"\n  Model #{i+1}:")
            print(f"    Type: {type(ds).__name__}")
            
            # Try to get model name/color
            if hasattr(ds, 'name'):
                print(f"    Name: {ds.name}")
            if hasattr(ds, 'color'):
                print(f"    Color: {ds.color}")
            if hasattr(ds, 'seriesType'):
                print(f"    Series type: {ds.seriesType}")
                
            if hasattr(ds, 'data'):
                data = ds.data
                print(f"    Data shape: {data.shape} (time x stations)")
                print(f"    Stations: {len(data.columns)}")
                print(f"    Time range: {data.index[0]} to {data.index[-1]}")
                
                # Statistics
                total_values = data.size
                nan_count = data.isna().sum().sum()
                valid_count = total_values - nan_count
                print(f"    Data coverage: {valid_count}/{total_values} ({100*valid_count/total_values:.1f}%)")
                
                # Value range
                valid_data = data.values[~data.isna().values]
                if len(valid_data) > 0:
                    print(f"    Value range: [{valid_data.min():.3f}, {valid_data.max():.3f}]")
                    print(f"    Mean: {valid_data.mean():.3f}, Std: {valid_data.std():.3f}")

# Check for additional attributes
print(f"\nAdditional Attributes:")
excluded_attrs = ['observations', 'simulations', '__dict__', '__class__', '__module__']
attrs = [attr for attr in dir(evaluator) if not attr.startswith('_') and attr not in excluded_attrs]
if attrs:
    for attr in attrs[:10]:  # Show first 10
        try:
            val = getattr(evaluator, attr)
            if not callable(val):
                print(f"  {attr}: {val}")
        except:
            pass
    if len(attrs) > 10:
        print(f"  ... and {len(attrs)-10} more attributes")
else:
    print("  (none)")

print(f"\n{'='*80}\n")
PYTHON_SCRIPT

exit $?
