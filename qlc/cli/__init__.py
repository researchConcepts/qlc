# QLC module package init
import os
import subprocess
import sys

def run_shell_driver():
    # Correctly locate the 'sh' directory relative to the package installation
    sh_dir = os.path.join(os.path.dirname(__file__), '..', 'sh')
    script = os.path.join(sh_dir, "qlc_main.sh")
    subprocess.run(["bash", script] + sys.argv[1:])

def run_python_driver():
    # This function seems to be for a different purpose, ensure qlc_main is correct
    from qlc.cli.qlc_main import main
    main()

def run_batch_driver():
    # Correctly locate the 'sh' directory relative to the package installation
    sh_dir = os.path.join(os.path.dirname(__file__), '..', 'sh')
    script = os.path.join(sh_dir, "qlc_start_batch.sh")
    subprocess.run(["bash", script] + sys.argv[1:])
