#!/bin/bash -e
umask 0022

# ============================================================================
# QLC Enhanced Installation Wrapper
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/getting-started/installation/
#
# Description:
#   Enhanced pip installation wrapper with automatic virtual environment
#   management, smart version detection, and integrated tool setup.
#
# Usage:
#   qlc-install-enhanced [package] [options]
#   Example: qlc-install-enhanced rc-qlc[test]
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================
#

SCRIPT="$0"

# ----------------------------------------------------------------------------------------
# Check if help is needed first
# ----------------------------------------------------------------------------------------
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "________________________________________________________________________________________"
  echo "QLC Enhanced Installation"
  echo "----------------------------------------------------------------------------------------"
  echo ""
  echo "Usage:"
  echo "  qlc-install-enhanced [package] [options]"
  echo ""
  echo "Smart Installation Commands:"
  echo "  qlc-install-enhanced rc-qlc                    # → Creates ~/venv/qlc"
  echo "  qlc-install-enhanced rc-qlc[dev]               # → Creates ~/venv/qlc-dev"
  echo "  qlc-install-enhanced rc-qlc[0.4.1]            # → Creates ~/venv/qlc-0.4.1"
  echo "  qlc-install-enhanced rc-qlc[test]              # → Creates ~/venv/qlc + test mode + tools"
  echo "  qlc-install-enhanced rc-qlc[cams]              # → Creates ~/venv/qlc + cams mode + tools"
  echo "  qlc-install-enhanced rc-qlc[dev]               # → Creates ~/venv/qlc-dev + dev mode + tools"
  echo "  qlc-install-enhanced rc-qlc[0.4.1,cams]        # → Creates ~/venv/qlc-0.4.1 + cams mode + tools"
  echo ""
  echo "Options:"
  echo "  --mode <mode>           Installation mode: test, cams, dev (default: test)"
  echo "  --version <version>    Specific QLC version to install"
  echo "  --extras <extras>      Comma-separated list of extras to install"
  echo "  --venv-name <name>     Virtual environment name"
  echo "  --python <path>        Python executable to use"
  echo ""
  echo "Examples:"
  echo "  # Basic installation"
  echo "  qlc-install-enhanced rc-qlc"
  echo ""
  echo "  # Development installation with tools"
  echo "  qlc-install-enhanced rc-qlc[dev]"
  echo ""
  echo "  # Specific version with cams mode"
  echo "  qlc-install-enhanced rc-qlc[0.4.3,cams]"
  echo ""
  echo "  # Custom venv name"
  echo "  qlc-install-enhanced rc-qlc --venv-name my-qlc"
  echo ""
  echo "Platform Support:"
  echo "  - macOS: Uses system Python or framework Python"
  echo "  - Linux: Uses system Python"
  echo "  - Windows: Uses system Python"
  echo "  - HPC (ATOS): Uses module-loaded Python with --no-cache-dir"
  echo ""
  echo "Post-Installation:"
  echo "  The installer automatically:"
  echo "  - Creates virtual environment with Python 3.10+"
  echo "  - Installs QLC package and dependencies"
  echo "  - Sets up QLC runtime structure"
  echo "  - Installs required tools (if specified)"
  echo "  - Creates activation script with aliases"
  echo ""
  echo "Usage After Installation:"
  echo "  source ~/venv/qlc/bin/activate"
  echo "  qlc --help"
  echo "  qlc b2ro b2rn 2018-12-01 2018-12-21 test"
  echo "________________________________________________________________________________________"
  exit 0
fi

# ----------------------------------------------------------------------------------------
# Parse package specification
# ----------------------------------------------------------------------------------------
PACKAGE="rc-qlc"
MODE="test"
VERSION=""
EXTRAS=""
VENV_NAME=""
PYTHON_CMD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --extras)
            EXTRAS="$2"
            shift 2
            ;;
        --venv-name)
            VENV_NAME="$2"
            shift 2
            ;;
        --python)
            PYTHON_CMD="$2"
            shift 2
            ;;
        -*)
            echo "[ERROR] Unknown option: $1"
            echo "Run 'qlc-install-enhanced --help' for usage information"
            exit 1
            ;;
        *)
            PACKAGE="$1"
            shift
            ;;
    esac
done

# ----------------------------------------------------------------------------------------
# Extract mode and extras from package specification
# ----------------------------------------------------------------------------------------
if [[ "$PACKAGE" =~ \[([^\]]+)\] ]]; then
    # Extract extras from package specification
    EXTRAS_FROM_PACKAGE="${BASH_REMATCH[1]}"
    
    # Check if extras contain mode specifications
    if [[ "$EXTRAS_FROM_PACKAGE" =~ (test|cams|dev) ]]; then
        MODE="${BASH_REMATCH[1]}"
    fi
    
    # Check if extras contain version specifications
    if [[ "$EXTRAS_FROM_PACKAGE" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        VERSION="${BASH_REMATCH[1]}"
    fi
    
    # Remove mode and version from extras, keep other extras
    EXTRAS_CLEANED=$(echo "$EXTRAS_FROM_PACKAGE" | sed -E 's/(test|cams|dev|,?[0-9]+\.[0-9]+\.[0-9]+)//g' | sed 's/^,//' | sed 's/,$//')
    if [ -n "$EXTRAS_CLEANED" ]; then
        EXTRAS="$EXTRAS_CLEANED"
    fi
fi

# Determine virtual environment name
if [ -n "$VENV_NAME" ]; then
    VENV_NAME="$VENV_NAME"
elif [ "$MODE" = "dev" ]; then
    VENV_NAME="qlc-dev"
elif [ -n "$VERSION" ]; then
    VENV_NAME="qlc-$VERSION"
else
    VENV_NAME="qlc"
fi

echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Enhanced Installation Starting..."
echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Package: $PACKAGE"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Mode: $MODE"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Version: ${VERSION:-latest}"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Extras: ${EXTRAS:-none}"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] [QLC] Virtual Environment: $VENV_NAME"

# ----------------------------------------------------------------------------------------
# Run enhanced installation
# ----------------------------------------------------------------------------------------
# Find the enhanced installation script
SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
ENHANCED_SCRIPT="$SCRIPT_DIR/qlc_install_enhanced.py"

if [ ! -f "$ENHANCED_SCRIPT" ]; then
    echo "[ERROR] Enhanced installation script not found: $ENHANCED_SCRIPT"
    exit 1
fi

# Run the enhanced installation
python3 "$ENHANCED_SCRIPT" "$PACKAGE" \
    --mode "$MODE" \
    ${VERSION:+--version "$VERSION"} \
    ${EXTRAS:+--extras "$EXTRAS"} \
    --venv-name "$VENV_NAME" \
    ${PYTHON_CMD:+--python "$PYTHON_CMD"}

exit $?
