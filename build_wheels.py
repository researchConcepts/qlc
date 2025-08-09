#!/usr/bin/env python3
"""
Robust wheel build script for QLC.

- Uses a specified Python interpreter (or current) to create a clean build venv
- Installs pypa/build and friends
- Builds wheels with isolated PEP 517 (respects pyproject and oldest-supported-numpy)
- Prints environment details for traceability
- Optionally checks the wheel with twine and verifies imports in a temp venv
"""

import argparse
import os
import sys
import subprocess
import platform
from pathlib import Path

ROOT = Path(__file__).resolve().parent


from typing import List, Union, Optional, Dict


def run(cmd: Union[List[str], str], cwd: Optional[Path] = None, env: Optional[Dict[str, str]] = None) -> subprocess.CompletedProcess:
    if isinstance(cmd, list):
        pretty = " ".join(cmd)
    else:
        pretty = cmd
    print(f"[RUN] {pretty}")
    return subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=True, shell=isinstance(cmd, str))


def abort_if_failed(res: subprocess.CompletedProcess, context: str):
    if res.returncode != 0:
        print(f"[ERROR] {context} failed (code {res.returncode})\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}")
        sys.exit(res.returncode)


def clean_build():
    print("[CLEAN] Removing build artifacts...")
    for p in [ROOT / "build", ROOT / "dist"]:
        if p.exists():
            res = run(["rm", "-rf", str(p)])
            abort_if_failed(res, f"rm {p}")
    # Remove egg-info and generated C files and .so
    res = run("find . -name '*.egg-info' -maxdepth 2 -exec rm -rf {} +")
    res = run("find qlc/py -name '*.c' -delete")
    res = run("find qlc -name '*.so' -delete")


def ensure_tools(python: Path):
    print(f"[SETUP] Ensuring build tools in {python}")
    res = run([str(python), "-m", "pip", "install", "--upgrade", "pip", "build", "setuptools", "wheel", "cython", "twine"])
    abort_if_failed(res, "pip install tools")


def build_with_interpreter(python: Path):
    print("[ENV] Build interpreter details:")
    res = run([str(python), "-c", "import sys,platform; print(sys.version); print(platform.platform())"])
    abort_if_failed(res, "print interpreter info")
    print(res.stdout)

    # Use PEP 517 isolated build (pyproject controls build deps, including oldest-supported-numpy)
    print("[BUILD] Building wheel (isolated) via pypa/build...")
    res = run([str(python), "-m", "build", "--wheel"])  # isolated by default
    abort_if_failed(res, "pypa/build wheel")


def twine_check(python: Path):
    print("[CHECK] twine check")
    wheels = sorted((ROOT / "dist").glob("*.whl"))
    if not wheels:
        print("[WARN] No wheels found in dist/")
        return
    for whl in wheels:
        res = run([str(python), "-m", "twine", "check", str(whl)])
        abort_if_failed(res, f"twine check {whl.name}")


def verify_imports(python: Path):
    print("[VERIFY] Creating temp venv to verify imports...")
    venv_dir = ROOT / ".qlc_verify_env"
    if venv_dir.exists():
        run(["rm", "-rf", str(venv_dir)])
    res = run([str(python), "-m", "venv", str(venv_dir)])
    abort_if_failed(res, "create verify venv")
    vpy = venv_dir / ("Scripts/python.exe" if platform.system() == "Windows" else "bin/python")
    res = run([str(vpy), "-m", "pip", "install", "--upgrade", "pip"])  # speed up
    res = run([str(vpy), "-m", "pip", "install", str(next((ROOT / "dist").glob("*.whl")))])
    abort_if_failed(res, "pip install built wheel into verify env")
    code = (
        "import sys, platform; print('PY', sys.version); print('PLAT', platform.platform());\n"
        "import qlc; from qlc.py import version as v; print('QLC_VERSION', v.QLC_VERSION)\n"
    )
    res = run([str(vpy), "-c", code])
    abort_if_failed(res, "verify import")
    print(res.stdout)


def main():
    ap = argparse.ArgumentParser(description="Build QLC wheels in a controlled way")
    ap.add_argument("--python", default=sys.executable, help="Path to the Python interpreter to use for building (e.g. your target 3.10)")
    ap.add_argument("--no-clean", action="store_true", help="Do not clean build artifacts before building")
    ap.add_argument("--skip-check", action="store_true", help="Skip twine check")
    ap.add_argument("--skip-verify", action="store_true", help="Skip import verification in a temp venv")
    args = ap.parse_args()

    build_python = Path(args.python).resolve()
    print("QLC Wheel Builder")
    print("=" * 60)
    print(f"Platform: {platform.system()} {platform.machine()}\nBuild Python: {build_python}")

    if not args.no_clean:
        clean_build()

    ensure_tools(build_python)
    build_with_interpreter(build_python)

    if not args.skip_check:
        twine_check(build_python)

    if not args.skip_verify:
        verify_imports(build_python)

    print("\nBuilt files:")
    for f in sorted((ROOT / "dist").glob("*")):
        print("  ", f)
    return 0

if __name__ == "__main__":
    sys.exit(main())
