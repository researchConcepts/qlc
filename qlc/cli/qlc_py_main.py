import os
import sys
import subprocess
from datetime import datetime
from pathlib import Path

def main():
    """
    Python entry point for running the main QLC processing script.
    """
    script_name = sys.argv[0]
    print("________________________________________________________________________________________")
    print(f"Start {script_name} at {datetime.now()}")
    print("----------------------------------------------------------------------------------------")

    # --- Change to QLC home directory ---
    qlc_home = Path.home() / "qlc"
    if not qlc_home.is_dir():
        print(f"[ERROR] QLC home directory not found at: {qlc_home}")
        print("Please run 'qlc-install' to set up the required structure.")
        sys.exit(1)
    
    os.chdir(qlc_home)
    print(f"Changed working directory to: {os.getcwd()}")
    # ---

    config_path = sys.argv[1] if len(sys.argv) > 1 else str(Path.home() / "qlc" / "config" / "json" / "qlc_config.json")
    log_dir = qlc_home / "log"
    log_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"qlc_run_{timestamp}.log"

    print("************************************************************************************************")
    print(f"Running {script_name} with output logged to {log_file}")

    # The command will use the same Python interpreter that is running this script
    python_executable = sys.executable
    command = [
        python_executable,
        "-m",
        "qlc.cli.qlc_main",
        "--config",
        config_path,
    ]
    
    print(f"Executing command: {' '.join(command)}")

    try:
        with open(log_file, "w") as lf:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True,
            )
            if process.stdout:
                for line in process.stdout:
                    print(line, end="")
                    lf.write(line)
            process.wait()

    except Exception as e:
        print(f"An error occurred: {e}")

    print("________________________________________________________________________________________")
    print(f"End   {script_name} at {datetime.now()}")
    print("________________________________________________________________________________________")

if __name__ == "__main__":
    main()

