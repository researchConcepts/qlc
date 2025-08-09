import argparse
from qlc.install import setup
from qlc.py.version import QLC_VERSION

def main():
    parser = argparse.ArgumentParser(description="QLC Installer")
    parser.add_argument(
        "--mode",
        choices=["cams", "test", "interactive"],
        default="test",
        help="Installation mode: test (for tests), cams (for CAMS), or interactive (development)"
    )
    args = parser.parse_args()

    print(f"[QLC-INSTALL] Installing QLC version {QLC_VERSION} in '{args.mode}' mode")
    setup(mode=args.mode, version=QLC_VERSION)
