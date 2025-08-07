# setup.py
try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    import toml as tomllib  # Use third-party `toml` package for <3.11
import datetime
from pathlib import Path
from setuptools import setup, Extension, find_packages
from Cython.Build import cythonize
from qlc.install import CustomInstallCommand

# --- Helper functions ---

def get_version_from_pyproject(pyproject_path: Path) -> str:
    if tomllib.__name__ == "toml":
        with pyproject_path.open("r", encoding="utf-8") as f:
            config = tomllib.load(f)
    else:
        with pyproject_path.open("rb") as f:
            config = tomllib.load(f)
    return config["project"]["version"]

def generate_version_pyx(version: str, output_path: Path):
    template_path = Path("qlc/py/version.pyx.in")
    content = template_path.read_text()
    content = content.replace("@QLC_VERSION@", version)
    content = content.replace("@QLC_RELEASE_DATE@", datetime.date.today().isoformat())
    output_path.write_text(content)

# --- Main setup logic ---

root = Path(__file__).parent
version = get_version_from_pyproject(root / "pyproject.toml")

# Generate version.pyx from template
generate_version_pyx(version, root / "qlc/py/version.pyx")

# Gather pyx files from qlc
pyx_files = list(Path("qlc/py").glob("*.pyx"))

# Define Cython extension(s)
extensions = cythonize(
    [Extension("qlc." + f.stem, [str(f)]) for f in pyx_files],
    compiler_directives={"language_level": "3"}
)

# Long description from doc
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setup(
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://pypi.org/project/qlc/",
    packages=find_packages(),
    ext_modules=extensions,
    include_package_data=True,
    zip_safe=False,

    entry_points={
        "console_scripts": [
            "qlc=qlc.cli:run_shell_driver",
            "qlc-py=qlc.cli:run_python_driver",
            "sqlc=qlc.cli:run_batch_driver"
        ]
    },

    package_data={
        "qlc": ["*.so"],  # Optional: add sh, conf, doc, etc. if needed
    },

    cmdclass={
        "install": CustomInstallCommand
    },

    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: Unix"
    ],
)