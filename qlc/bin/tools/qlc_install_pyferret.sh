#!/usr/bin/env bash

# ============================================================================
# QLC PyFerret Installation Script
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/advanced/pyferret/
#
# Description:
#   Installs PyFerret for 3D global/vertical analysis and visualization.
#   Creates or uses existing venv, tries multiple installation methods
#   (system modules, conda-forge, pip), and verifies installation.
#
# Attribution:
#   PyFerret (NOAA/PMEL)
#   GitHub: https://github.com/NOAA-PMEL/PyFerret
#   Website: https://ferret.pmel.noaa.gov/Ferret/
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_install_pyferret.sh [--force]
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Strict mode for safer bash execution
set -euo pipefail

# Minimal structured logging helpers
log() { printf '%s %s\n' "[$(date +"%Y-%m-%dT%H:%M:%S%z")]" "$*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*"; }
err() { log "ERROR: $*" >&2; }

usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Options:
  --venv DIR              Path to create/use the virtualenv (default: current environment)
  --force                  Force reinstallation even if already installed
  --method METHOD          Installation method: auto, system, conda, pip, conda-env, venv, conda-venv (default: auto)
  --conda-cmd CMD         Conda command to use: conda, mamba (default: conda)
  --python-module NAME    Lmod Python module to load (default: python3/3.10.10-01)
  --ferret-module NAME    Lmod Ferret module to load (default: ferret/7.6.3)
  --help                  Show this help

Examples:
  $(basename "$0")                                    # Auto-detect best method
  $(basename "$0") --method system                    # Use system PyFerret only
  $(basename "$0") --method conda --conda-cmd mamba   # Use mamba for conda installation
  $(basename "$0") --method conda-env                 # Create dedicated conda environment FERRET_QLC
  $(basename "$0") --method conda-env --force          # Force recreate conda environment FERRET_QLC
  $(basename "$0") --method venv                       # Create dedicated venv ~/venv/pyferret
  $(basename "$0") --method venv --force               # Force recreate dedicated venv
  $(basename "$0") --method conda-venv                 # Create conda-based venv ~/venv/pyferret
  $(basename "$0") --method conda-venv --force          # Force recreate conda-based venv
  $(basename "$0") --venv ~/venv/pyferret --force     # Force reinstall in specific venv
  $(basename "$0") --ferret-module ferret/7.5.0       # Use specific Ferret module

Installation Methods:
  auto       - Try system PyFerret first, then conda, then pip (recommended)
  system     - Only use system PyFerret installation
  conda      - Only use conda/mamba installation in current environment
  conda-env  - Create dedicated conda environment FERRET_QLC with pyferret and ferret_datasets
  venv       - Create dedicated Python venv ~/venv/pyferret with pyferret (HPC-friendly, not recommended for Apple Silicon)
  conda-venv - Create conda-based venv ~/venv/pyferret with pyferret (Apple Silicon compatible)
  pip        - Only use pip installation
EOF
}

VENV_DIR=""
FORCE_INSTALL=0
INSTALL_METHOD="auto"
CONDA_CMD="conda"
PYTHON_MODULE="python3/3.10.10-01"
FERRET_MODULE="ferret/7.6.3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV_DIR="${2:-}"; shift 2;;
    --force)
      FORCE_INSTALL=1; shift;;
    --method)
      INSTALL_METHOD="${2:-}"; shift 2;;
    --conda-cmd)
      CONDA_CMD="${2:-}"; shift 2;;
    --python-module)
      PYTHON_MODULE="${2:-}"; shift 2;;
    --ferret-module)
      FERRET_MODULE="${2:-}"; shift 2;;
    --help|-h)
      usage; exit 0;;
    *)
      err "Unknown option: $1"; usage; exit 1;;
  esac
done

# Validate installation method
case "${INSTALL_METHOD}" in
  auto|system|conda|pip|conda-env|venv|conda-venv)
    ;;
  *)
    err "Invalid installation method: ${INSTALL_METHOD}"; usage; exit 1;;
esac

# Deactivate venv on exit if active
deactivate_venv() {
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    deactivate || true
  fi
}
trap deactivate_venv EXIT

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to detect platform
detect_platform() {
  local platform="unknown"
  local arch="unknown"
  
  # Detect OS
  case "$(uname -s)" in
    Darwin*)
      platform="macos"
      ;;
    Linux*)
      platform="linux"
      ;;
    CYGWIN*|MINGW32*|MSYS*|MINGW*)
      platform="windows"
      ;;
  esac
  
  # Detect architecture
  case "$(uname -m)" in
    x86_64|amd64)
      arch="x86_64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    armv7l)
      arch="arm32"
      ;;
  esac
  
  echo "${platform}-${arch}"
}

# Function to check if PyFerret is available for platform
check_pyferret_availability() {
  local platform_info
  platform_info=$(detect_platform)
  
  case "${platform_info}" in
    macos-arm64)
      info "macOS ARM64 detected: PyFerret requires special installation with CONDA_SUBDIR=osx-64"
      info "This will install x86_64 PyFerret to run under Rosetta 2"
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

# Function to run a command and return success status
run_command() {
  local cmd=("$@")
  if "${cmd[@]}" >/dev/null 2>&1; then
    info "Command succeeded: ${cmd[*]}"
    return 0
  else
    warn "Command failed: ${cmd[*]}"
    return 1
  fi
}

# Function to verify PyFerret installation
verify_pyferret() {
  local python_exe="${1:-python}"
  local test_cmd
  
  info "Verifying PyFerret installation..."
  
  # Test 1: Import pyferret
  test_cmd="${python_exe} -c \"import pyferret; print('PyFerret version:', pyferret.__version__)\""
  if eval "${test_cmd}" >/dev/null 2>&1; then
    local version_output
    version_output=$(eval "${test_cmd}" 2>/dev/null)
    info "PyFerret import test passed: ${version_output}"
  else
    warn "PyFerret import test failed"
    return 1
  fi
  
  # Test 2: Try to run pyferret command (with timeout)
  test_cmd="${python_exe} -c \"import pyferret; pyferret.run('quit')\""
  if timeout 30 bash -c "${test_cmd}" >/dev/null 2>&1; then
    info "PyFerret command execution test passed"
    return 0
  else
    warn "PyFerret command execution test failed or timed out"
    return 1
  fi
}

# Function to check for system PyFerret
check_system_pyferret() {
  info "Checking for system PyFerret installation..."
  
  local system_paths=(
    "/usr/bin/pyferret"
    "/usr/local/bin/pyferret"
    "/opt/bin/pyferret"
    "/opt/local/bin/pyferret"
    "/opt/homebrew/bin/pyferret"
    "/opt/PyFerret/bin/pyferret"
    "${HOME}/.local/bin/pyferret"
  )
  
  for path in "${system_paths[@]}"; do
    if [[ -f "${path}" ]]; then
      info "Found system PyFerret at: ${path}"
      if run_command "${path}" --version; then
        info "System PyFerret is functional"
        return 0
      else
        warn "System PyFerret found but not functional"
      fi
    fi
  done
  
  return 1
}

# Function to check for module system PyFerret
check_module_pyferret() {
  info "Checking for Ferret module system..."
  
  if command_exists module; then
    info "Module system detected, checking for Ferret module..."
    if module avail "${FERRET_MODULE}" >/dev/null 2>&1; then
      info "Ferret module available: ${FERRET_MODULE}"
      return 0
    else
      warn "Ferret module not available: ${FERRET_MODULE}"
    fi
  else
    warn "Module system not available"
  fi
  
  return 1
}

# Function to create dedicated conda environment for PyFerret
create_pyferret_conda_env() {
  local force="${1:-0}"
  local env_name="FERRET_QLC"
  
  info "Creating dedicated conda environment for PyFerret..."
  
  # Check if conda command exists
  if ! command_exists "${CONDA_CMD}"; then
    err "${CONDA_CMD} command not found"
    return 1
  fi
  
  info "Using ${CONDA_CMD} for environment creation"
  
  # Check if environment already exists
  local env_exists=0
  if eval "${CONDA_CMD} env list" | grep -q "^${env_name}"; then
    env_exists=1
  fi
  
  if [[ ${env_exists} -eq 1 ]] && [[ ${force} -eq 0 ]]; then
    info "Conda environment '${env_name}' already exists"
    info "Use --force to recreate the environment"
    return 0
  elif [[ ${env_exists} -eq 1 ]] && [[ ${force} -eq 1 ]]; then
    info "Force recreation requested, removing existing environment '${env_name}'..."
    if ! eval "${CONDA_CMD} env remove -n ${env_name} -y" >/dev/null 2>&1; then
      warn "Failed to remove existing environment"
    fi
  fi
  
  # Create the environment
  info "Creating conda environment '${env_name}' with PyFerret and ferret_datasets..."
  
  # Check platform for Apple Silicon support
  local platform_info
  platform_info=$(detect_platform)
  
  if [[ "${platform_info}" == "macos-arm64" ]]; then
    info "macOS ARM64 detected: Using CONDA_SUBDIR=osx-64 for PyFerret installation"
    info "This installs x86_64 PyFerret to run under Rosetta 2"
    
    # Use Apple Silicon specific method
    info "Running: CONDA_SUBDIR=osx-64 ${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    info "This may take several minutes to download and install packages..."
    
    if CONDA_SUBDIR=osx-64 eval "${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"; then
      info "Command succeeded: CONDA_SUBDIR=osx-64 ${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
      info "Conda environment '${env_name}' created successfully!"
      info "To activate the environment, run: conda activate ${env_name}"
      return 0
    else
      err "Command failed: CONDA_SUBDIR=osx-64 ${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    fi
  else
    # Standard conda environment creation for other platforms
    info "Running: ${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    info "This may take several minutes to download and install packages..."
    
    if eval "${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"; then
      info "Command succeeded: ${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
      info "Conda environment '${env_name}' created successfully!"
      info "To activate the environment, run: conda activate ${env_name}"
      return 0
    else
      err "Command failed: ${CONDA_CMD} create -n ${env_name} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    fi
  fi
  
  return 1
}

# Function to create dedicated Python venv for PyFerret
create_pyferret_venv() {
  local force="${1:-0}"
  local venv_path="${HOME}/venv/pyferret"
  
  info "Creating dedicated Python virtual environment for PyFerret..."
  
  # Check if venv already exists
  if [[ -d "${venv_path}" ]] && [[ ${force} -eq 0 ]]; then
    info "Python virtual environment '${venv_path}' already exists"
    info "Use --force to recreate the environment"
    return 0
  elif [[ -d "${venv_path}" ]] && [[ ${force} -eq 1 ]]; then
    info "Force recreation requested, removing existing venv '${venv_path}'..."
    rm -rf "${venv_path}"
  fi
  
  # Create the venv
  info "Creating Python virtual environment: ${venv_path}"
  if python3 -m venv "${venv_path}"; then
    info "Virtual environment created successfully"
  else
    err "Failed to create virtual environment"
    return 1
  fi
  
  # Activate venv and install PyFerret
  info "Activating virtual environment and installing PyFerret..."
  source "${venv_path}/bin/activate"
  
  # Upgrade pip first
  info "Upgrading pip..."
  if ! python -m pip install --upgrade pip >/dev/null 2>&1; then
    warn "Failed to upgrade pip, continuing anyway"
  fi
  
  # Check platform for Apple Silicon support
  local platform_info
  platform_info=$(detect_platform)
  
  if [[ "${platform_info}" == "macos-arm64" ]]; then
    info "macOS ARM64 detected: PyFerret via pip may not work properly"
    info "Trying pip installation first, but conda method is recommended for Apple Silicon"
  fi
  
  # Install PyFerret via pip
  info "Installing PyFerret via pip..."
  if python -m pip install pyferret >/dev/null 2>&1; then
    info "PyFerret installed via pip successfully!"
  else
    # Try with conda-forge channel
    info "Direct pip installation failed, trying conda-forge channel..."
    if python -m pip install --extra-index-url https://pypi.anaconda.org/conda-forge/simple pyferret >/dev/null 2>&1; then
      info "PyFerret installed via conda-forge pip successfully!"
    else
      if [[ "${platform_info}" == "macos-arm64" ]]; then
        err "PyFerret installation failed in virtual environment on Apple Silicon"
        err "PyFerret via pip is not reliable on macOS ARM64"
        err "Recommended: Use --method conda-env instead for Apple Silicon systems"
        err "This creates a conda environment with x86_64 PyFerret under Rosetta 2"
      else
        err "PyFerret installation failed in virtual environment"
      fi
      return 1
    fi
  fi
  
  # Test installation
  if verify_pyferret "${venv_path}/bin/python"; then
    info "PyFerret virtual environment created successfully!"
    info "Virtual environment location: ${venv_path}"
    info "To activate: source ${venv_path}/bin/activate"
    info "To use PyFerret: python -c 'import pyferret'"
    return 0
  else
    if [[ "${platform_info}" == "macos-arm64" ]]; then
      err "PyFerret installation verification failed in virtual environment on Apple Silicon"
      err "PyFerret via pip is not reliable on macOS ARM64"
      err "Recommended: Use --method conda-env instead for Apple Silicon systems"
      err "This creates a conda environment with x86_64 PyFerret under Rosetta 2"
    else
      err "PyFerret installation verification failed in virtual environment"
    fi
    return 1
  fi
}

# Function to create conda-based venv for PyFerret (Apple Silicon compatible)
create_pyferret_conda_venv() {
  local force="${1:-0}"
  local venv_path="${HOME}/venv/pyferret"
  
  info "Creating conda-based virtual environment for PyFerret..."
  
  # Check if conda command exists
  if ! command_exists "${CONDA_CMD}"; then
    err "${CONDA_CMD} command not found"
    return 1
  fi
  
  # Check if venv already exists
  if [[ -d "${venv_path}" ]] && [[ ${force} -eq 0 ]]; then
    info "Conda-based virtual environment '${venv_path}' already exists"
    info "Use --force to recreate the environment"
    return 0
  elif [[ -d "${venv_path}" ]] && [[ ${force} -eq 1 ]]; then
    info "Force recreation requested, removing existing venv '${venv_path}'..."
    rm -rf "${venv_path}"
  fi
  
  # Create the conda-based venv
  info "Creating conda-based virtual environment: ${venv_path}"
  
  # Check platform for Apple Silicon support
  local platform_info
  platform_info=$(detect_platform)
  
  if [[ "${platform_info}" == "macos-arm64" ]]; then
    info "macOS ARM64 detected: Using CONDA_SUBDIR=osx-64 for PyFerret installation"
    info "This installs x86_64 PyFerret to run under Rosetta 2"
    
    # Use Apple Silicon specific method
    info "Running: CONDA_SUBDIR=osx-64 ${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    info "This may take several minutes to download and install packages..."
    
    if CONDA_SUBDIR=osx-64 eval "${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"; then
      info "Command succeeded: CONDA_SUBDIR=osx-64 ${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    else
      err "Command failed: CONDA_SUBDIR=osx-64 ${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
      return 1
    fi
  else
    # Standard conda-based venv creation for other platforms
    info "Running: ${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    info "This may take several minutes to download and install packages..."
    
    if eval "${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"; then
      info "Command succeeded: ${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    else
      err "Command failed: ${CONDA_CMD} create -p ${venv_path} -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
      return 1
    fi
  fi
  
  # Test installation
  if verify_pyferret "${venv_path}/bin/python"; then
    info "Conda-based virtual environment created successfully!"
    info "Virtual environment location: ${venv_path}"
    info "To activate: conda activate ${venv_path}"
    info "To use PyFerret: python -c 'import pyferret'"
    return 0
  else
    err "PyFerret installation verification failed in conda-based virtual environment"
    err "Note: This is a conda environment, activate with: conda activate ${venv_path}"
    return 1
  fi
}

# Function to install PyFerret via conda
install_pyferret_conda() {
  local python_exe="${1:-python}"
  
  info "Installing PyFerret via conda..."
  
  # Check if conda command exists
  if ! command_exists "${CONDA_CMD}"; then
    warn "${CONDA_CMD} command not found"
    return 1
  fi
  
  # Check if we're on macOS ARM64 and need special handling
  local platform_info
  platform_info=$(detect_platform)
  
  if [[ "${platform_info}" == "macos-arm64" ]]; then
    info "macOS ARM64 detected: Using CONDA_SUBDIR=osx-64 for PyFerret installation"
    info "This installs x86_64 PyFerret to run under Rosetta 2"
    
    # Use the Apple Silicon specific method from PyFerret documentation
    info "Running: CONDA_SUBDIR=osx-64 ${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    info "This may take several minutes to download and install packages..."
    
    if CONDA_SUBDIR=osx-64 eval "${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"; then
      info "Command succeeded: CONDA_SUBDIR=osx-64 ${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
      if verify_pyferret "${python_exe}"; then
        info "PyFerret installed via conda (x86_64 under Rosetta 2) successfully!"
        return 0
      else
        warn "PyFerret conda installation failed verification"
      fi
    else
      warn "Command failed: CONDA_SUBDIR=osx-64 ${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    fi
  else
    # Standard conda installation for other platforms
    if eval "${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y" >/dev/null 2>&1; then
      info "Command succeeded: ${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
      if verify_pyferret "${python_exe}"; then
        info "PyFerret installed via conda successfully!"
        return 0
      else
        warn "PyFerret conda installation failed verification"
      fi
    else
      warn "Command failed: ${CONDA_CMD} install -c conda-forge/label/pyferret_dev pyferret ferret_datasets -y"
    fi
  fi
  
  return 1
}

# Function to install PyFerret via pip
install_pyferret_pip() {
  local python_exe="${1:-python}"
  local pip_exe
  
  # Determine pip executable
  if [[ "${python_exe}" == "python" ]]; then
    pip_exe="pip"
  else
    pip_exe="${python_exe} -m pip"
  fi
  
  info "Installing PyFerret via pip..."
  
  # Method 1: Direct pip install
  if eval "${pip_exe} install pyferret" >/dev/null 2>&1; then
    info "Command succeeded: ${pip_exe} install pyferret"
    if verify_pyferret "${python_exe}"; then
      info "PyFerret installed via pip successfully!"
      return 0
    else
      warn "PyFerret pip installation failed verification"
    fi
  else
    warn "Command failed: ${pip_exe} install pyferret"
  fi
  
  # Method 2: Try with conda-forge channel
  info "Direct pip installation failed, trying conda-forge channel..."
  if eval "${pip_exe} install --extra-index-url https://pypi.anaconda.org/conda-forge/simple pyferret" >/dev/null 2>&1; then
    info "Command succeeded: ${pip_exe} install --extra-index-url https://pypi.anaconda.org/conda-forge/simple pyferret"
    if verify_pyferret "${python_exe}"; then
      info "PyFerret installed via conda-forge pip successfully!"
      return 0
    else
      warn "PyFerret conda-forge pip installation failed verification"
    fi
  else
    warn "Command failed: ${pip_exe} install --extra-index-url https://pypi.anaconda.org/conda-forge/simple pyferret"
  fi
  
  # Method 3: Try with specific version constraints
  info "Trying PyFerret installation with version constraints..."
  local versions=(
    "pyferret>=7.6.0,<8.0"
    "pyferret>=7.5.0,<8.0"
    "pyferret>=7.4.0,<8.0"
  )
  
  for version in "${versions[@]}"; do
    if eval "${pip_exe} install ${version}" >/dev/null 2>&1; then
      info "Command succeeded: ${pip_exe} install ${version}"
      if verify_pyferret "${python_exe}"; then
        info "PyFerret installed with version constraint ${version} successfully!"
        return 0
      else
        warn "PyFerret installation with ${version} failed verification"
      fi
    else
      warn "Command failed: ${pip_exe} install ${version}"
    fi
  done
  
  return 1
}

# Function to setup virtual environment
setup_venv() {
  local venv_path="${1:-}"
  local python_exe
  
  if [[ -n "${venv_path}" ]]; then
    info "Setting up virtual environment: ${venv_path}"
    
    # Create venv if it doesn't exist
    if [[ ! -d "${venv_path}" ]]; then
      info "Creating virtual environment: ${venv_path}"
      python3 -m venv "${venv_path}"
    fi
    
    # Activate venv
    source "${venv_path}/bin/activate"
    python_exe="${venv_path}/bin/python"
  else
    # Use current environment
    python_exe="python"
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
      info "Using current virtual environment: ${VIRTUAL_ENV}"
      python_exe="${VIRTUAL_ENV}/bin/python"
    else
      info "Using system Python"
    fi
  fi
  
  echo "${python_exe}"
}

# Main installation function
main() {
  info "Starting PyFerret installation..."
  info "Installation method: ${INSTALL_METHOD}"
  info "Force installation: ${FORCE_INSTALL}"
  
  # Step 1: Load Python module if available
  if command_exists module; then
    info "Loading Python module: ${PYTHON_MODULE}"
    module load "${PYTHON_MODULE}"
  else
    warn "Environment Modules not available; proceeding without 'module load'"
  fi
  
  # Step 2: Setup virtual environment
  local python_exe
  python_exe=$(setup_venv "${VENV_DIR}")
  info "Using Python executable: ${python_exe}"
  
  # If user specified a venv but wants conda environment, automatically switch to conda-env method
  if [[ -n "${VENV_DIR}" ]] && [[ "${INSTALL_METHOD}" == "auto" ]]; then
    info "Note: You specified a virtual environment (${VENV_DIR}) but are using auto method"
    info "Automatically switching to --method conda-env to avoid package conflicts"
    info "This creates a dedicated conda environment 'FERRET_QLC' with PyFerret and ferret_datasets"
    INSTALL_METHOD="conda-env"
  fi
  
  # Step 3: Check if PyFerret is already installed (unless force is specified)
  if [[ ${FORCE_INSTALL} -eq 0 ]]; then
    info "Checking if PyFerret is already installed..."
    if verify_pyferret "${python_exe}"; then
      info "PyFerret is already installed and working"
      info "Skipping PyFerret installation (use --force to reinstall)"
      exit 0
    else
      info "PyFerret not found or not working, proceeding with installation..."
    fi
  else
    info "Force installation requested, removing existing PyFerret installation..."
    # Remove existing PyFerret installation
    local pip_exe
    if [[ "${python_exe}" == "python" ]]; then
      pip_exe="pip"
    else
      pip_exe="${python_exe} -m pip"
    fi
    
    # Uninstall via pip
    info "Uninstalling existing PyFerret via pip..."
    eval "${pip_exe} uninstall pyferret -y" >/dev/null 2>&1 || true
    
    # Remove any symlinks in venv
    local venv_bin
    if [[ "${python_exe}" == "python" ]]; then
      venv_bin="$(dirname "$(which python)")"
    else
      venv_bin="$(dirname "${python_exe}")"
    fi
    
    if [[ -f "${venv_bin}/pyferret" ]]; then
      info "Removing existing PyFerret symlink..."
      rm -f "${venv_bin}/pyferret"
    fi
    
    info "Proceeding with fresh PyFerret installation..."
  fi
  
  # Step 4: Install based on method
  local success=0
  
  # Check if PyFerret is available for this platform
  local platform_info
  platform_info=$(detect_platform)
  info "Detected platform: ${platform_info}"
  
  case "${INSTALL_METHOD}" in
    auto)
      # Try system PyFerret first (skip if force)
      if [[ ${FORCE_INSTALL} -eq 0 ]] && check_system_pyferret; then
        info "Using system PyFerret installation"
        success=1
      elif [[ ${FORCE_INSTALL} -eq 0 ]] && check_module_pyferret; then
        info "Using module system PyFerret"
        success=1
      elif check_pyferret_availability && install_pyferret_conda "${python_exe}"; then
        success=1
      elif check_pyferret_availability && install_pyferret_pip "${python_exe}"; then
        success=1
      fi
      ;;
    system)
      if check_system_pyferret || check_module_pyferret; then
        success=1
      else
        err "System PyFerret not found"
      fi
      ;;
    conda)
      if check_pyferret_availability && install_pyferret_conda "${python_exe}"; then
        success=1
      else
        err "Conda PyFerret installation failed or not available for this platform"
      fi
      ;;
    conda-env)
      if create_pyferret_conda_env "${FORCE_INSTALL}"; then
        success=1
      else
        err "Conda environment creation failed"
      fi
      ;;
    venv)
      if create_pyferret_venv "${FORCE_INSTALL}"; then
        success=1
      else
        err "Virtual environment creation failed"
      fi
      ;;
    conda-venv)
      if create_pyferret_conda_venv "${FORCE_INSTALL}"; then
        success=1
      else
        err "Conda-based virtual environment creation failed"
      fi
      ;;
    pip)
      if check_pyferret_availability && install_pyferret_pip "${python_exe}"; then
        success=1
      else
        err "Pip PyFerret installation failed or not available for this platform"
      fi
      ;;
  esac
  
  # Step 5: Final verification
  if [[ ${success} -eq 1 ]]; then
    if [[ "${INSTALL_METHOD}" == "conda-env" ]]; then
      info "Conda environment 'FERRET_QLC' created successfully!"
      info "PyFerret is ready to use with QLC"
      info "To activate the environment, run: conda activate FERRET_QLC"
      exit 0
    elif [[ "${INSTALL_METHOD}" == "venv" ]]; then
      info "Virtual environment '~/venv/pyferret' created successfully!"
      info "PyFerret is ready to use with QLC"
      info "To activate the environment, run: source ~/venv/pyferret/bin/activate"
      exit 0
    elif [[ "${INSTALL_METHOD}" == "conda-venv" ]]; then
      info "Conda-based virtual environment '~/venv/pyferret' created successfully!"
      info "PyFerret is ready to use with QLC"
      info "To activate the environment, run: conda activate ~/venv/pyferret"
      exit 0
    elif verify_pyferret "${python_exe}"; then
      info "PyFerret installation completed successfully!"
      info "PyFerret is ready to use with QLC"
      exit 0
    else
      err "PyFerret installation verification failed"
    fi
  else
    err "PyFerret installation failed with all methods"
    
    # Provide platform-specific guidance
    local platform_info
    platform_info=$(detect_platform)
    
    case "${platform_info}" in
      macos-arm64)
        err "PyFerret installation failed on macOS ARM64 (Apple Silicon)"
        err "Recommended solutions:"
        err "  1. Use system PyFerret (already detected at /opt/PyFerret/bin/pyferret)"
        err "  2. Install PyFerret manually using: CONDA_SUBDIR=osx-64 conda create -n FERRET_QLC -c conda-forge pyferret ferret_datasets --yes"
        err "  3. Use Rosetta 2 terminal to run x86_64 conda installation"
        err "  4. Disable PyFerret-dependent scripts in QLC configuration"
        err ""
        err "For detailed instructions, see: https://github.com/NOAA-PMEL/PyFerret/blob/master/README.md"
        ;;
      *)
        err "PyFerret may not be available for your platform via pip/conda"
        err "Please try manual installation:"
        err "  conda install -c conda-forge pyferret"
        err "  Or install system PyFerret and ensure it's in PATH"
        err "  Or disable pyferret-dependent scripts in your QLC configuration"
        ;;
    esac
    
    # If force installation failed, try to fall back to system PyFerret
    if [[ ${FORCE_INSTALL} -eq 1 ]]; then
      info "Force installation failed, trying to fall back to system PyFerret..."
      if check_system_pyferret; then
        info "Found working system PyFerret, creating symlink..."
        local venv_bin
        if [[ "${python_exe}" == "python" ]]; then
          venv_bin="$(dirname "$(which python)")"
        else
          venv_bin="$(dirname "${python_exe}")"
        fi
        
        # Find system PyFerret
        local system_paths=(
          "/usr/bin/pyferret"
          "/usr/local/bin/pyferret"
          "/opt/bin/pyferret"
          "/opt/local/bin/pyferret"
          "/opt/homebrew/bin/pyferret"
          "/opt/PyFerret/bin/pyferret"
          "${HOME}/.local/bin/pyferret"
        )
        
        for path in "${system_paths[@]}"; do
          if [[ -f "${path}" ]]; then
            # Clean up any existing symlink first
            [[ -L "${venv_bin}/pyferret" ]] && rm -f "${venv_bin}/pyferret"
            ln -sf "${path}" "${venv_bin}/pyferret"
            info "System PyFerret linked to venv: ${path}"
            if verify_pyferret "${python_exe}"; then
              info "System PyFerret fallback successful!"
              exit 0
            fi
          fi
        done
      fi
    fi
  fi
  
  exit 1
}

# Run main function
main "$@"
