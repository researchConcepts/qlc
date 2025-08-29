import os
import sys
import subprocess
from datetime import datetime
from pathlib import Path

def main():
    """
    Python entry point for running the main QLC processing script.
    This script now acts as a silent wrapper. All console output
    is handled by the logging configuration in the downstream qlc_main module.
    """
    # --- Ensure QLC home directory exists ---
    qlc_home = Path.home() / "qlc"
    # The qlc-install script creates this directory.
    # If it's not here, the user needs to run the installer.
    if not qlc_home.is_dir():
        # Use print here because logging is not yet configured and this is a pre-flight check.
        print(f"[ERROR] QLC home directory not found at: {qlc_home}")
        print("Please run 'qlc-install' to set up the required structure.")
        sys.exit(1)

    os.chdir(qlc_home)

    # Determine config path. Default to the standard location if no args are given.
    # Look for a --config flag.
    config_arg_present = "--config" in sys.argv
    stdin_mode = False
    config_path_str = str(qlc_home / "config" / "json" / "qlc_config.json") # Default

    if config_arg_present:
        config_idx = sys.argv.index("--config")
        if len(sys.argv) > config_idx + 1:
            config_value = sys.argv[config_idx + 1]
            if config_value == '-':
                stdin_mode = True
                config_path_str = '-' # Pass the stdin marker to the subprocess
            else:
                config_path_str = config_value # A specific file was passed
        else:
            # This case should be caught by argparse in the child, but we can be safe.
            print("[ERROR] --config flag was provided without a value.", file=sys.stderr)
            sys.exit(1)

    python_executable = sys.executable
    command = [
        python_executable,
        "-m",
        "qlc.cli.qlc_main",
        "--config",
        config_path_str,
    ]
    
    try:
        # If in stdin mode, we need to pass our stdin to the subprocess.
        # Otherwise, the subprocess runs without piped data.
        if stdin_mode:
            subprocess.run(
                command,
                check=True,
                text=True,
                stdin=sys.stdin  # Pass stdin through
            )
        else:
            subprocess.run(
                command,
                check=True,
                text=True,
            )
    except subprocess.CalledProcessError as e:
        # The error output from the subprocess will have already been printed.
        sys.exit(e.returncode)
    except Exception as e:
        print(f"A critical error occurred in the QLC wrapper: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

