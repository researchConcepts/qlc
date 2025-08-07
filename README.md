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
pip install qlc && qlc-install --mode cams

# Option 2: Local test mode with embedded examples
pip install qlc && qlc-install --mode test
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

## 🔧 Developer / Custom Installation

# PyPip:

```bash
pip install qlc && qlc-install --interactive="./path/to/qlc_user.conf"
```

# Local wheel:

```bash
VERSION="0.3.5"
ARCH="cp310-cp310-macosx_14_0_arm64"
DIST=~/qlc_package_v$VERSION/dist/qlc-$VERSION-$ARCH.whl
pip uninstall qlc
pip install $DIST && qlc-install --interactive="./path/to/qlc_user.conf"
```
# Verify version:

```bash
pip show -f qlc
```

---

## 🔧 Configuration Structure

The following directory is automatically created at:
```
$HOME/qlc/v0.3.5/
├── bin/                    # Symlink to shell scripts
├── doc/                    # Symlink to documentation files
├── config/                 # Active config file: qlc.conf + qlc_tex.conf
├── examples/               # Test input and output files
├── obs/, mod/, run/, log/  # Runtime directories
└── VERSION.json            # Tracks install mode and version
```

You can edit `config/qlc.conf` to modify runtime behavior.

---

## 📄 Documentation

- [Jupyter Notebook Overview (PDF)](doc/qlc-JupyterNotebook.pdf)
- All logic described in `qlc_main.sh` and `qlc_main.py`
- Shell scripts: `src/sh/*.sh`
- Python logic: `qlc/*.pyx` (compiled as `.so`)

---

## 🛠 Developer Notes

- Source files are cythonized and installed as compiled binaries
- Shell scripts remain user-readable
- Versions are auto-detected from `version.pyx`
- Config selection uses symlinks and is mode-dependent

---

## 🔗 License

© ResearchConcepts io GmbH  
Contact: [contact@researchconcepts.io](mailto:contact@researchconcepts.io)  
MIT-compatible, source-restricted under private release until publication.

---