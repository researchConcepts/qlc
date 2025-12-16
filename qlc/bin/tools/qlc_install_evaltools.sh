#!/usr/bin/env bash

# ============================================================================
# QLC Evaltools Installation Script
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/advanced/evaltools/
#
# Description:
#   Installs evaltools 1.0.9 statistical analysis package from CNRS/Météo-France.
#   Creates or uses existing venv, pins known-good dependencies, installs
#   cartopy with system modules, and applies NumPy 2.x compatibility patches.
#
# Attribution:
#   evaltools (CNRM Open Source by CNRS and Météo-France)
#   https://redmine.umr-cnrm.fr/projects/evaltools/wiki
#
# Usage:
#   bash $HOME/qlc/bin/tools/qlc_install_evaltools.sh
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
  --venv DIR              Path to create/use the virtualenv (default: ~/venv/evaltools_109)
  --src PATH_OR_URL       evaltools source directory or .zip (local path) or URL to .zip (default: ./evaltools_1.0.9)
  --python-module NAME    Lmod Python module to load (default: python3/3.10.10-01)
  --geos-module NAME      Lmod GEOS module to try load (default: geos/3.13.1)
  --proj-module NAME      Lmod PROJ module to try load (default: proj/9.5.1)
  --download-official     Fetch evaltools v1.0.9, simple example v1.0.6, and documentation v1.0.9
  --download-dir DIR      Where to download/unpack the official zips (default: ~/evaltools_downloads)
  --no-cartopy            Skip installing cartopy
  --help                  Show this help

Examples:
  $(basename "$0") --src ./evaltools_1.0.9
  $(basename "$0") --src https://redmine.umr-cnrm.fr/attachments/download/5300/evaltools_v1.0.9.zip
  $(basename "$0") --venv ~/venv/evaltools_109 --no-cartopy
  $(basename "$0") --download-official --download-dir ~/evaltools_downloads
EOF
}

VENV_DIR="${HOME}/venv/evaltools_109"
EVALTOOLS_SRC="./evaltools_1.0.9"
PYTHON_MODULE="python3/3.10.10-01"
GEOS_MODULE="geos/3.13.1"
PROJ_MODULE="proj/9.5.1"
INSTALL_CARTOPY=1
DOWNLOAD_OFFICIAL=0
DOWNLOAD_DIR="${HOME}/evaltools_downloads"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV_DIR="${2:-}"; shift 2;;
    --src)
      EVALTOOLS_SRC="${2:-}"; shift 2;;
    --python-module)
      PYTHON_MODULE="${2:-}"; shift 2;;
    --geos-module)
      GEOS_MODULE="${2:-}"; shift 2;;
    --proj-module)
      PROJ_MODULE="${2:-}"; shift 2;;
    --download-official)
      DOWNLOAD_OFFICIAL=1; shift;;
    --download-dir)
      DOWNLOAD_DIR="${2:-}"; shift 2;;
    --no-cartopy)
      INSTALL_CARTOPY=0; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      err "Unknown option: $1"; usage; exit 1;;
  esac
done

# Deactivate venv on exit if active
deactivate_venv() {
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    deactivate || true
  fi
}
trap deactivate_venv EXIT

# Step 0: Load Python module
info "Loading Python module: ${PYTHON_MODULE}"
if command -v module >/dev/null 2>&1; then
  module load "${PYTHON_MODULE}"
else
  warn "Environment Modules not available; proceeding without 'module load'. Ensure Python 3.10 is available."
fi

# Optional: Download official evaltools package, example, and documentation
if [[ ${DOWNLOAD_OFFICIAL} -eq 1 ]]; then
  info "Preparing download directory: ${DOWNLOAD_DIR}"
  mkdir -p "${DOWNLOAD_DIR}"
  cd "${DOWNLOAD_DIR}"
  pwd -P || true

  EVALTOOLS_ZIP="evaltools_v1.0.9.zip"
  EXAMPLE_ZIP="simple_example_v1.0.6.zip"
  DOC_ZIP="documentation_v1.0.9.zip"

  if [[ ! -f "${EVALTOOLS_ZIP}" ]]; then
    info "Downloading evaltools v1.0.9"
    curl -fsSL -o "${EVALTOOLS_ZIP}" "https://redmine.umr-cnrm.fr/attachments/download/5300/evaltools_v1.0.9.zip"
  else
    info "Using existing ${EVALTOOLS_ZIP}"
  fi

  if [[ ! -f "${EXAMPLE_ZIP}" ]]; then
    info "Downloading simple example v1.0.6"
    curl -fsSL -o "${EXAMPLE_ZIP}" "https://redmine.umr-cnrm.fr/attachments/download/4014/simple_example_v1.0.6.zip"
  else
    info "Using existing ${EXAMPLE_ZIP}"
  fi

  if [[ ! -f "${DOC_ZIP}" ]]; then
    info "Downloading documentation v1.0.9"
    curl -fsSL -o "${DOC_ZIP}" "https://redmine.umr-cnrm.fr/attachments/download/5298/documentation_v1.0.9.zip"
  else
    info "Using existing ${DOC_ZIP}"
  fi

  if [[ ! -d evaltools_1.0.9 ]]; then
    info "Unzipping evaltools"
    unzip -q "${EVALTOOLS_ZIP}"
  fi

  if [[ ! -d simple_example_v1.0.6 ]]; then
    info "Unzipping simple example"
    unzip -q "${EXAMPLE_ZIP}"
  fi

  if [[ ! -d documentation_v1.0.9 ]]; then
    info "Unzipping documentation"
    unzip -q "${DOC_ZIP}" -d documentation_v1.0.9
  fi

  # Prefer the freshly downloaded source as install source
  if [[ -d evaltools_1.0.9 ]]; then
    EVALTOOLS_SRC="${DOWNLOAD_DIR}/evaltools_1.0.9"
  fi

  info "Documentation: ${DOWNLOAD_DIR}/documentation_v1.0.9/index.html"
  info "Example: ${DOWNLOAD_DIR}/simple_example_v1.0.6"
  cd - >/dev/null || true
else
  if [[ ! -d "${DOWNLOAD_DIR}" ]]; then
    err "Could not locate download directory ${DOWNLOAD_DIR}. Start again with e.g.:"
    echo "$0 --download-official --download-dir ~/evaltools_downloads"
    exit 1
  fi
  cd "${DOWNLOAD_DIR}"
  pwd -P || true
fi

# Step 1: Create or reuse venv
if [[ -d "${VENV_DIR}" ]]; then
  info "Using existing virtualenv at: ${VENV_DIR}"
else
  info "Creating virtualenv at: ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

# Step 2: Activate venv (with permission check)
info "Activating virtualenv"
if [[ ! -r "${VENV_DIR}/bin/activate" ]]; then
  err "Cannot read ${VENV_DIR}/bin/activate (permissions). Choose a different --venv path or fix permissions."; exit 13
fi
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

# Step 3: Upgrade pip and pin setuptools for Python 3.13 compatibility
info "Upgrading pip and installing modern setuptools; installing wheel"
python -m pip install --upgrade pip
pip install "setuptools>=65.0.0" wheel

# Step 4: Install pinned dependency versions (compatible with Python 3.13 and QLC)
info "Installing pinned dependencies"
pip install "cython>=0.29.32"
pip install "numpy>=1.21.0,<2.0"  # Pin to <2.0 for evaltools compatibility (mean_time_scores)
pip install "scipy>=1.9.0,<2.0"
pip install "matplotlib>=3.5.0,<4.0"
pip install "pandas>=1.5.0,<3.0"
pip install packaging
pip install "pyyaml>=6.0"
pip install "shapely>=2.1.2"
pip install "netCDF4>=1.7.3,<1.8.0"
pip install "h5py>=3.15.1,<3.16.0"
pip install "h5netcdf>=1.7.2,<1.8.0"

# Step 5: Try loading GEOS/PROJ modules and install cartopy (optional)
if [[ ${INSTALL_CARTOPY} -eq 1 ]]; then
  if command -v module >/dev/null 2>&1; then
    info "Attempting to load GEOS and PROJ modules: ${GEOS_MODULE}, ${PROJ_MODULE}"
    module load "${GEOS_MODULE}" || warn "Failed to load ${GEOS_MODULE}; cartopy may still work if libs are in default paths"
    module load "${PROJ_MODULE}" || warn "Failed to load ${PROJ_MODULE}; cartopy may still work if libs are in default paths"
    module list
  fi

  info "Installing cartopy (compatible with matplotlib and shapely)"
  if pip install --no-build-isolation "cartopy>=0.21.0,<1.0"; then
    python - << 'PYTEST'
import cartopy
print("Cartopy installed:", cartopy.__version__)
PYTEST
  else
    warn "Cartopy installation failed; continuing without cartopy (map plots may be unavailable)."
  fi
else
  info "Skipping cartopy installation as requested"
fi

# Step 6: Resolve evaltools source
WORKDIR="$(pwd)"
SRC_DIR=""
echo "WORKDIR: ${WORKDIR}"

is_url=0
if [[ "${EVALTOOLS_SRC}" =~ ^https?:// ]]; then
  is_url=1
fi

if [[ ${is_url} -eq 1 ]]; then
  info "Downloading evaltools from URL: ${EVALTOOLS_SRC}"
  mkdir -p "${WORKDIR}/_evaltools_src"
  cd "${WORKDIR}/_evaltools_src"
  pwd
  fname="evaltools_src.zip"
  curl -fsSL "${EVALTOOLS_SRC}" -o "${fname}"
  info "Unzipping evaltools"
  rm -rf evaltools_src_unzip
  mkdir -p evaltools_src_unzip
  unzip -q "${fname}" -d evaltools_src_unzip
  # Try to locate the inner directory
  cand="$(find evaltools_src_unzip -maxdepth 2 -type d -name 'evaltools_1.0.9' | head -n1 || true)"
  if [[ -z "${cand}" ]]; then
    cand="$(find evaltools_src_unzip -maxdepth 2 -type d -name 'evaltools*' | head -n1 || true)"
  fi
  if [[ -z "${cand}" ]]; then
    err "Could not locate evaltools source directory after unzip"; exit 1
  fi
  SRC_DIR="${cand}"
  cd "${WORKDIR}"
  pwd
else
  if [[ -f "${EVALTOOLS_SRC}" && "${EVALTOOLS_SRC}" == *.zip ]]; then
    info "Unzipping local evaltools zip: ${EVALTOOLS_SRC}"
    mkdir -p "${WORKDIR}/_evaltools_src"
    cd "${WORKDIR}/_evaltools_src"
    pwd
    unzip -q "${EVALTOOLS_SRC}"
    cand="$(find . -maxdepth 2 -type d -name 'evaltools_1.0.9' | head -n1 || true)"
    if [[ -z "${cand}" ]]; then
      cand="$(find . -maxdepth 2 -type d -name 'evaltools*' | head -n1 || true)"
    fi
    if [[ -z "${cand}" ]]; then
      err "Could not locate evaltools source directory after unzip"; exit 1
    fi
    SRC_DIR="${PWD}/${cand#./}"
    cd "${WORKDIR}"
    pwd
  elif [[ -d "${EVALTOOLS_SRC}" ]]; then
    SRC_DIR="${EVALTOOLS_SRC}"
  else
    err "--src must be a directory, .zip file, or URL: ${EVALTOOLS_SRC}"; exit 1
  fi
fi

# Step 7: Ensure PEP 517 build (pyproject.toml) exists to avoid legacy setup.py warning
if [[ -d "${SRC_DIR}" ]]; then
  if [[ ! -f "${SRC_DIR}/pyproject.toml" ]]; then
    info "Creating minimal pyproject.toml in source to enable PEP 517 build"
    cat > "${SRC_DIR}/pyproject.toml" << 'PYEOF'
[build-system]
requires = [
  "setuptools>=65.0.0",
  "wheel",
  "cython>=0.29.32",
  "numpy>=1.21.0,<2.0"
]
build-backend = "setuptools.build_meta"
PYEOF
  fi
fi

# Step 8: Install evaltools with PEP 517 build system (no isolation for dependencies)
pwd
info "Installing evaltools from: ${SRC_DIR}"
pip install --use-pep517 --no-build-isolation "${SRC_DIR}"

# Step 9: Smoke test
info "Verifying evaltools installation"
python - << 'PYTEST'
import evaltools
print("Evaltools installed:", evaltools.__version__)
PYTEST

# Step 10: Apply NumPy 2.x compatibility patch
info "=================================================="
info "Applying evaltools NumPy 2.x compatibility patch"
info "=================================================="
if python -c "import qlc.cli.qlc_fix_evaltools" 2>/dev/null; then
  # QLC is installed, use the built-in patch
  info "Using QLC built-in patch (qlc-fix-evaltools)"
  if python -m qlc.cli.qlc_fix_evaltools; then
    info "Patch applied successfully!"
  else
    warn "Patch encountered issues - you may need to apply it manually later"
    warn "Run: python -m qlc.cli.qlc_fix_evaltools"
  fi
else
  # QLC not installed, apply patch manually
  info "Applying patch directly (QLC not installed)"
  
  # Find evaltools installation
  EVALTOOLS_PATH=$(python -c "import evaltools, inspect; print(inspect.getfile(evaltools))" 2>/dev/null || echo "")
  if [[ -z "${EVALTOOLS_PATH}" ]]; then
    warn "Could not locate evaltools installation path"
    warn "Patch was not applied - evaltools may not work with NumPy >= 1.24.0"
  else
    EVALTOOLS_DIR=$(dirname "${EVALTOOLS_PATH}")
    EVALUATOR_FILE="${EVALTOOLS_DIR}/evaluator.py"
    
    if [[ -f "${EVALUATOR_FILE}" ]]; then
      info "Found evaluator.py at: ${EVALUATOR_FILE}"
      
      # Check if already patched
      if grep -q "import warnings" "${EVALUATOR_FILE}" && ! grep -q "np.warnings" "${EVALUATOR_FILE}"; then
        info "Evaltools is already patched"
      else
        # Create backup
        cp "${EVALUATOR_FILE}" "${EVALUATOR_FILE}.backup"
        info "Created backup: ${EVALUATOR_FILE}.backup"
        
        # Apply patch (replace np.warnings with warnings)
        if ! grep -q "import warnings" "${EVALUATOR_FILE}"; then
          # Add warnings import after numpy import
          sed -i.tmp '/import numpy as np/a\
import warnings' "${EVALUATOR_FILE}"
          rm -f "${EVALUATOR_FILE}.tmp"
          info "Added 'import warnings' to evaluator.py"
        fi
        
        # Replace np.warnings with warnings
        sed -i.tmp 's/np\.warnings/warnings/g' "${EVALUATOR_FILE}"
        rm -f "${EVALUATOR_FILE}.tmp"
        info "Replaced np.warnings with warnings module"
        info "Patch applied successfully!"
      fi
    else
      warn "Could not find evaluator.py at ${EVALUATOR_FILE}"
      warn "Patch was not applied - evaltools may not work with NumPy >= 1.24.0"
    fi
  fi
fi
info "=================================================="

info "All done. Activate with: source ${VENV_DIR}/bin/activate"
info "        Deactivate with: deactivate"
if [[ ${DOWNLOAD_OFFICIAL} -eq 1 ]]; then
  info "Documentation: ${DOWNLOAD_DIR}/documentation_v1.0.9/index.html"
  info "Example: ${DOWNLOAD_DIR}/simple_example_v1.0.6"
fi


