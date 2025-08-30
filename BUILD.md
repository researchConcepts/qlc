# QLC Build Guide

This document describes how to build the QLC package for different platforms and troubleshoot common issues.

## Prerequisites

### System Dependencies

#### macOS
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required system libraries
brew install geos proj
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y libgeos-dev proj-bin libproj-dev
```

#### Windows
- Install Visual Studio Build Tools
- Install GEOS and PROJ libraries (via conda or manual installation)

### Python Dependencies

```bash
pip install wheel setuptools cython
pip install numpy pandas matplotlib xarray netCDF4 scipy cartopy tqdm
```

## Building the Package

### Local Build

1. **Clean previous builds:**
   ```bash
   python build_wheels.py
   ```

2. **Build wheel:**
   ```bash
   python setup.py bdist_wheel
   ```

3. **Build source distribution:**
   ```bash
   python setup.py sdist
   ```

4. **Check wheel:**
   ```bash
   twine check dist/*.whl
   ```

### Automated Build (GitHub Actions)

The package includes GitHub Actions workflows that automatically build wheels for:
- macOS (x86_64, arm64)
- Linux (x86_64)
- Windows (x86_64)

To trigger a build:
1. Push a tag starting with 'v' (e.g., `v0.3.25`)
2. The workflow will build wheels for all supported platforms
3. Download the artifacts from the GitHub Actions page

## Testing the Build

### Basic Import Test
```bash
python test_basic.py
```

### Comprehensive Import Test
```bash
python test_imports.py
```

### Installation Test
```bash
# Install the wheel
pip install dist/qlc-*.whl

# Test basic functionality
python -c "import qlc; print('QLC imported successfully')"
python -c "from qlc.py import version; print(f'QLC version: {version.QLC_VERSION}')"
```

## Troubleshooting

### Segmentation Fault Issues

If you encounter segmentation faults:

1. **Check dependencies:**
   ```bash
   python test_imports.py
   ```

2. **Verify Cython compilation:**
   ```bash
   python setup.py build_ext --inplace
   ```

3. **Check for missing system libraries:**
   - macOS: Ensure GEOS and PROJ are installed via Homebrew
   - Linux: Install libgeos-dev and libproj-dev
   - Windows: Install via conda or manual installation

4. **Test with minimal imports:**
   ```bash
   python test_basic.py
   ```

### Common Issues

#### Missing Dependencies
- Ensure all Python dependencies are installed
- Check system library dependencies
- Verify Cython is properly installed

#### Compilation Errors
- Clean build artifacts: `python build_wheels.py`
- Check Cython version compatibility
- Verify Python version (3.10+ required)

#### Import Errors
- Check that compiled extensions are properly included
- Verify package structure
- Test with minimal import script

### Platform-Specific Notes

#### macOS
- Use Homebrew for system dependencies
- Ensure Xcode command line tools are installed
- Test on both Intel and Apple Silicon

#### Linux
- Install system dependencies via package manager
- Test on multiple distributions if possible
- Check for library version conflicts

#### Windows
- Use conda for system dependencies if possible
- Test with different Python versions
- Verify Visual Studio Build Tools installation

## Release Process

1. **Update version in pyproject.toml**
2. **Create and push a tag:**
   ```bash
   git tag v0.3.25
   git push origin v0.3.25
   ```
3. **Wait for GitHub Actions to complete**
4. **Download and test wheels**
5. **Upload to PyPI:**
   ```bash
   twine upload dist/*
   ```

## Support

For build issues:
1. Check this guide
2. Run the test scripts
3. Check GitHub Actions logs
4. Open an issue with detailed error information
