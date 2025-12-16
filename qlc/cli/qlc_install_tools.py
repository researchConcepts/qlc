#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLC Tools Installer and Checker: System Tool Management

Part of QLC (Quick Look Content) v1.0.1-beta
An Automated Model-Observation Comparison Suite Optimized for CAMS

Documentation:
    https://docs.researchconcepts.io/qlc/latest/getting-started/installation/

Description:
    Comprehensive checking and platform-specific installation of command-line
    tools required by QLC. Supports HPC module system detection, automatic
    tool installation, and verification of all dependencies.

Usage:
    qlc-install-tools --check                # Check all tools and show status
    qlc-install-tools --install-all          # Install all missing tools
    qlc-install-tools --install-xelatex      # Install only XeLaTeX
    qlc-install-tools --install-netcdf       # Install only NetCDF utilities
    qlc-install-tools --install-extras       # Install evaltools, pyferret, cartopy data
    qlc-install-tools --install-evaltools    # Install evaltools with NumPy 2.x patch
    qlc-install-tools --install-pyferret     # Install PyFerret standalone
    qlc-install-tools --install-cartopy      # Download Cartopy Natural Earth data

Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import tarfile
import re
from pathlib import Path
from typing import List, Optional, Dict, Tuple


def log(message: str, level: str = "INFO") -> None:
    """Simple logging function."""
    print(f"[{level}] {message}")


def run_command(cmd: List[str], cwd: Optional[str] = None, check: bool = True) -> bool:
    """Run a command and return success status."""
    try:
        result = subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)
        if result.stdout:
            log(f"Output: {result.stdout}")
        return True
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {' '.join(cmd)}", "ERROR")
        if e.stderr:
            log(f"Error: {e.stderr}", "ERROR")
        return False


def check_command_exists(command: str) -> bool:
    """Check if a command exists in PATH."""
    return shutil.which(command) is not None


def get_command_version(command: str) -> Optional[str]:
    """Get version string for a command if available."""
    try:
        result = subprocess.run([command, "--version"], 
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            return result.stdout.strip().split('\n')[0]
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
        pass
    
    try:
        result = subprocess.run([command, "-v"], 
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            return result.stdout.strip().split('\n')[0]
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
        pass
    
    return None


def get_command_location(command: str) -> Optional[str]:
    """Get the full path to a command."""
    return shutil.which(command)


def check_module_system() -> Dict[str, bool]:
    """Check if module system is available and what modules can be loaded."""
    modules = {
        "module_system": False,
        "python3": False,
        "texlive": False,
        "ferret": False,
        "cdo": False,
        "netcdf": False
    }
    
    # Check if module command exists
    if not check_command_exists("module"):
        return modules
    
    modules["module_system"] = True
    
    # Check available modules using shell to handle module function
    try:
        # Use bash to execute module command since it's a shell function
        result = subprocess.run(["bash", "-c", "module avail"], 
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            available_modules = result.stdout.lower()
            
            # Check for specific modules
            modules["python3"] = "python3" in available_modules
            modules["texlive"] = "texlive" in available_modules
            modules["ferret"] = "ferret" in available_modules
            modules["cdo"] = "cdo" in available_modules
            modules["netcdf"] = "netcdf" in available_modules
            
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        pass
    
    return modules


def check_all_tools() -> Dict[str, Dict[str, any]]:
    """Comprehensive check of all QLC tools."""
    tools = {
        "bash": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        },
        "cdo": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        },
        "ncdump": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        },
        "ncgen": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        },
        "xelatex": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        },
        "pyferret": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        },
        "evaltools": {
            "available": False,
            "version": None,
            "location": None,
            "source": None
        }
    }
    
    # Check module system first
    modules = check_module_system()
    
    # On HPC systems with module system, try to load modules before checking
    if modules["module_system"]:
        try:
            # Try to load texlive module for xelatex check
            if modules["texlive"]:
                subprocess.run(
                    ["bash", "-c", "module load texlive 2>/dev/null"],
                    timeout=5,
                    capture_output=True
                )
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
            pass
    
    # Check each tool
    for tool in tools:
        # Special handling for tools available via modules
        tool_available_via_module = False
        if modules["module_system"]:
            if tool == "xelatex" and modules["texlive"]:
                # Try to find xelatex after loading texlive module
                try:
                    result = subprocess.run(
                        ["bash", "-c", "module load texlive 2>/dev/null && which xelatex"],
                        capture_output=True, text=True, timeout=5
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        tools[tool]["available"] = True
                        tools[tool]["location"] = result.stdout.strip()
                        tools[tool]["source"] = "module (texlive)"
                        tool_available_via_module = True
                        # Get version
                        version_result = subprocess.run(
                            ["bash", "-c", "module load texlive 2>/dev/null && xelatex --version"],
                            capture_output=True, text=True, timeout=5
                        )
                        if version_result.returncode == 0:
                            tools[tool]["version"] = version_result.stdout.split('\n')[0].strip()
                except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
                    pass
        
        if not tool_available_via_module and check_command_exists(tool):
            tools[tool]["available"] = True
            tools[tool]["location"] = get_command_location(tool)
            tools[tool]["version"] = get_command_version(tool)
            
            # Determine source
            if modules["module_system"]:
                if tool == "cdo" and modules["cdo"]:
                    tools[tool]["source"] = "module (cdo)"
                elif tool in ["ncdump", "ncgen"] and modules["netcdf"]:
                    tools[tool]["source"] = "module (netcdf)"
                elif tool == "xelatex" and modules["texlive"]:
                    tools[tool]["source"] = "module (texlive)"
                elif tool == "pyferret" and modules["ferret"]:
                    tools[tool]["source"] = "module (ferret)"
                else:
                    tools[tool]["source"] = "system PATH"
            else:
                tools[tool]["source"] = "system PATH"
    
    # Special check for bash in venv (required for QLC)
    venv_path = os.environ.get('VIRTUAL_ENV')
    if venv_path:
        venv_bash = Path(venv_path) / "bin" / "bash"
        if venv_bash.exists():
            tools["bash"]["available"] = True
            tools["bash"]["location"] = str(venv_bash)
            tools["bash"]["source"] = "QLC venv"
            try:
                result = subprocess.run(
                    [str(venv_bash), "--version"],
                    capture_output=True, text=True, timeout=2
                )
                if result.returncode == 0:
                    # Extract version from "GNU bash, version X.Y.Z"
                    version_line = result.stdout.split('\n')[0]
                    if "version" in version_line:
                        tools["bash"]["version"] = version_line.split("version")[1].split("(")[0].strip()
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
                pass
    
    # Special check for evaltools (Python package)
    try:
        import evaltools
        tools["evaltools"]["available"] = True
        tools["evaltools"]["version"] = getattr(evaltools, '__version__', 'unknown')
        tools["evaltools"]["source"] = "Python package (current environment)"
        tools["evaltools"]["location"] = evaltools.__file__ if hasattr(evaltools, '__file__') else None
    except ImportError:
        # Check for standalone evaltools installation
        evaltools_venv = Path.home() / "venv" / "evaltools_109"
        if evaltools_venv.exists():
            evaltools_python = evaltools_venv / "bin" / "python"
            if evaltools_python.exists():
                try:
                    result = subprocess.run(
                        [str(evaltools_python), "-c", "import evaltools; print(evaltools.__version__)"],
                        capture_output=True, text=True, check=True
                    )
                    tools["evaltools"]["available"] = True
                    tools["evaltools"]["version"] = result.stdout.strip()
                    tools["evaltools"]["source"] = "standalone venv (evaltools_109)"
                    tools["evaltools"]["location"] = str(evaltools_venv)
                except subprocess.CalledProcessError:
                    pass
    
    return tools


def get_platform_info() -> dict:
    """Get platform-specific information."""
    system = platform.system().lower()
    machine = platform.machine().lower()
    
    info = {
        "system": system,
        "machine": machine,
        "is_macos": system == "darwin",
        "is_linux": system == "linux",
        "is_windows": system == "windows",
        "is_arm": machine in ["arm64", "aarch64"],
        "is_x86": machine in ["x86_64", "amd64", "i386", "i686"]
    }
    
    return info


def install_xelatex_macos(force: bool = False) -> bool:
    """Install XeLaTeX on macOS using Homebrew."""
    log("Installing XeLaTeX on macOS using Homebrew...")
    
    # Check if Homebrew is available
    if not check_command_exists("brew"):
        log("Homebrew not found. Please install Homebrew first:", "ERROR")
        log("  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", "ERROR")
        return False
    
    # Install texlive (includes xelatex)
    if force:
        cmd = ["brew", "reinstall", "--cask", "mactex"]
        log("Force mode: Reinstalling MacTeX...")
    else:
        cmd = ["brew", "install", "--cask", "mactex"]
        log("This will install MacTeX (~4GB). Continue? (y/N): ", end="")
        
        if input().lower() != 'y':
            log("Installation cancelled by user")
            return False
    
    log(f"Running: {' '.join(cmd)}")
    return run_command(cmd)


def install_xelatex_linux(force: bool = False) -> bool:
    """Install XeLaTeX on Linux using apt-get."""
    log("Installing XeLaTeX on Linux using apt-get...")
    
    # Check if apt-get is available
    if not check_command_exists("apt-get"):
        log("apt-get not found. Please install texlive-xetex manually:", "ERROR")
        log("  sudo apt-get update", "ERROR")
        log("  sudo apt-get install texlive-xetex", "ERROR")
        return False
    
    # Update package list and install texlive-xetex
    cmds = [
        ["sudo", "apt-get", "update"],
        ["sudo", "apt-get", "install", "-y", "texlive-xetex"]
    ]
    
    if force:
        log("Force mode: Reinstalling texlive-xetex...")
        cmds = [
            ["sudo", "apt-get", "update"],
            ["sudo", "apt-get", "reinstall", "-y", "texlive-xetex"]
        ]
    
    for cmd in cmds:
        log(f"Running: {' '.join(cmd)}")
        if not run_command(cmd):
            return False
    
    return True


def install_xelatex_windows() -> bool:
    """Provide instructions for installing XeLaTeX on Windows."""
    log("XeLaTeX installation on Windows:", "INFO")
    log("1. Download MiKTeX from: https://miktex.org/download", "INFO")
    log("2. Run the installer and follow the setup wizard", "INFO")
    log("3. Or use Chocolatey: choco install miktex", "INFO")
    log("4. Or use Scoop: scoop install miktex", "INFO")
    return True


def install_netcdf_macos(force: bool = False) -> bool:
    """Install NetCDF utilities on macOS using Homebrew."""
    log("Installing NetCDF utilities on macOS using Homebrew...")
    
    if not check_command_exists("brew"):
        log("Homebrew not found. Please install Homebrew first:", "ERROR")
        return False
    
    if force:
        cmd = ["brew", "reinstall", "netcdf"]
        log("Force mode: Reinstalling NetCDF...")
    else:
        cmd = ["brew", "install", "netcdf"]
    
    log(f"Running: {' '.join(cmd)}")
    return run_command(cmd)


def install_netcdf_linux(force: bool = False) -> bool:
    """Install NetCDF utilities on Linux using apt-get."""
    log("Installing NetCDF utilities on Linux using apt-get...")
    
    if not check_command_exists("apt-get"):
        log("apt-get not found. Please install netcdf-bin manually:", "ERROR")
        log("  sudo apt-get update", "ERROR")
        log("  sudo apt-get install netcdf-bin", "ERROR")
        return False
    
    cmds = [
        ["sudo", "apt-get", "update"],
        ["sudo", "apt-get", "install", "-y", "netcdf-bin"]
    ]
    
    if force:
        log("Force mode: Reinstalling netcdf-bin...")
        cmds = [
            ["sudo", "apt-get", "update"],
            ["sudo", "apt-get", "reinstall", "-y", "netcdf-bin"]
        ]
    
    for cmd in cmds:
        log(f"Running: {' '.join(cmd)}")
        if not run_command(cmd):
            return False
    
    return True


def install_netcdf_windows() -> bool:
    """Provide instructions for installing NetCDF utilities on Windows."""
    log("NetCDF utilities installation on Windows:", "INFO")
    log("1. Download NetCDF from: https://www.unidata.ucar.edu/software/netcdf/", "INFO")
    log("2. Or use Chocolatey: choco install netcdf", "INFO")
    log("3. Or use Scoop: scoop install netcdf", "INFO")
    return True


def install_xelatex(platform_info: dict, force: bool = False) -> bool:
    """Install XeLaTeX based on platform."""
    log("Installing XeLaTeX...")
    
    if platform_info["is_macos"]:
        return install_xelatex_macos(force)
    elif platform_info["is_linux"]:
        return install_xelatex_linux(force)
    elif platform_info["is_windows"]:
        return install_xelatex_windows()
    else:
        log(f"Unsupported platform: {platform_info['system']}", "ERROR")
        return False


def install_netcdf(platform_info: dict, force: bool = False) -> bool:
    """Install NetCDF utilities based on platform."""
    log("Installing NetCDF utilities...")
    
    if platform_info["is_macos"]:
        return install_netcdf_macos(force)
    elif platform_info["is_linux"]:
        return install_netcdf_linux(force)
    elif platform_info["is_windows"]:
        return install_netcdf_windows()
    else:
        log(f"Unsupported platform: {platform_info['system']}", "ERROR")
        return False


def check_tools() -> dict:
    """Check which tools are already available."""
    tools = check_all_tools()
    
    log("QLC Tool Availability Check:")
    log("=" * 50)
    
    # QLC Required Tools
    log("\n[QLC Required Tools]")
    for tool in ["bash"]:
        if tools[tool]["available"]:
            status = f"✓ Available"
            version = f" ({tools[tool]['version']})" if tools[tool]['version'] else ""
            source = f" via {tools[tool]['source']}" if tools[tool]['source'] else ""
            log(f"  {tool}: {status}{version}{source}")
        else:
            log(f"  {tool}: ✗ Missing - Install with: qlc-install-tools --install-bash")
    
    # Core Tools
    log("\n[Core Tools]")
    for tool in ["cdo", "ncdump", "ncgen", "xelatex"]:
        if tools[tool]["available"]:
            status = f"✓ Available"
            version = f" ({tools[tool]['version']})" if tools[tool]['version'] else ""
            source = f" via {tools[tool]['source']}" if tools[tool]['source'] else ""
            log(f"  {tool}: {status}{version}{source}")
        else:
            log(f"  {tool}: ✗ Missing")
    
    # Plotting tools
    log("\n[Plotting Tools]")
    for tool in ["pyferret", "evaltools"]:
        if tools[tool]["available"]:
            status = f"✓ Available"
            version = f" ({tools[tool]['version']})" if tools[tool]['version'] else ""
            source = f" via {tools[tool]['source']}" if tools[tool]['source'] else ""
            location = f" at {tools[tool]['location']}" if tools[tool]['location'] else ""
            log(f"  {tool}: {status}{version}{source}{location}")
        else:
            log(f"  {tool}: ✗ Missing")
    
    # Module system info
    modules = check_module_system()
    if modules["module_system"]:
        log(f"\n[Module System] ✓ Available")
        available_modules = []
        for module in ["python3", "texlive", "ferret", "cdo", "netcdf"]:
            if modules[module]:
                available_modules.append(module)
        if available_modules:
            log(f"  Available modules: {', '.join(available_modules)}")
        else:
            log(f"  No QLC-relevant modules found")
    else:
        log(f"\n[Module System] ✗ Not available (using system packages)")
    
    return tools


def install_extras(force: bool = False) -> bool:
    """Install evaltools and pyferret (and cartopy data) using the existing install_extras.py."""
    log("Installing evaltools, pyferret, and cartopy data...")
    
    try:
        # Import and run the install_extras module
        from qlc.cli.qlc_install_extras import main as install_extras_main
        
        # Save current sys.argv and replace with install_extras arguments
        original_argv = sys.argv
        if force:
            sys.argv = ["qlc-install-extras", "--all", "--cartopy_downloads", "--force"]
        else:
            sys.argv = ["qlc-install-extras", "--all", "--cartopy_downloads"]
        
        try:
            result = install_extras_main()
            return result == 0
        finally:
            sys.argv = original_argv
            
    except Exception as e:
        log(f"Failed to install extras: {e}", "ERROR")
        return False


def install_evaltools_only(force: bool = False) -> bool:
    """Install evaltools only using the existing install_extras.py."""
    log("Installing evaltools...")
    
    try:
        # Import and run the install_extras module
        from qlc.cli.qlc_install_extras import main as install_extras_main
        
        # Save current sys.argv and replace with install_extras arguments
        original_argv = sys.argv
        if force:
            sys.argv = ["qlc-install-extras", "--evaltools", "--force"]
        else:
            sys.argv = ["qlc-install-extras", "--evaltools"]
        
        try:
            result = install_extras_main()
            return result == 0
        finally:
            sys.argv = original_argv
            
    except Exception as e:
        log(f"Failed to install evaltools: {e}", "ERROR")
        return False


def install_cartopy_data(force: bool = False) -> bool:
    """Download Cartopy Natural Earth data using the existing install_extras.py."""
    log("Downloading Cartopy Natural Earth data...")
    
    try:
        # Import and run the install_extras module
        from qlc.cli.qlc_install_extras import main as install_extras_main
        
        # Save current sys.argv and replace with install_extras arguments
        original_argv = sys.argv
        if force:
            sys.argv = ["qlc-install-extras", "--cartopy_downloads", "--force"]
        else:
            sys.argv = ["qlc-install-extras", "--cartopy_downloads"]
        
        try:
            result = install_extras_main()
            return result == 0
        finally:
            sys.argv = original_argv
            
    except Exception as e:
        log(f"Failed to download cartopy data: {e}", "ERROR")
        return False


def install_pyferret_standalone(force: bool = False) -> bool:
    """
    Install PyFerret using the qlc-install-extras Python entry point.
    This ensures consistency and single source of truth.
    """
    log("Installing PyFerret only...")
    
    try:
        # Import and run the install_extras module for pyferret only
        from qlc.cli.qlc_install_extras import main as install_extras_main
        
        # Save current sys.argv and replace with install_extras arguments
        original_argv = sys.argv
        if force:
            sys.argv = ["qlc-install-extras", "--pyferret", "--force"]
        else:
            sys.argv = ["qlc-install-extras", "--pyferret"]
        
        try:
            result = install_extras_main()
            return result == 0
        finally:
            sys.argv = original_argv
            
    except Exception as e:
        log(f"Failed to install PyFerret: {e}", "ERROR")
        return False


def install_bash(venv_path: Optional[str] = None, force: bool = False) -> bool:
    """
    Install Bash 5.x from source into the QLC venv.
    QLC requires Bash 4.0+ for associative arrays and declare -g.
    
    This ensures predictable behavior regardless of system bash version.
    Everything is installed into venv/bin/ - no sudo required.
    
    Args:
        venv_path: Path to virtual environment (defaults to VIRTUAL_ENV)
        force: Force installation even if bash already exists
    
    Returns:
        True if successful, False otherwise
    """
    log("=== Bash 5.x Installation ===")
    
    # Get venv path
    if venv_path is None:
        venv_path = os.environ.get('VIRTUAL_ENV')
        if not venv_path:
            log("VIRTUAL_ENV not set. Please activate your QLC virtual environment.", "ERROR")
            return False
    
    venv_path = Path(venv_path)
    venv_bash = venv_path / 'bin' / 'bash'
    
    # Check if bash already installed
    if venv_bash.exists() and not force:
        # Check version
        try:
            result = subprocess.run([str(venv_bash), '--version'], 
                                   capture_output=True, text=True, timeout=2)
            match = re.search(r'version (\d+\.\d+)', result.stdout)
            if match:
                version = float(match.group(1))
                if version >= 4.0:
                    log(f"Bash {version} already installed in venv: {venv_bash}")
                    return True
        except:
            pass
    
    if force:
        log("Force installation requested, will reinstall bash...")
    
    # Check for required build tools
    log("Checking for required build tools (gcc/clang, make)...")
    if not shutil.which('gcc') and not shutil.which('clang'):
        log("ERROR: No C compiler found (gcc or clang required)", "ERROR")
        log("Please install development tools:", "ERROR")
        if sys.platform == 'darwin':
            log("  macOS: xcode-select --install", "ERROR")
        else:
            log("  Linux: sudo apt install build-essential  (or yum groupinstall 'Development Tools')", "ERROR")
        return False
    
    if not shutil.which('make'):
        log("ERROR: make not found", "ERROR")
        return False
    
    # Download and compile bash
    bash_version = "5.2.21"
    bash_url = f"https://ftp.gnu.org/gnu/bash/bash-{bash_version}.tar.gz"
    
    log(f"Compiling Bash {bash_version} from source...")
    log("This will take a few minutes...")
    
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        bash_tar = temp_path / f"bash-{bash_version}.tar.gz"
        
        # Download with SSL context handling
        log(f"Downloading from {bash_url}")
        try:
            import ssl
            
            # Try to create a proper SSL context
            try:
                # First, try with certifi if available (most reliable)
                import certifi
                ssl_context = ssl.create_default_context(cafile=certifi.where())
                log("Using certifi for SSL certificate verification")
            except ImportError:
                # If certifi not available, try with default context
                try:
                    ssl_context = ssl.create_default_context()
                    log("Using default SSL context")
                except Exception:
                    # Last resort: use unverified context (macOS fallback)
                    ssl_context = ssl._create_unverified_context()
                    log("Warning: Using unverified SSL context (certificate verification disabled)", "WARNING")
            
            # Download with SSL context using urlopen with progress
            with urllib.request.urlopen(bash_url, context=ssl_context, timeout=30) as response:
                total_size = response.length
                downloaded = 0
                chunk_size = 8192  # 8KB chunks
                
                with open(bash_tar, 'wb') as out_file:
                    while True:
                        chunk = response.read(chunk_size)
                        if not chunk:
                            break
                        out_file.write(chunk)
                        downloaded += len(chunk)
                        
                        # Show progress every 1MB
                        if total_size and downloaded % (1024 * 1024) < chunk_size:
                            progress_mb = downloaded / (1024 * 1024)
                            total_mb = total_size / (1024 * 1024) if total_size else 0
                            if total_mb > 0:
                                log(f"Downloaded {progress_mb:.1f} MB of {total_mb:.1f} MB ({100*downloaded/total_size:.0f}%)")
                            else:
                                log(f"Downloaded {progress_mb:.1f} MB")
                
                log(f"Download complete: {downloaded / (1024*1024):.1f} MB")
        except Exception as e:
            log(f"Download failed: {e}", "ERROR")
            log("If SSL errors persist, try: pip install --upgrade certifi", "ERROR")
            return False
        
        # Extract
        log("Extracting source...")
        try:
            with tarfile.open(bash_tar, 'r:gz') as tar:
                tar.extractall(temp_path)
        except Exception as e:
            log(f"Extraction failed: {e}", "ERROR")
            return False
        
        bash_src = temp_path / f"bash-{bash_version}"
        
        # Configure
        log(f"Configuring (installing to {venv_path})...")
        configure_cmd = [
            './configure',
            f'--prefix={venv_path}',  # Install into venv!
            '--disable-nls',           # No internationalization (faster build)
            '--without-bash-malloc',   # Use system malloc (more compatible)
        ]
        
        result = run_command(configure_cmd, cwd=str(bash_src), check=False)
        if not result:
            log("Configure failed", "ERROR")
            return False
        
        # Compile (use multiple cores if available)
        import multiprocessing
        num_cores = multiprocessing.cpu_count()
        log(f"Compiling with {num_cores} cores (this takes 2-5 minutes)...")
        
        result = run_command(['make', f'-j{num_cores}'], cwd=str(bash_src), check=False)
        if not result:
            log("Compilation failed", "ERROR")
            return False
        
        # Install to venv/bin/ (NO SUDO!)
        log(f"Installing to {venv_bash}...")
        result = run_command(['make', 'install'], cwd=str(bash_src), check=False)
        if not result:
            log("Installation failed", "ERROR")
            return False
    
    # Verify installation
    if venv_bash.exists():
        result = subprocess.run([str(venv_bash), '--version'], 
                               capture_output=True, text=True)
        log(f"Successfully installed: {result.stdout.splitlines()[0]}")
        log(f"Location: {venv_bash}")
        return True
    else:
        log("Installation failed - bash not found after install", "ERROR")
        return False


def get_missing_tools_commands(tools: dict) -> List[str]:
    """Get the commands needed to install missing tools."""
    commands = []
    
    # Check core tools
    if not tools["xelatex"]["available"]:
        commands.append("qlc-install-tools --install-xelatex")
    
    if not (tools["ncdump"]["available"] and tools["ncgen"]["available"]):
        commands.append("qlc-install-tools --install-netcdf")
    
    # Check plotting tools
    if not tools["pyferret"]["available"] or not tools["evaltools"]["available"]:
        commands.append("qlc-install-tools --install-extras")
    
    return commands


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Install and check platform-specific tools required by QLC",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  qlc-install-tools --check                     # Check which tools are available
  qlc-install-tools --install-all               # Install all missing tools
  qlc-install-tools --install-all --force       # Force reinstall all tools
  qlc-install-tools --install-xelatex           # Install only XeLaTeX
  qlc-install-tools --install-xelatex --force   # Force reinstall XeLaTeX
  qlc-install-tools --install-netcdf            # Install only NetCDF utilities
  qlc-install-tools --install-extras            # Install evaltools (with NumPy 2.x patch), pyferret, and cartopy data
  qlc-install-tools --install-evaltools         # Install evaltools only with NumPy 2.x compatibility patch
  qlc-install-tools --install-evaltools --force # Force reinstall evaltools (with NumPy 2.x patch)
  qlc-install-tools --install-pyferret          # Install PyFerret only (standalone)
  qlc-install-tools --install-pyferret --force  # Force reinstall PyFerret
  qlc-install-tools --install-cartopy           # Download Cartopy Natural Earth data only
        """
    )
    
    parser.add_argument("--check", action="store_true", 
                       help="Check which tools are already available")
    parser.add_argument("--install-all", action="store_true",
                       help="Install all missing tools")
    parser.add_argument("--install-xelatex", action="store_true",
                       help="Install XeLaTeX")
    parser.add_argument("--install-netcdf", action="store_true",
                       help="Install NetCDF utilities")
    parser.add_argument("--install-extras", action="store_true",
                       help="Install evaltools, pyferret, and cartopy data")
    parser.add_argument("--install-evaltools", action="store_true",
                       help="Install evaltools only with NumPy 2.x compatibility patch (standalone)")
    parser.add_argument("--install-pyferret", action="store_true",
                       help="Install PyFerret only (calls qlc-install-extras --pyferret)")
    parser.add_argument("--install-cartopy", action="store_true",
                       help="Download Cartopy Natural Earth data only")
    parser.add_argument("--install-bash", action="store_true",
                       help="Install Bash 5.x into QLC venv (required for QLC operation)")
    parser.add_argument("--force", action="store_true",
                       help="Force installation even if tools already exist")
    
    args = parser.parse_args()
    
    if not any([args.check, args.install_all, args.install_xelatex, args.install_netcdf, 
                args.install_extras, args.install_evaltools, args.install_pyferret, 
                args.install_cartopy, args.install_bash]):
        parser.print_help()
        return 1
    
    platform_info = get_platform_info()
    log(f"Platform: {platform_info['system']} ({platform_info['machine']})")
    
    if args.check:
        tools = check_tools()
        
        # Show next steps if tools are missing
        missing_commands = get_missing_tools_commands(tools)
        if missing_commands:
            log(f"\n[Next Steps]")
            log("To install missing tools, run:")
            for cmd in missing_commands:
                log(f"  {cmd}")
            log(f"\nOr install everything at once:")
            log(f"  qlc-install-tools --install-all")
        else:
            log(f"\n[Status] All tools are available! QLC is ready to use.")
        
        return 0
    
    tools = check_all_tools()
    success = True
    
    if args.install_all or args.install_xelatex:
        if not tools["xelatex"]["available"] or args.force:
            if args.force and tools["xelatex"]["available"]:
                log("Force mode: Reinstalling XeLaTeX...")
            success &= install_xelatex(platform_info, args.force)
        else:
            log("XeLaTeX already available")
    
    if args.install_all or args.install_netcdf:
        if not (tools["ncdump"]["available"] and tools["ncgen"]["available"]) or args.force:
            if args.force and (tools["ncdump"]["available"] or tools["ncgen"]["available"]):
                log("Force mode: Reinstalling NetCDF utilities...")
            success &= install_netcdf(platform_info, args.force)
        else:
            log("NetCDF utilities already available")
    
    if args.install_all or args.install_extras:
        if not tools["pyferret"]["available"] or not tools["evaltools"]["available"] or args.force:
            if args.force and (tools["pyferret"]["available"] or tools["evaltools"]["available"]):
                log("Force mode: Reinstalling evaltools, PyFerret, and cartopy data...")
            success &= install_extras(args.force)
        else:
            log("Evaltools and PyFerret already available")
    
    if args.install_evaltools:
        if not tools["evaltools"]["available"] or args.force:
            if args.force and tools["evaltools"]["available"]:
                log("Force mode: Reinstalling evaltools...")
            success &= install_evaltools_only(args.force)
        else:
            log("Evaltools already available")
    
    if args.install_pyferret:
        if not tools["pyferret"]["available"] or args.force:
            if args.force and tools["pyferret"]["available"]:
                log("Force mode: Reinstalling PyFerret...")
            success &= install_pyferret_standalone(args.force)
        else:
            log("PyFerret already available")
    
    if args.install_cartopy:
        log("Downloading Cartopy Natural Earth data...")
        success &= install_cartopy_data(args.force)
    
    if args.install_bash or args.install_all:
        venv_path = os.environ.get('VIRTUAL_ENV')
        if not venv_path:
            log("ERROR: VIRTUAL_ENV not set. Cannot install bash.", "ERROR")
            log("       Please activate the QLC virtual environment first.", "ERROR")
            success = False
        else:
            bash_path = os.path.join(venv_path, 'bin', 'bash')
            if not os.path.exists(bash_path) or args.force:
                if args.force and os.path.exists(bash_path):
                    log("Force mode: Reinstalling Bash 5.x...")
                log("Installing Bash 5.x into QLC venv...")
                log("This is required for QLC operation and will take 2-5 minutes...")
                success &= install_bash(venv_path, args.force)
            else:
                log("Bash 5.x already installed in venv")
    
    if success:
        log("Tool installation completed successfully!")
        log("Run 'qlc-install-tools --check' to verify installation")
    else:
        log("Some installations failed. Check the output above.", "ERROR")
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
