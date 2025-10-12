import argparse
from qlc.install import setup
from qlc.py.version import QLC_VERSION

def main():
    parser = argparse.ArgumentParser(
        description="Install the QLC runtime environment.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--mode",
        type=str,
        choices=['test', 'cams', 'dev', 'interactive'],
        required=True,
        help="The installation mode.\n"
             "'test': A standalone mode with bundled example data (PyPI).\n"
             "'cams': An operational mode for CAMS environments.\n"
             "'dev': Development mode for parallel testing (creates qlc_dev runtime).\n"
             "'interactive': A mode for developers to use a custom config."
    )
    parser.add_argument("--version", type=str, help="Override QLC version (for development)")
    parser.add_argument("--config", type=str, help="[interactive mode only] Path to a custom config file.")


    args = parser.parse_args()

    print(f"[QLC-INSTALL] Installing QLC version {QLC_VERSION} in '{args.mode}' mode")
    if args.mode == 'interactive' and not args.config:
        parser.error("--config is required when using --mode interactive")
    
    # Use a dummy version if not provided, as the setup script will find the real one
    version = args.version if args.version else "0.0.0"
    
    setup(mode=args.mode, version=version, config_file=args.config)
    return 0
