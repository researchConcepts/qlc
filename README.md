# Quick Look Content (QLC): Model–Observation Comparison Suite for Use with CAMS

`qlc` is a single command-line tool for model–observation comparisons with automated figures and summaries,
designed to support climate and air quality monitoring and specifically adapted for use with CAMS (Copernicus Atmospheric Monitoring Service) datasets.

| Package | Status |
|---------|--------|
| [qlc on PyPI](https://pypi.org/project/qlc/) | ![PyPI](https://img.shields.io/pypi/v/qlc?color=blue) |

---

## 🚀 Features

- Side-by-side evaluation of observational and modelled data
- Fully scriptable and automated post-processing chain (`qlc_main.sh`)
- Modular structure using shell + Python + Cython
- Generates publication-ready figures and LaTeX integration
- Supports NetCDF and CSV time series formats
- Pre-configured CAMS observational interface via JSON

---

## 🧩 User Installation

Use one of the following install modes:

```bash
# Option 1: CAMS (default data links + config)
pip install qlc && qlc-install --cams

# Option 2: Local test mode with embedded examples
pip install qlc && qlc-install --test

# Option 3: Custom interactive mode
pip install qlc && qlc-install --interactive="./path/to/qlc_user.conf"
```

---

## 🧪 Example Use Cases

### Run the full shell pipeline (retrieval, processing, plotting):
```bash
qlc
```

### Run just the observation/model comparison in Python:
```bash
qlc-py
```

### Submit via batch system (e.g., SLURM or LSF):
```bash
sqlc
```

## 🔧 Developer Setup

To work on the `qlc` source code, clone the repository and install it in "editable" mode. This will install all dependencies and link the `qlc` command to your source tree.

```bash
# 1. Clone the repository
git clone https://github.com/researchConcepts/qlc.git
cd qlc

# 2. (Recommended) Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# 3. Install in editable mode
pip install -e .
```

---

## 🔧 Configuration Structure

The installer script creates the following structure in your home directory:
```
$HOME/qlc_v<version>/
├── test/                   # Root directory for the 'test' installation mode
│   ├── bin/                # Symlinks to shell scripts
│   ├── doc/                # Symlinks to documentation
│   ├── config/             # Active config files (e.g., qlc.conf)
│   ├── examples/           # Test input and output files
│   ├── obs/, mod/, ...     # Runtime directories
│   └── VERSION.json        # Tracks install mode and version
└── cams/                   # Root for 'cams' mode, etc.
```
A symlink `$HOME/qlc` is also created to point to the active installation. You can edit `$HOME/qlc/config/qlc.conf` to modify runtime behavior.

---

## 📄 Documentation

- All core logic is contained in the `qlc` package.
- Shell scripts for driving the pipeline are in `qlc/sh/`.
- The core Python/Cython logic is in `qlc/py/*.py` and is compiled to binary modules for performance.

---

## 🛠 Developer Notes

- Python source files (`.py`) are compiled to binary modules (`.so`) using Cython at install time.
- The package version is managed in `pyproject.toml`.
- The `qlc-install` script sets up the runtime environment by creating directories and symlinks.

---

## 🔗 License

© ResearchConcepts io GmbH  
Contact: [contact@researchconcepts.io](mailto:contact@researchconcepts.io)  
MIT-compatible, source-restricted under private release until publication.

---