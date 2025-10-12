#!/bin/bash
#
# QLC Development Environment Setup Helper
#
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
#log  "----------------------------------------------------------------------------------------"
#
# This script provides helper functions for QLC development.
# Source it to add utility aliases and functions to your shell session.
#
# IMPORTANT: This script requires bash (not sh/dash/zsh) because it uses
# bash-specific features like 'export -f' to export functions.
#
# Usage:
#   bash                                            # Switch to bash if needed
#   source ~/qlc/bin/tools/qlc_dev_env.sh
#
# With conda environments, you typically just need:
#   conda activate qlc-dev # Use development version
#   conda activate qlc     # Use PyPI release version
#

# Detect the QLC development directory
if [ -n "$BASH_SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

QLC_DEV_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "QLC Development Environment Helper"
echo "===================================="
echo ""

# Check if we're in a conda environment
if [ -n "$CONDA_DEFAULT_ENV" ]; then
    echo "✓ Active conda environment: $CONDA_DEFAULT_ENV"
    
    # Check if qlc is available
    if command -v qlc &> /dev/null; then
        QLC_PATH=$(which qlc)
        echo "✓ qlc command found: $QLC_PATH"
        
        # Try to show version
        if qlc --version 2>/dev/null | head -1; then
            echo ""
        fi
    else
        echo "✗ qlc command not found in PATH"
        echo "  Run: pip install -e $QLC_DEV_ROOT"
    fi
else
    echo "⚠ Not in a conda environment"
    echo "  Activate with: conda activate qlc"
fi

echo ""
echo "Useful Commands:"
echo "----------------"
echo "  qlc --version              Show version"
echo "  qlc --help                 Show help"
echo "  qlc-extract-stations      Extract station metadata"
echo "  qlc-inspect-evaluator.sh  Inspect evaluator files"
echo ""
echo "Development Workflow:"
echo "---------------------"
echo "  cd ~/qlc/run"
echo "  qlc b2ro b2rn 2018-12-01 2018-12-21 qpy"
echo "  qlc b2ro b2rn 2018-12-01 2018-12-21 evaltools"
echo ""

# Define helper functions
qlc-rebuild() {
    echo "Rebuilding QLC development version..."
    cd "$QLC_DEV_ROOT" || return 1
    pip install -e ".[dev]" --force-reinstall --no-deps
    echo "✓ Rebuild complete"
}

qlc-test-extract() {
    echo "Testing station extraction tool..."
    qlc-extract-stations \
        --obs-path ~/qlc/obs/data/ver0d \
        --obs-type ebas_daily \
        --obs-version latest \
        --output /tmp/test_stations.csv
}

qlc-find-evaluators() {
    local eval_dir="${1:-$HOME/qlc/Analysis/evaluators}"
    echo "Searching for evaluator files in: $eval_dir"
    find "$eval_dir" -name "*.evaluator.evaltools" -type f 2>/dev/null | head -20
}

qlc-inspect-all() {
    local eval_dir="${1:-$HOME/qlc/Analysis/evaluators}"
    echo "Inspecting all evaluators in: $eval_dir"
    find "$eval_dir" -name "*.evaluator.evaltools" -type f -exec $SCRIPT_DIR/qlc-inspect-evaluator.sh {} \;
}

# Export functions
export -f qlc-rebuild 2>/dev/null
export -f qlc-test-extract 2>/dev/null
export -f qlc-find-evaluators 2>/dev/null
export -f qlc-inspect-all 2>/dev/null

echo "Development Functions Loaded:"
echo "-----------------------------"
echo "  qlc-rebuild                    Rebuild development package after code changes"
echo "  qlc-test-extract              Test station extraction tool"
echo "  qlc-find-evaluators [path]    Find all evaluator files"
echo "  qlc-inspect-all [path]        Inspect all evaluators with detailed output"
echo ""
echo "Examples:"
echo "---------"
echo "  # After editing code, rebuild:"
echo "  qlc-rebuild"
echo ""
echo "  # Test station extraction:"
echo "  qlc-test-extract"
echo ""
echo "  # Find and inspect evaluators:"
echo "  qlc-find-evaluators              # Uses ~/qlc/Analysis/evaluators"
echo "  qlc-inspect-all                  # Inspects all found evaluators"
echo ""
echo "  # Or specify custom directory:"
echo "  qlc-find-evaluators ~/path/to/evaluators"
echo "  qlc-inspect-all ~/path/to/evaluators"
echo ""
echo "For more help, see: $SCRIPT_DIR/README.md"
echo ""
