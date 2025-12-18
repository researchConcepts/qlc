#!/bin/bash

# ============================================================================
# QLC Standalone Installer
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# IMPORTANT: This script installs QLC from PyPI (https://pypi.org/project/rc-qlc/)
#            using 'pip install rc-qlc' into a safe virtual environment.
#            For testing, it can also install from a local wheel file.
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/getting-started/installation/
#
# Description:
#   Complete, safe installation of QLC from PyPI or local wheel file.
#   Provides automatic environment detection, Python 3.10+ setup, virtual
#   environment creation, package installation, and runtime configuration.
#
#   Repository: https://github.com/researchConcepts/qlc
#   PyPI Package: https://pypi.org/project/rc-qlc/
#
# Usage:
# - One-Line Installation
#   Install QLC from PyPI in test mode for evaluation and testing
#   curl -sSL https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh | bash -s -- --mode test
#
# - Or Download First
#   Download the installer and run it locally
#   curl -O https://raw.githubusercontent.com/researchConcepts/qlc/main/qlc/bin/tools/qlc_install.sh
#
# - Installation Modes
#   bash qlc_install.sh --mode test # Testing and evaluation (recommended for first-time users)
#   bash qlc_install.sh --mode cams # Operational CAMS environment (requires HPC access)
#   bash qlc_install.sh --mode dev  # Development and parallel testing
#
# - Install from local wheel (development / testing)
#   bash qlc_install.sh --mode test --wheel /path/to/rc_qlc-1.0.1b0-*.whl
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script version
SCRIPT_VERSION="0.4.3"

# Default values
MODE="test"
VERSION=""
WHEEL=""
TOOLS=""
VENV_NAME=""
PYTHON_CMD=""
FORCE=false
SKIP_VENV_CHECK=false
QLC_ONLY=false

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo ""
}

# Function to show usage
show_usage() {
    cat << EOF
QLC Standalone Installer v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Required (choose one):
  --mode <mode>         Installation mode: test, cams, dev
  --test                Install in test mode (equivalent to --mode test)
  --cams                Install in cams mode (equivalent to --mode cams)
  --dev                 Install in dev mode (equivalent to --mode dev)

Optional:
  --version <version>   Specific QLC version to install (default: latest)
  --wheel <path>        Path to local wheel file (for testing, default: PyPI)
  --qlc-only            Reinstall only QLC package, skip dependencies (fast dev testing)
  --tools <tools>       Auto-install tools: essential, evaltools, pyferret, all (default: none)
  --venv-name <name>    Custom virtual environment name
  --python <path>       Path to Python 3.10+ executable
  --force               Force reinstallation even if QLC exists
  --skip-venv-check     Skip virtual environment safety checks
  -h, --help            Show this help message

Installation Path Configuration (HPC/ATOS):
  QLC installation base:
    \$PERM/qlc_pypi (if \$PERM is set) or \$HOME/qlc_pypi (default)
  
  Essential tools (--tools essential):
    - cdo, ncdump, xelatex, pyferret: via module load (preferred) or system
    - evaltools: installed with NumPy 2.x compatibility
    - cartopy: Natural Earth data pre-downloaded
  
  Data directory mapping:
    CAMS mode (shared across versions):
      ~/qlc/Results       -> \$SCRATCH/qlc_pypi/Results
      ~/qlc/Analysis      -> \$HPCPERM/qlc_pypi/Analysis
      ~/qlc/Plots         -> \$PERM/qlc_pypi/Plots
      ~/qlc/Presentations -> \$PERM/qlc_pypi/Presentations
    
    Test/Dev modes (isolated per version):
      Data directories created within version directory
      Example: \$PERM/qlc_pypi/v1.0.1b0/test/data/Results

  To override default HPC storage paths (optional):
    export PERM="/perm/\$USER"           # Installation base + data storage
    export HPCPERM="/ec/res4/hpcperm/\$USER"  # Analysis data storage
    export SCRATCH="/ec/res4/scratch/\$USER"  # Results data storage

  A stable symlink will always be created: \$HOME/qlc -> installation base

Examples:
  # Basic installation from PyPI (both syntaxes work)
  $0 --mode test
  $0 --test

  # Install specific version from PyPI
  $0 --mode test --version 0.4.1

  # Install from local wheel (for testing)
  $0 --mode test --wheel /path/to/rc_qlc-0.4.3-cp310-cp310-macosx_10_9_universal2.whl

  # Install with essential tools (recommended)
  # Includes: cdo, ncdump, xelatex, evaltools, pyferret, cartopy downloads
  # Prefers module load for cdo, ncdump, xelatex, pyferret where available
  $0 --mode test --tools essential

  # Install evaltools only
  $0 --mode test --tools evaltools

  # Install all tools (cdo, ncdump, evaltools, pyferret, cartopy downloads, pyferret, xelatex)
  $0 --mode test --tools all

  # Install from wheel with all tools
  $0 --mode test --wheel /path/to/wheel.whl --tools all

  # Quick reinstall of QLC only (for rapid testing, keeps dependencies)
  $0 --mode test --wheel /path/to/wheel.whl --qlc-only

  # Install with custom venv name
  $0 --mode dev --venv-name my-qlc-dev

  # Install using specific Python
  $0 --mode test --python /usr/bin/python3.10

  # HPC installation with proper paths (both syntaxes work)
  export PERM="/perm/\$USER"
  $0 --mode cams --tools essential
  $0 --cams --tools essential

Installation Modes:
  test    - Standalone mode with bundled example data (recommended for testing)
  cams    - Operational mode for CAMS environments (requires HPC access)
  dev     - Development mode for parallel testing

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --test)
            MODE="test"
            shift
            ;;
        --cams)
            MODE="cams"
            shift
            ;;
        --dev)
            MODE="dev"
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --wheel)
            WHEEL="$2"
            shift 2
            ;;
        --qlc-only)
            QLC_ONLY=true
            shift
            ;;
        --tools)
            TOOLS="$2"
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
        --force)
            FORCE=true
            shift
            ;;
        --skip-venv-check)
            SKIP_VENV_CHECK=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Validate mode
if [[ ! "$MODE" =~ ^(test|cams|dev)$ ]]; then
    print_error "Invalid mode: $MODE"
    print_error "Mode must be one of: test, cams, dev"
    exit 1
fi

# Validate --qlc-only usage
if [[ "$QLC_ONLY" == true ]] && [[ -z "$WHEEL" ]]; then
    print_error "--qlc-only can only be used with --wheel option"
    print_error "This option is for rapid testing with local wheel files"
    exit 1
fi

# Validate wheel file if provided
if [[ -n "$WHEEL" ]]; then
    if [[ ! -f "$WHEEL" ]]; then
        print_error "Wheel file not found: $WHEEL"
        exit 1
    fi
    if [[ ! "$WHEEL" =~ \.whl$ ]]; then
        print_error "Invalid wheel file (must end with .whl): $WHEEL"
        exit 1
    fi
    # Convert to absolute path
    WHEEL=$(cd "$(dirname "$WHEEL")" && pwd)/$(basename "$WHEEL")
    
    # Extract Python version from wheel filename (e.g., cp310 -> 3.10)
    WHEEL_BASENAME=$(basename "$WHEEL")
    if [[ "$WHEEL_BASENAME" =~ -cp([0-9]+)- ]]; then
        WHEEL_PY_VERSION="${BASH_REMATCH[1]}"
        WHEEL_PY_MAJOR="${WHEEL_PY_VERSION:0:1}"
        WHEEL_PY_MINOR="${WHEEL_PY_VERSION:1}"
        REQUIRED_PY_VERSION="${WHEEL_PY_MAJOR}.${WHEEL_PY_MINOR}"
        print_info "Wheel requires Python ${REQUIRED_PY_VERSION}"
    fi
    
    # Warn if both version and wheel are specified
    if [[ -n "$VERSION" ]]; then
        print_warning "Both --version and --wheel specified. Using wheel file, ignoring --version."
        VERSION=""
    fi
fi

# Validate tools parameter if provided
if [[ -n "$TOOLS" ]]; then
    if [[ ! "$TOOLS" =~ ^(essential|evaltools|pyferret|all)$ ]]; then
        print_error "Invalid tools option: $TOOLS"
        print_error "Tools must be one of: essential, evaltools, pyferret, all"
        exit 1
    fi
fi

print_header "QLC Standalone Installer v${SCRIPT_VERSION}"
print_info "Installation mode: $MODE"
if [[ -n "$WHEEL" ]]; then
    print_info "Installation source: Local wheel"
    print_info "Wheel file: $WHEEL"
elif [[ -n "$VERSION" ]]; then
    print_info "Installation source: PyPI"
    print_info "Target version: $VERSION"
else
    print_info "Installation source: PyPI"
    print_info "Target version: latest"
fi

if [[ -n "$TOOLS" ]]; then
    print_info "Additional tools: $TOOLS"
fi

# Detect platform
detect_platform() {
    local os_type=$(uname -s)
    local machine=$(uname -m)
    
    case "$os_type" in
        Darwin*)
            PLATFORM="macos"
            PLATFORM_NAME="macOS"
            ;;
        Linux*)
            PLATFORM="linux"
            PLATFORM_NAME="Linux"
            # Check for HPC environment
            if command -v module &> /dev/null || [[ -n "$SLURM_JOB_ID" ]] || [[ -n "$PBS_JOBID" ]]; then
                IS_HPC=true
                PLATFORM_NAME="Linux (HPC)"
            else
                IS_HPC=false
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="windows"
            PLATFORM_NAME="Windows"
            ;;
        *)
            PLATFORM="unknown"
            PLATFORM_NAME="Unknown"
            ;;
    esac
    
    print_info "Platform detected: $PLATFORM_NAME ($machine)"
}

# Check current environment
check_current_environment() {
    print_info "Checking current environment..."
    
    # Check if we're in a virtual environment
    if [[ -n "$VIRTUAL_ENV" ]]; then
        print_warning "Currently in virtual environment: $VIRTUAL_ENV"
        if [[ "$SKIP_VENV_CHECK" == false ]]; then
            print_warning "This script will create a new venv for QLC"
            read -p "Continue? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Installation cancelled"
                exit 0
            fi
        fi
    fi
    
    # Check if we're in conda
    if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
        print_warning "Currently in conda environment: $CONDA_DEFAULT_ENV"
        if [[ "$SKIP_VENV_CHECK" == false ]]; then
            print_warning "This script will create a new venv for QLC"
            read -p "Continue? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Installation cancelled"
                exit 0
            fi
        fi
    fi
    
    # Detect which python is active
    local active_python=$(which python3 2>/dev/null || which python 2>/dev/null || echo "none")
    if [[ "$active_python" != "none" ]]; then
        local python_version=$($active_python --version 2>&1 | awk '{print $2}')
        print_info "Active Python: $active_python (version $python_version)"
    fi
}

# Find suitable Python 3.10 or 3.11
find_python() {
    print_info "Searching for Python 3.10 or 3.11..."
    
    # If user specified Python, use that
    if [[ -n "$PYTHON_CMD" ]]; then
        if [[ ! -x "$PYTHON_CMD" ]]; then
            print_error "Specified Python not found or not executable: $PYTHON_CMD"
            exit 1
        fi
        
        local version=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
        local major=$(echo $version | cut -d. -f1)
        local minor=$(echo $version | cut -d. -f2)
        
        if [[ $major -eq 3 ]] && [[ $minor -ge 10 ]] && [[ $minor -le 11 ]]; then
            print_success "Using specified Python: $PYTHON_CMD (version $version)"
            return 0
        elif [[ $major -eq 3 ]] && [[ $minor -ge 12 ]]; then
            print_error "Specified Python version $version is not supported (need 3.10 or 3.11)"
            print_error "Python 3.12+ is not supported (no compatible wheel available)"
            exit 1
        else
            print_error "Specified Python version $version is too old (need 3.10 or 3.11)"
            exit 1
        fi
    fi
    
    # Define search paths based on platform
    local python_paths=()
    
    if [[ "$PLATFORM" == "macos" ]]; then
        # If wheel requires specific Python version, prioritize it
        if [[ -n "$REQUIRED_PY_VERSION" ]]; then
            python_paths=(
                "/Library/Frameworks/Python.framework/Versions/${REQUIRED_PY_VERSION}/bin/python3"
                "/opt/homebrew/bin/python${REQUIRED_PY_VERSION}"
                "/usr/local/bin/python${REQUIRED_PY_VERSION}"
                "python${REQUIRED_PY_VERSION}"
            )
        fi
        
        # Add standard search paths (prioritize 3.10 over 3.11)
        python_paths+=(
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3"
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
            "/opt/homebrew/bin/python3.10"
            "/opt/homebrew/bin/python3.11"
            "/usr/local/bin/python3.10"
            "/usr/local/bin/python3.11"
            "python3.10"
            "python3.11"
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
            "/opt/homebrew/bin/python3.12"
            "/usr/local/bin/python3.12"
            "python3.12"
            "python3"
        )
    elif [[ "$PLATFORM" == "linux" ]]; then
        if [[ "$IS_HPC" == true ]]; then
            # Try to load Python module on HPC
            if command -v module &> /dev/null; then
                print_info "HPC environment detected, checking for Python modules..."
                module avail python3 2>&1 | grep -i python || true
                
                # If wheel requires specific version, try that first
                if [[ -n "$REQUIRED_PY_VERSION" ]]; then
                    if module load python3/${REQUIRED_PY_VERSION} 2>/dev/null; then
                        print_success "Loaded Python module: python3/${REQUIRED_PY_VERSION} (matches wheel)"
                        PYTHON_CMD="python3"
                        return 0
                    fi
                fi
                
                # Try to load Python 3.10 or 3.11 (prioritize 3.10)
                for py_version in 3.10 3.11; do
                    if module load python3/${py_version} 2>/dev/null; then
                        print_success "Loaded Python module: python3/${py_version}"
                        PYTHON_CMD="python3"
                        return 0
                    fi
                done
                # Load required system modules first
                module load cdo/2.5.3 netcdf4/4.9.3 hdf5/1.14.6 geos/3.13.1 proj/9.5.1 gdal/3.10.2 texlive/2025 ferret/7.6.3
                module list
            fi
        fi
        
        # If wheel requires specific Python version, prioritize it
        if [[ -n "$REQUIRED_PY_VERSION" ]]; then
            python_paths=(
                "python${REQUIRED_PY_VERSION}"
                "/usr/bin/python${REQUIRED_PY_VERSION}"
            )
        fi
        
        # Add standard search paths (prioritize 3.10 over 3.11)
        python_paths+=(
            "python3.10"
            "python3.11"
            "/usr/bin/python3.10"
            "/usr/bin/python3.11"
            "python3.12"
            "/usr/bin/python3.12"
            "python3"
        )
    elif [[ "$PLATFORM" == "windows" ]]; then
        python_paths=(
            "python3.10"
            "python3.11"
            "py -3.10"
            "py -3.11"
            "python3.12"
            "py -3.12"
            "python"
        )
    fi
    
    # Search for Python 3.10 or 3.11 ONLY
    local found_312plus=""
    local found_312plus_version=""
    local found_older=""
    local found_older_version=""
    
    for python_path in "${python_paths[@]}"; do
        if command -v $python_path &> /dev/null; then
            local version=$($python_path --version 2>&1 | awk '{print $2}')
            local major=$(echo $version | cut -d. -f1)
            local minor=$(echo $version | cut -d. -f2)
            
            if [[ $major -eq 3 ]] && [[ $minor -ge 10 ]] && [[ $minor -le 11 ]]; then
                # Found Python 3.10 or 3.11 - this is what we need
                PYTHON_CMD=$python_path
                print_success "Found Python 3.10-3.11: $python_path (version $version)"
                return 0
            elif [[ $major -eq 3 ]] && [[ $minor -ge 12 ]]; then
                # Track Python 3.12+ for error message
                if [[ -z "$found_312plus" ]]; then
                    found_312plus=$python_path
                    found_312plus_version=$version
                fi
            elif [[ $major -eq 3 ]] && [[ $minor -lt 10 ]]; then
                # Track older Python for error message
                if [[ -z "$found_older" ]]; then
                    found_older=$python_path
                    found_older_version=$version
                fi
            fi
        fi
    done
    
    # No Python 3.10-3.11 found - provide specific error message
    if [[ -n "$found_312plus" ]]; then
        print_error "Found Python $found_312plus_version but QLC requires Python 3.10 or 3.11"
        print_error "Python 3.12+ is not supported (no compatible wheel available)"
        print_installation_guidance
        exit 1
    elif [[ -n "$found_older" ]]; then
        print_error "Found Python $found_older_version but QLC requires Python 3.10 or 3.11"
        print_error "Installation cannot proceed with older Python versions"
        print_installation_guidance
        exit 1
    fi
    
    print_error "No suitable Python executable found"
    print_error "QLC requires Python 3.10 or 3.11"
    print_installation_guidance
    exit 1
}

# Print installation guidance
print_installation_guidance() {
    echo ""
    print_info "Python 3.10 or 3.11 Installation Guide:"
    echo ""
    print_warning "QLC requires Python 3.10 or 3.11 (not 3.12+)"
    echo ""
    
    case "$PLATFORM" in
        macos)
            echo "macOS:"
            echo "  1. Official installer: https://www.python.org/downloads/ (select 3.10 or 3.11)"
            echo "  2. Homebrew: brew install python@3.11"
            echo "  3. pyenv: pyenv install 3.11.0"
            ;;
        linux)
            if [[ "$IS_HPC" == true ]]; then
                echo "HPC (ATOS):"
                echo "  1. Load Python module: module load python3/3.10.10-01"
                echo "  2. Check available modules: module avail python3"
            else
                echo "Linux:"
                echo "  1. Package manager: sudo apt install python3.11"
                echo "  2. Official installer: https://www.python.org/downloads/ (select 3.10 or 3.11)"
                echo "  3. pyenv: curl https://pyenv.run | bash"
            fi
            ;;
        windows)
            echo "Windows:"
            echo "  1. Official installer: https://www.python.org/downloads/ (select 3.10 or 3.11)"
            echo "  2. Microsoft Store: Search for 'Python 3.11'"
            echo "  3. Chocolatey: choco install python311"
            ;;
    esac
    echo ""
}

# Determine venv name
determine_venv_name() {
    if [[ -n "$VENV_NAME" ]]; then
        # User specified custom name
        VENV_PATH="$HOME/venv/$VENV_NAME"
    elif [[ -n "$VERSION" ]]; then
        # Version-specific venv
        VENV_PATH="$HOME/venv/qlc-$VERSION"
    elif [[ "$MODE" == "dev" ]]; then
        # Development venv
        VENV_PATH="$HOME/venv/qlc-dev"
    else
        # Default venv
        VENV_PATH="$HOME/venv/qlc"
    fi
    
    print_info "Virtual environment: $VENV_PATH"
}

# Create virtual environment
create_venv() {
    print_info "Creating virtual environment..."
    
    if [[ -d "$VENV_PATH" ]]; then
        if [[ "$FORCE" == true ]]; then
            print_warning "Removing existing venv: $VENV_PATH"
            rm -rf "$VENV_PATH"
        else
            print_warning "Virtual environment already exists: $VENV_PATH"
            read -p "Remove and recreate? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$VENV_PATH"
            else
                print_info "Using existing virtual environment"
                return 0
            fi
        fi
    fi
    
    # Create venv
    if $PYTHON_CMD -m venv "$VENV_PATH"; then
        print_success "Virtual environment created: $VENV_PATH"
    else
        print_error "Failed to create virtual environment"
        exit 1
    fi
}

# Install QLC
install_qlc() {
    print_info "Installing QLC into virtual environment..."
    
    # Activate venv
    if [[ "$PLATFORM" == "windows" ]]; then
        source "$VENV_PATH/Scripts/activate"
    else
        source "$VENV_PATH/bin/activate"
    fi
    
    # Upgrade pip
    print_info "Upgrading pip..."
    python -m pip install --upgrade pip
    
    # Determine package specification
    local package_spec
    local install_source
    
    if [[ -n "$WHEEL" ]]; then
        # Install from local wheel file
        package_spec="${WHEEL}[${MODE}]"
        install_source="local wheel"
        print_info "Installing QLC from local wheel: $(basename "$WHEEL")"
        print_info "Installation mode: $MODE"
    else
        # Install from PyPI
        package_spec="rc-qlc"
        if [[ -n "$VERSION" ]]; then
            package_spec="rc-qlc==$VERSION"
        fi
        # Add mode-specific extras
        package_spec="${package_spec}[${MODE}]"
        install_source="PyPI"
        print_info "Installing QLC from PyPI: $package_spec"
        print_info "PyPI Package: https://pypi.org/project/rc-qlc/"
    fi
    
    # Build pip install command
    pip_flags=""
    if [[ "$QLC_ONLY" == true ]]; then
        # Quick reinstall: only update QLC, keep dependencies
        print_info "QLC-only mode: reinstalling QLC package without touching dependencies"
        pip_flags="--force-reinstall --no-deps"
    fi
    
    # Add --pre flag for PyPI installations without specific version to include pre-releases
    if [[ -z "$WHEEL" ]] && [[ -z "$VERSION" ]]; then
        pip_flags="$pip_flags --pre"
        print_info "Including pre-release versions (beta, rc, etc.)"
    fi
    
    # Install QLC
    if [[ "$IS_HPC" == true ]]; then
        # HPC-specific installation: avoid CUDA packages by installing deps separately
        print_info "Using HPC-optimized installation (avoiding CUDA packages)"
        
        # Step 1: Extract and install dependencies (excluding CUDA-heavy packages)
        print_info "Extracting dependencies from package metadata..."
        
        # Create a temporary Python script to extract dependencies
        temp_deps_script=$(mktemp)
        cat > "$temp_deps_script" << 'PYTHON_SCRIPT'
import sys
import subprocess
import re

# Packages to exclude (CUDA-heavy or unused)
EXCLUDE_PACKAGES = {'torch', 'torchvision', 'tinycio', 'scikit-fmm'}

try:
    # Get package info
    package_spec = sys.argv[1]
    use_pre = sys.argv[2] if len(sys.argv) > 2 else 'false'
    
    # If we have a wheel file, extract metadata directly without copying
    if package_spec.endswith('.whl'):
        import zipfile
        import json
        from pathlib import Path
        
        with zipfile.ZipFile(package_spec, 'r') as whl:
            # Find METADATA or metadata.json
            metadata_files = [f for f in whl.namelist() if f.endswith('METADATA') or f.endswith('metadata.json')]
            if metadata_files:
                metadata = whl.read(metadata_files[0]).decode('utf-8')
                dependencies = []
                for line in metadata.split('\n'):
                    if line.startswith('Requires-Dist:'):
                        dep = line.split(':', 1)[1].strip()
                        # Remove environment markers
                        dep = re.split(r'[;]', dep)[0].strip()
                        pkg_name = re.split(r'[>=<\[]', dep)[0].strip()
                        if pkg_name.lower() not in EXCLUDE_PACKAGES and dep:
                            dependencies.append(dep)
                
                print(' '.join(f"'{d}'" for d in dependencies))
                sys.exit(0)
    
    # For PyPI packages, download package info without installing
    pip_cmd = [sys.executable, '-m', 'pip', 'download', '--no-deps', '--no-binary', ':all:']
    if use_pre == 'true':
        pip_cmd.append('--pre')
    pip_cmd.append(package_spec)
    result = subprocess.run(
        pip_cmd,
        capture_output=True, text=True, timeout=30
    )
    
    if result.returncode != 0:
        # Fallback: try to get info from already installed package
        result = subprocess.run(
            [sys.executable, '-m', 'pip', 'show', 'rc-qlc'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            # Extract requires from installed package
            for line in result.stdout.split('\n'):
                if line.startswith('Requires:'):
                    deps_str = line.split(':', 1)[1].strip()
                    deps = [d.strip() for d in deps_str.split(',') if d.strip()]
                    filtered_deps = []
                    for dep in deps:
                        pkg_name = re.split(r'[>=<\[]', dep)[0].strip()
                        if pkg_name.lower() not in EXCLUDE_PACKAGES:
                            filtered_deps.append(dep)
                    print(' '.join(f"'{d}'" for d in filtered_deps))
                    sys.exit(0)
    
    # Fallback: use hardcoded essential dependencies (from pyproject.toml v0.4.3)
    print("'numpy>=1.21.0,<2.0' 'pandas>=1.5.0,<3.0' 'matplotlib>=3.5.0,<4.0' 'seaborn>=0.11.0,<1.0' 'xarray>=2022.6.0,<2025.0' 'netCDF4>=1.7.3,<1.8.0' 'h5py>=3.15.1,<3.16.0' 'h5netcdf>=1.7.2,<1.8.0' 'dask[complete]>=2022.6.0,<2025.0' 'scipy>=1.9.0,<2.0' 'cartopy>=0.21.0,<1.0' 'tqdm>=4.64.0,<5.0' 'adjustText>=0.7.0,<0.8.0' 'cftime>=1.6.0,<2.0' 'bottleneck>=1.3.0,<2.0' 'pytinytex>=0.1.0' 'cdo>=1.6.0' 'tomli>=2.0.0'")
    
except Exception as e:
    # Fallback on error
    print("'numpy>=1.21.0,<2.0' 'pandas>=1.5.0,<3.0' 'matplotlib>=3.5.0,<4.0' 'seaborn>=0.11.0,<1.0' 'xarray>=2022.6.0,<2025.0' 'netCDF4>=1.7.3,<1.8.0' 'h5py>=3.15.1,<3.16.0' 'h5netcdf>=1.7.2,<1.8.0' 'dask[complete]>=2022.6.0,<2025.0' 'scipy>=1.9.0,<2.0' 'cartopy>=0.21.0,<1.0' 'tqdm>=4.64.0,<5.0' 'adjustText>=0.7.0,<0.8.0' 'cftime>=1.6.0,<2.0' 'bottleneck>=1.3.0,<2.0' 'pytinytex>=0.1.0' 'cdo>=1.6.0' 'tomli>=2.0.0'")
PYTHON_SCRIPT
        
        # Extract dependencies
        # Pass 'true' if we're using --pre flag for pre-releases
        use_pre_flag="false"
        if [[ -z "$WHEEL" ]] && [[ -z "$VERSION" ]]; then
            use_pre_flag="true"
        fi
        deps_to_install=$(python "$temp_deps_script" "$package_spec" "$use_pre_flag")
        rm -f "$temp_deps_script"
        
        print_info "Installing essential dependencies (excluding CUDA-heavy packages)..."
        if eval "python -m pip install --no-cache-dir $deps_to_install"; then
            print_success "Essential dependencies installed"
        else
            print_error "Failed to install essential dependencies"
            exit 1
        fi
        
        # Step 2: Install QLC without dependencies (deps already installed)
        print_info "Installing QLC package (dependencies already satisfied)..."
        if python -m pip install --no-cache-dir --no-deps $pip_flags "$package_spec"; then
            print_success "QLC installed successfully from $install_source"
        else
            print_error "Failed to install QLC from $install_source"
            exit 1
        fi
    else
        # Standard installation (includes all dependencies including torch/torchvision)
        if python -m pip install $pip_flags "$package_spec"; then
            print_success "QLC installed successfully from $install_source"
        else
            print_error "Failed to install QLC from $install_source"
            exit 1
        fi
    fi
}

# Run QLC setup
run_qlc_setup() {
    print_info "Running QLC runtime setup..."
    
    # Activate venv
    if [[ "$PLATFORM" == "windows" ]]; then
        source "$VENV_PATH/Scripts/activate"
    else
        source "$VENV_PATH/bin/activate"
    fi
    
    # Run qlc-install
    if qlc-install --mode "$MODE"; then
        print_success "QLC runtime setup completed"
    else
        print_warning "QLC runtime setup had issues (this may be expected)"
    fi
}

# Create activation script
create_activation_script() {
    print_info "Creating activation helper script..."
    
    local activate_script="$VENV_PATH/bin/qlc-activate.sh"
    
    cat > "$activate_script" << EOF
#!/bin/bash
# QLC Environment Activation Script
# Generated by QLC Standalone Installer v${SCRIPT_VERSION}

# Activate the virtual environment
source "$VENV_PATH/bin/activate"

# Set up QLC aliases
alias cdp='cd \${PERM:-\$HOME}'
alias cdq='cd \$HOME/qlc'  # Always use $HOME/qlc (stable symlink)
alias cdr='cd \$HOME/qlc/run'  # Always use $HOME/qlc/run (via stable symlink)

# Display QLC information
echo "QLC Environment Activated"
echo "Virtual Environment: $VENV_PATH"
echo "Mode: $MODE"
echo "QLC Version: \$(qlc --version 2>/dev/null || echo 'unknown')"
echo ""
echo "Useful aliases:"
echo "  cdp  - Change to \\\$PERM directory"
echo "  cdq  - Change to QLC directory"
echo "  cdr  - Change to QLC run directory"
echo ""
echo "To deactivate: deactivate"
EOF
    
    chmod +x "$activate_script"
    print_success "Activation script created: $activate_script"
}

# Print completion message
print_completion() {
    print_header "QLC Installation Completed Successfully!"
    
    echo "Installation Details:"
    echo "  Mode: $MODE"
    echo "  Virtual Environment: $VENV_PATH"
    echo "  Python: $PYTHON_CMD"
    if [[ -n "$VERSION" ]]; then
        echo "  QLC Version: $VERSION"
    fi
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. IMPORTANT: Activate the QLC environment in your current shell:"
    echo ""
    echo "   source $VENV_PATH/bin/activate"
    echo ""
    echo "   Or use the QLC activation script (includes helpful aliases):"
    echo "   source $VENV_PATH/bin/qlc-activate.sh"
    echo ""
    echo "2. Verify installation:"
    echo "   qlc --version"
    echo "   qlc --help"
    echo ""
    echo "3. Check tool availability (optional):"
    echo "   qlc-install-tools --check"
    echo ""
    echo "4. Install evaltools if needed (optional):"
    echo "   qlc-install-tools --install-evaltools"
    echo ""
    echo "5. Start using QLC:"
    echo "   cd ~/qlc/run"
    echo "   qlc b2ro b2rn 2018-12-01 2018-12-21 test"
    echo ""
    echo "  Batch mode (HPC/SLURM):"
    echo "    sqlc b2ro b2rn 2018-12-01 2018-12-21 test"
    echo ""
    echo "For more information:"
    echo "  Quick Start:   ~/qlc/doc/QuickStart.md"
    echo "  Documentation: https://docs.researchconcepts.io/qlc"
    echo "  Getting Started: https://docs.researchconcepts.io/qlc/latest/getting-started/quickstart/"
    echo ""
    print_success "Happy analyzing!"
}

# Install additional tools (evaltools, pyferret)
install_tools() {
    if [[ -z "$TOOLS" ]]; then
        return 0
    fi
    
    print_header "Installing Additional Tools"
    
    # Activate venv first
    if [[ -f "$VENV_PATH/bin/activate" ]]; then
        # shellcheck disable=SC1090
        source "$VENV_PATH/bin/activate"
    else
        print_error "Cannot activate venv to install tools"
        return 1
    fi
    
    case "$TOOLS" in
        essential)
            print_info "Installing essential tools..."
            print_info "Essential includes: cdo, ncdump, xelatex, evaltools, pyferret, cartopy"
            print_info "Preferring module load for: cdo, ncdump, xelatex, pyferret"
            echo ""
            
            print_info "Installing evaltools with NumPy 2.x compatibility..."
            print_info "Running: qlc-install-tools --install-evaltools"
            if qlc-install-tools --install-evaltools; then
                print_success "Evaltools installed successfully"
            else
                print_warning "Evaltools installation had issues (may need manual setup)"
            fi
            
            print_info ""
            print_info "System tools (cdo, ncdump, xelatex, pyferret) will be detected from:"
            print_info "  1. Module system (module load) - preferred on HPC"
            print_info "  2. System installation - fallback"
            print_info ""
            print_info "NOTE: Cartopy Natural Earth data is PRE-DOWNLOADED during installation setup"
            print_info "      This happens automatically - NO runtime downloads will occur"
            print_info ""
            print_info "After installation, run 'qlc-install-tools --check' to verify all tools"
            ;;
        evaltools)
            print_info "Installing evaltools with NumPy 2.x compatibility..."
            if qlc-install-tools --install-evaltools; then
                print_success "Evaltools installed successfully"
            else
                print_warning "Evaltools installation had issues (may need manual setup)"
            fi
            ;;
        xelatex)
            print_info "Installing xelatex..."
            if qlc-install-tools --install-xelatex; then
                print_success "xelatex installed successfully"
            else
                print_warning "xelatex installation had issues (may need manual setup)"
            fi
            ;;
        pyferret)
            print_info "Installing pyferret..."
            if qlc-install-extras --pyferret; then
                print_success "PyFerret installed successfully"
            else
                print_warning "PyFerret installation had issues (may need manual setup)"
            fi
            ;;
        all)
            print_info "Installing all tools (evaltools)..."
            
            print_info "Installing evaltools with NumPy 2.x compatibility..."
            if qlc-install-tools --install-evaltools; then
                print_success "Evaltools installed successfully"
            else
                print_warning "Evaltools installation had issues (may need manual setup)"
            fi
            
            print_info "Skipping xelatex (using module load texlive on ATOS)..."
#             print_info "Installing xelatex..."
#             if qlc-install-tools --install-xelatex; then
#                 print_success "xelatex installed successfully"
#             else
#                 print_warning "xelatex installation had issues (may need manual setup)"
#             fi
            ;;
        all2)
            print_info "Installing all tools (evaltools + xelatex + pyferret)..."
            
            print_info "Installing evaltools with NumPy 2.x compatibility..."
            if qlc-install-tools --install-evaltools; then
                print_success "Evaltools installed successfully"
            else
                print_warning "Evaltools installation had issues (may need manual setup)"
            fi
            
            print_info "Installing xelatex..."
            if qlc-install-tools --install-xelatex; then
                print_success "xelatex installed successfully"
            else
                print_warning "xelatex installation had issues (may need manual setup)"
            fi

            print_info "Installing pyferret..."
            if qlc-install-extras --pyferret; then
                print_success "PyFerret installed successfully"
            else
                print_warning "PyFerret installation had issues (may need manual setup)"
            fi
            ;;
    esac
    
    print_success "Tool installation completed"
}

# Print final activation instructions
print_activation_instructions() {
    echo ""
    echo "================================================================"
    echo ""
    echo "  QLC installation complete! To start using QLC, activate the"
    echo "  virtual environment by running:"
    echo ""
    echo "    source $VENV_PATH/bin/activate"
    echo ""
    echo " To deactivate the environment, run:"
    echo ""
    echo "    deactivate"
    echo ""
    echo "================================================================"
    echo ""
}

# Main installation flow
main() {
    detect_platform
    check_current_environment
    find_python
    determine_venv_name
    create_venv
    install_qlc
    run_qlc_setup
    create_activation_script
    install_tools
    print_completion
    print_activation_instructions
}

# Run main installation
main

