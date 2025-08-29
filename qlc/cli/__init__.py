# QLC module package init
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

def run_shell_driver():
    """
    Finds and executes qlc_main.sh, capturing its output for logging.
    This acts as the entry point for the 'qlc' command.
    """
    # Correctly locate the 'sh' directory relative to the package installation
    sh_dir = os.path.join(os.path.dirname(__file__), '..', 'sh')
    script = os.path.join(sh_dir, "qlc_main.sh")

    # Determine log directory from QLC_HOME or fall back to a default
    # This mirrors the logic that the shell scripts would use.
    qlc_home_str = os.environ.get("QLC_HOME", f"{os.path.expanduser('~')}/qlc")
    log_dir = os.path.join(qlc_home_str, "log")
    os.makedirs(log_dir, exist_ok=True)

    # Create a timestamped log file for the shell script's output
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file_path = os.path.join(log_dir, f"qlc_shell_main_{timestamp}.log")
    print(f"[QLC Wrapper] Logging shell script output to: {log_file_path}")

    try:
        # Use a list of strings for Popen
        command = [str(script)] + sys.argv[1:]
        
        with open(log_file_path, 'w', encoding='utf-8') as log_file:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1, # Line-buffered
                universal_newlines=True
            )
            
            # Real-time stream processing
            for line in process.stdout:
                # Write to file without adding a newline, as 'line' already has one
                log_file.write(line)
                # Print to console, stripping the newline to avoid double spacing
                sys.stdout.write(line)
            
            process.wait()

        if process.returncode != 0:
            print(f"\n[ERROR] Shell script exited with non-zero code: {process.returncode}", file=sys.stderr)
            sys.exit(process.returncode)

    except FileNotFoundError:
        print(f"Error: Could not find the qlc_main.sh script at {script}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)


def run_batch_driver():
    """
    Finds and executes qlc_batch.sh, capturing its output for logging.
    This acts as the entry point for the 'sqlc' command.
    """
    try:
        sh_dir = Path(__file__).resolve().parent.parent / "sh"
        script_path = sh_dir / "qlc_batch.sh"
        if not script_path.is_file():
            print(f"[ERROR] Batch script not found at: {script_path}", file=sys.stderr)
            sys.exit(1)

        # Ensure the script is executable
        script_path.chmod(script_path.stat().st_mode | 0o111)

        # Determine log directory from config
        home = Path.home()
        log_dir_str = os.environ.get("QLC_LOG_DIR", str(home / "qlc" / "log"))
        log_dir = Path(log_dir_str)
        log_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file_path = log_dir / f"sqlc_shell_main_{timestamp}.log"
        print(f"[QLC Batch Wrapper] Logging shell script output to: {log_file_path}")

        command = [str(script_path)] + sys.argv[1:]
        
        with open(log_file_path, 'w', encoding='utf-8') as log_file:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            for line in process.stdout:
                log_file.write(line)
                sys.stdout.write(line)
            
            process.wait()

        if process.returncode != 0:
            print(f"\n[ERROR] Batch script exited with non-zero code: {process.returncode}", file=sys.stderr)
            sys.exit(process.returncode)

    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)
