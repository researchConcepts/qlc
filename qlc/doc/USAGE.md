# QLC Usage Guide

## Installed CLI Tools

Once installed, QLC provides the following command-line entry points:

### `qlc`
Runs the full shell-based QLC pipeline (retrieval, processing, plotting).

### `qlc-py`
Runs the standalone Python-based observation–model comparison.

### `sqlc`
Submits a QLC run as a batch job (e.g., SLURM, LSF).

---

## PyPI Installation

To install `rc-qlc` from PyPI and set up the local environment, use the following two-step command.

### CAMS Mode
For users connected to the CAMS data infrastructure.
```bash
pip install rc-qlc && qlc-install --cams
```

### Test Mode
For a standalone test using the bundled example data.
```bash
pip install rc-qlc && qlc-install --test
```

---

## Local Wheel Installation

If you have a wheel file (`.whl`), you can install it directly.

```bash
# Example for a local wheel file
pip install ./path/to/your/rc-qlc-0.3.21-....whl
qlc-install --test
```

---

## Running QLC in Test Mode

After installing in test mode, you can immediately run the main drivers:
```bash
# Run the full shell pipeline with example data
qlc

# Run only the Python processing part
qlc-py
```

