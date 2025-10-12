# Contributing to QLC

Thank you for considering contributing to QLC!

This project supports structured comparisons between model and observation datasets (CAMS, surface stations, etc.). Contributions are welcome in the form of bug reports, feature proposals, configuration templates, or plugins.

---

## Package Layout

- `qlc/`: Main package directory.
  - `cli/`: Command-line entry point logic.
  - `py/`: Core Python/Cython source files (compiled to binaries).
  - `sh/`: Shell scripts for the pipeline driver.
  - `config/`: Configuration templates and defaults.
  - `examples/`: Sample case for testing.
  - `doc/`: Documentation files.

---

## CLI Tools

After installation, the following entry points are available:

- `qlc` → Shell-based full pipeline
- `qlc-py` → Python-only driver
- `sqlc` → Batch wrapper for `qlc`

---

## Plugin Support

Plugins may be placed in your runtime directory:

```bash
~/qlc/plugin/              # For PyPI installation
~/qlc-dev-run/plugin/      # For development installation
```

These are loaded dynamically via `plugin_loader.py` if found.

---

## Development Setup

**New in v0.4.1**: QLC now supports isolated development environments that can run in parallel with PyPI installations.

### Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/researchConcepts/qlc.git ~/qlc-dev
    cd ~/qlc-dev
    ```

2.  **Create and activate a conda environment (use 'qlc-dev' name):**
    ```bash
    conda create -n qlc-dev python=3.10 -y
    conda activate qlc-dev
    ```

3.  **Install in "editable" mode:**
    This command installs all dependencies and links your environment to your source code. Any changes you make to the `.py` files will be reflected immediately.
    ```bash
    pip install -e ".[dev]"
    ```
    
    **Note**: Evaltools must be installed separately - see `qlc/doc/EVALTOOLS.md` for instructions.

4.  **Setup isolated development runtime:**
    This creates a separate runtime directory (`~/qlc_dev/`) that won't conflict with PyPI installations.
    ```bash
    qlc-install --mode dev
    ```

5.  **Setup conda environment auto-switching (recommended):**
    ```bash
    bash qlc/sh/tools/setup_conda_env.sh qlc-dev
    ```

### Verify Setup

```bash
conda deactivate && conda activate qlc-dev
qlc --version
# Should show: Runtime: /Users/<user>/qlc-dev-run (conda-dev)
```

### For Complete Development Guide

See **INSTALL_DEV.md** for comprehensive development setup instructions, including:
- Parallel testing with PyPI version
- Version switching methods
- Troubleshooting common issues
- Development utilities documentation

---

## Building Wheels for Distribution

To build the platform-specific wheels for distribution on PyPI, use the provided build script. It handles the complexities of cross-platform compilation.

```bash
# Ensure you have the target Python version installed (e.g., 3.10)
# Then run the build script, pointing to that interpreter
python build_wheels.py --python /path/to/your/python3.10
```
The final wheels will be located in the `dist/` directory.

---

## Testing

Unit tests (to be added) will be collected under `tests/`.

  ```bash
  python -m qlc.install --test
  python -m qlc.install --cams
  ```

---

## Style Guide

- Follow [PEP8](https://www.python.org/dev/peps/pep-0008/)
- Use docstrings in PEP257 format and keep things simple (KISS principle)
- Write CLI-facing functions with clean logging

---

## License

This project uses the MIT License. By contributing, you agree your code may be distributed under the same license.

---

Thanks again!
