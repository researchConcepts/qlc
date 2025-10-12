import os
import sys
import shutil
import argparse
import json
from pathlib import Path
try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    import tomli as tomllib  # Python < 3.11

def get_version_from_pyproject(pyproject_path: Path) -> str:
    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)
    return config["project"]["version"]

def read_version_json(version_json_path: Path) -> dict:
    if not version_json_path.exists():
        raise FileNotFoundError(f"[ERROR] VERSION.json not found: {version_json_path}")
    with version_json_path.open("r", encoding="utf-8") as f:
        return json.load(f)

def get_bin_path():
    return Path(sys.executable).resolve().parent

def copy_or_link(src, dst, symlink=False, relative=False):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    if symlink:
        link_target = os.path.relpath(src.resolve(), dst.parent) if relative else src.resolve()
        dst.symlink_to(link_target, target_is_directory=src.is_dir())
    else:
        shutil.copy(src, dst)

def copytree_with_symlinks(src: Path, dst: Path):
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)

    for item in src.iterdir():
        s = src / item.name
        d = dst / item.name
        if s.is_symlink():
            target = os.readlink(s)
            print(f"[LINK] Preserving symlink {d} → {target}")
            d.symlink_to(target)
        elif s.is_dir():
            copytree_with_symlinks(s, d)
        else:
            shutil.copy2(s, d)

def safe_move_and_link(src: Path, dst: Path, relative: bool = False, backup: bool = True):
    """
    Safely create a symlink from dst to src.
    If dst exists, it's backed up (if backup=True) before the new link is created.
    If dst is already a symlink pointing to src, do nothing.
    """
    if dst.is_symlink():
        try:
            if dst.resolve() == src.resolve():
                print(f"[SKIP] Link {dst} already points to {src}")
                return
            else:
                print(f"[INFO] Unlinking existing symlink {dst} -> {dst.readlink()}")
                dst.unlink()
        except FileNotFoundError:
            # This handles broken symlinks
            print(f"[INFO] Removing broken symlink {dst}")
            dst.unlink()

    elif dst.exists():
        if backup:
            backup_dst = dst.with_name(f"{dst.name}_backup_link")
            print(f"[BACKUP] Moving existing path {dst} -> {backup_dst}")
            shutil.move(str(dst), str(backup_dst))
        else:
            print(f"[INFO] Removing existing path {dst}")
            if dst.is_dir():
                shutil.rmtree(dst)
            else:
                dst.unlink()

    # Create the new link
    copy_or_link(src, dst, symlink=True, relative=relative)

def update_qlc_version(config_path: Path, version: str):
    if not config_path.exists():
        raise FileNotFoundError(f"[ERROR] Config file not found: {config_path}")

    lines = config_path.read_text(encoding="utf-8").splitlines()
    new_lines = []
    updated = False

    for line in lines:
        if line.strip().startswith("QLC_VERSION="):
            new_lines.append(f'QLC_VERSION="{version}"')
            updated = True
        else:
            new_lines.append(line)

    if not updated:
        print(f"[WARN] QLC_VERSION=... not found in {config_path}")
    else:
        config_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        print(f"[UPDATED] QLC_VERSION set to {version} in {config_path}")

def setup_data_directories(root: Path, mode: str):
    """
    Creates the two-stage symlink structure for data-heavy directories WITHIN a mode's root.
    - Creates <root>/data
    - Populates it with either real directories (test) or symlinks (cams)
    - Creates top-level symlinks from <root>/* -> <root>/data/*
    """
    print("[SETUP] Configuring data directories...")
    data_dir = root / "data"
    data_dir.mkdir(exist_ok=True)

    # Define the mapping for CAMS mode
    cams_env_map = {
        "Results": "SCRATCH",
        "Analysis": "HPCPERM",
        "Plots": "PERM",
        "Presentations": "PERM",
        "log": "PERM",
        "run": "PERM",
        "output": "PERM"
    }
    
    data_heavy_dirs = ["Results", "Analysis", "Plots", "Presentations", "log", "run", "output"]

    for d in data_heavy_dirs:
        data_subdir = data_dir / d
        
        # Robustly remove existing path before creating a new one
        if data_subdir.is_symlink():
            data_subdir.unlink()
        elif data_subdir.is_dir():
            shutil.rmtree(data_subdir)
        elif data_subdir.exists():
            data_subdir.unlink()

        if mode == "cams":
            env_var = cams_env_map.get(d)
            target_base_path = os.environ.get(env_var)
            
            if target_base_path:
                target_path = Path(target_base_path) / d
                target_path.mkdir(parents=True, exist_ok=True)
                data_subdir.symlink_to(target_path, target_is_directory=True)
                print(f"[LINK] {data_subdir} -> {target_path}")
            else:
                print(f"[WARN] Environment variable ${env_var} not set for {d}. Creating local directory.")
                data_subdir.mkdir(exist_ok=True)
        else: # test mode
            data_subdir.mkdir(exist_ok=True)
            print(f"[MKDIR] {data_subdir}")

        # Create the top-level symlink, e.g., <root>/Results -> <root>/data/Results
        top_level_link = root / d
        if top_level_link.is_symlink() or top_level_link.exists():
            top_level_link.unlink()
        
        # --- Create a relative symlink ---
        # The target is data_subdir, and the link is created at top_level_link.
        # We need the path of the target relative to the link's parent directory.
        relative_target = os.path.relpath(data_subdir, top_level_link.parent)
        top_level_link.symlink_to(relative_target, target_is_directory=True)
        print(f"[LINK] {top_level_link} -> {relative_target}")

def link_model_experiments(mod_data_src_root: Path, results_dst_root: Path, debug: bool = False):
    """
    Links model experiment files from mod_data_src_root to results_dst_root.
    Creates absolute symlinks for the model data files.
    """
    if not mod_data_src_root.is_dir():
        print(f"[WARN] Source directory not found for model experiments: {mod_data_src_root}")
        return

    for exp_dir in mod_data_src_root.iterdir():
        if exp_dir.is_dir():
            # This is an experiment dir, e.g., /path/to/test/mod/b2ro
            results_exp_dir = results_dst_root / exp_dir.name
            results_exp_dir.mkdir(exist_ok=True)
            
            # Find all .grb files, searching recursively through year folders
            for year_dir in exp_dir.iterdir():
                if year_dir.is_dir():
                    for src_file in year_dir.glob('*.grb'):
                        dst_file = results_exp_dir / src_file.name
                        dst_file.parent.mkdir(parents=True, exist_ok=True)
                        # Use absolute paths for these links as they point from the data dir to the mod dir,
                        # which can be far apart.
                        copy_or_link(src_file, dst_file, symlink=True, relative=False)
                        if debug:
                            print(f"[LINK] {dst_file} -> {src_file}")

def setup(mode: str, version: str, debug: bool = False, config_file: str = None):

    # Define source root
    qlc_root = Path(__file__).resolve().parent.parent
    config_src = qlc_root / "qlc" / "config"
    example_src = qlc_root / "qlc" / "examples"
    sh_src = qlc_root / "qlc" / "sh"
    doc_src = qlc_root / "qlc" / "doc"

    from qlc.py.version import QLC_VERSION as version

    # --- QLC paths with isolated PyPI and Dev installations ---
    install_base = Path.home()
    user_home = install_base
    print(f"[INFO] Using $HOME as installation base: {install_base}")
    
    # Determine installation directory based on mode
    # Runtime: qlc_pypi (underscore) for production, qlc_dev (underscore) for development
    # Source: qlc-pypi (hyphen) for public, qlc-dev (hyphen) for private
    if mode == 'dev':
        install_root_name = "qlc_dev"
        stable_link_name = "qlc-dev-run"
        print(f"[INFO] Development mode: using {install_root_name} runtime root")
    else:  # test, cams, interactive
        install_root_name = "qlc_pypi"
        stable_link_name = "qlc"
        print(f"[INFO] Production mode: using {install_root_name} runtime root")
    
    # The versioned installation directory, e.g., $HOME/qlc_pypi/v0.4.1
    versioned_install_dir = user_home / install_root_name / f"v{version}"
    
    # The mode-specific root, e.g., $HOME/qlc_pypi/v0.4.1/test or $HOME/qlc_dev/v0.4.1/dev
    root = versioned_install_dir / mode

    # --- Backup Logic: Back up the entire versioned directory if the specific mode being installed already exists ---
    if root.exists():
        backup_name = f"{versioned_install_dir.name}_backup"
        backup = versioned_install_dir.with_name(backup_name)
        count = 1
        while backup.exists():
            backup = versioned_install_dir.with_name(f"{backup_name}{count}")
            count += 1
        print(f"[BACKUP] Moving existing install root {versioned_install_dir} → {backup}")
        shutil.move(str(versioned_install_dir), str(backup))

    print(f"[SETUP] Mode: {mode}, Version: {version}")
    print(f"[PATHS] QLC Install Root: {root}")
    
    # Create essential directories for the mode
    root.mkdir(parents=True, exist_ok=True)

    # Prepare paths inside the versioned, mode-specific directory
    config_dst = root / "config"
    example_dst = root / "examples"
    bin_dst = root / "bin"
    mod_dst = root / "mod"
    obs_dst = root / "obs"
    doc_dst = root / "doc"
    plug_dst = root / "plugin"
    
    # Create non-data directories inside the mode-specific root
    # NOTE: 'run' and 'output' are now handled by setup_data_directories
    for path in [config_dst, example_dst, bin_dst, mod_dst, obs_dst, doc_dst, plug_dst]:
        path.mkdir(parents=True, exist_ok=True)

    # --- Setup the new data directory structure INSIDE the mode root ---
    setup_data_directories(root, mode)

    # Copy config files
    shutil.copytree(config_src, config_dst, dirs_exist_ok=True)
    print(f"[COPY] {config_src} -> {config_dst}")

    # Link example directories instead of copying
    if example_src.exists():
        for item in example_src.iterdir():
            if item.is_dir(): # Only link directories
                dst_link = example_dst / item.name
                if dst_link.exists() or dst_link.is_symlink():
                    if dst_link.is_dir() and not dst_link.is_symlink():
                        shutil.rmtree(dst_link)
                    else:
                        dst_link.unlink()
                dst_link.symlink_to(item.resolve(), target_is_directory=True)
                print(f"[LINK] {dst_link} -> {item}")

    # Link all documentation files
#   shutil.copytree(doc_src, doc_dst, dirs_exist_ok=True)
    for doc_file in doc_src.glob("*"):
        dst = doc_dst / doc_file.name
        copy_or_link(doc_file, dst, symlink=True, relative=False)
        print(f"[LINK] {dst} -> {doc_file.resolve()}")

    # Link all *.sh files to bin_dst (helpers included)
    for sh_file in sh_src.glob("*.sh"):
        dst = bin_dst / sh_file.name
        copy_or_link(sh_file, dst, symlink=True, relative=False)
        print(f"[LINK] {dst} -> {sh_file.resolve()}")

    # Copy the TeX template directory to bin_dst
    tex_template_src = sh_src / "tex_template"
    tex_template_dst = bin_dst / "tex_template"
    if tex_template_src.is_dir():
        if tex_template_dst.exists():
            shutil.rmtree(tex_template_dst)
        shutil.copytree(tex_template_src, tex_template_dst)
        print(f"[COPY] {tex_template_src} -> {tex_template_dst}")

    # Create shell tool links (now handled by entry_points in setup.py)
    pass

    # In test mode: link obs and mod to examples
    if mode == "test":
        # Link sample observation data as requested
        # 1. $HOME/qlc/obs/data/ver0d/ebas_daily/v_20240216 -> $HOME/qlc/examples/cams_case_1/obs/ebas_daily/v_20240216
        # 2. $HOME/qlc/obs/data/ver0d/ebas_daily/latest -> v_20240216 (relative)
        
        obs_data_source = root / "examples/cams_case_1/obs/ebas_daily/v_20240216"
        obs_data_dest_dir = root / "obs/data/ver0d/ebas_daily"
        obs_data_dest_dir.mkdir(parents=True, exist_ok=True)
        
        # Create the v_20240216 symlink with an absolute path
        link1_target = obs_data_dest_dir / "v_20240216"
        copy_or_link(obs_data_source, link1_target, symlink=True, relative=False)
        print(f"[LINK] {link1_target} -> {obs_data_source.resolve()}")

        # Create the latest symlink, relative to its location
        link2_target = obs_data_dest_dir / "latest"
        if link2_target.exists() or link2_target.is_symlink():
            link2_target.unlink()
        # This one MUST be relative by its nature
        link2_target.symlink_to("v_20240216", target_is_directory=True)
        print(f"[LINK] {link2_target} -> v_20240216")

        # Copy all station files for the test case
        station_files_source_dir = root / "examples/cams_case_1/obs"
        station_files_dest_dir = root / "obs/data"
        if station_files_source_dir.exists():
            # Copy all CSV station files
            for station_file in station_files_source_dir.glob("*.csv"):
                dest_file = station_files_dest_dir / station_file.name
                copy_or_link(station_file, dest_file, symlink=False)
                print(f"[COPY] {dest_file}")


        # Link sample model data, ensuring absolute paths
        mod_data_src_root = root / "examples" / "cams_case_1" / "mod"
        mod_data_dst_root = root / "mod"
        if mod_data_src_root.is_dir():
            for model_dir in mod_data_src_root.iterdir():
                if model_dir.is_dir():
                    dst_link = mod_data_dst_root / model_dir.name
                    # Use copy_or_link to create an absolute symlink
                    copy_or_link(model_dir, dst_link, symlink=True, relative=False)
                    print(f"[LINK] {dst_link} -> {model_dir.resolve()}")

        # Link model experiment files to the 'Results' directory (relative)
        results_dst_root = root / "Results"
        results_dst_root.mkdir(exist_ok=True)
        print(f"[SETUP] Linking model experiments to {results_dst_root}")

        if mod_data_dst_root.is_dir():
            for exp_dir in mod_data_dst_root.iterdir():
                if exp_dir.is_dir():
                    # This is an experiment dir, e.g., /path/to/test/mod/b2ro
                    results_exp_dir = results_dst_root / exp_dir.name
                    results_exp_dir.mkdir(exist_ok=True)
                    
                    # Find all .grb files, searching recursively through year folders
                    for year_dir in exp_dir.iterdir():
                        if year_dir.is_dir():
                            for src_file in year_dir.glob('*.grb'):
                                dst_file = results_exp_dir / src_file.name
                                dst_file.parent.mkdir(parents=True, exist_ok=True)
                                # Use absolute paths for these links as they point from the data dir to the mod dir,
                                # which can be far apart.
                                copy_or_link(src_file, dst_file, symlink=True, relative=False)
                                if debug:
                                    print(f"[LINK] {dst_file} -> {src_file}")

    # In CAMS mode: link to operational directories
    if mode == "cams":
        # Link obs data directory
        cams_obs_src = Path("/ec/vol/cams/qlc/obs")
        if obs_dst.is_symlink() or obs_dst.is_symlink():
            obs_dst.unlink()
        elif obs_dst.is_dir():
            shutil.rmtree(obs_dst)
        obs_dst.symlink_to(cams_obs_src, target_is_directory=True)
        print(f"[LINK] {obs_dst} -> {cams_obs_src}")
        
        # Link mod directory to this mode's internal Results directory
        results_link = root / "Results"
        if mod_dst.is_symlink() or mod_dst.is_symlink():
            mod_dst.unlink()
        elif mod_dst.is_dir():
            shutil.rmtree(mod_dst)
        mod_dst.symlink_to(results_link, target_is_directory=True)
        print(f"[LINK] {mod_dst} -> {results_link}")

    # The config is now static, just need to update the version
    generic_config_path = config_dst / "qlc.conf"
    update_qlc_version(generic_config_path, version)

    # --- Setup master symlinks for isolated PyPI/Dev installations ---
    
    # Create the new two-level symlink structure:
    # 1. qlc_pypi/current -> v0.4.1 (or qlc_dev/current -> v0.4.1)
    # 2. ~/qlc -> qlc_pypi/current/test (or ~/qlc-dev-run -> qlc_dev/current/dev)
    
    install_root = versioned_install_dir.parent  # e.g., ~/qlc_pypi or ~/qlc_dev
    current_link = install_root / "current"
    stable_link = user_home / stable_link_name  # qlc or qlc-dev-run
    
    # Create/update current -> v0.4.1 (inside qlc_pypi or qlc_dev)
    if current_link.is_symlink():
        current_link.unlink()
    elif current_link.exists():
        shutil.rmtree(current_link)
    
    # Create relative symlink to version directory
    current_link.symlink_to(versioned_install_dir.name, target_is_directory=True)
    print(f"[LINK] {current_link} -> {versioned_install_dir.name}")
    
    # Create/update ~/qlc or ~/qlc-dev-run -> qlc_pypi/current/test (or dev)
    if stable_link.is_symlink():
        stable_link.unlink()
    elif stable_link.exists():
        if stable_link.is_dir():
            print(f"[WARN] {stable_link} exists as directory, not overwriting")
        else:
            stable_link.unlink()
    
    # Create relative symlink from home to runtime directory
    relative_target = os.path.relpath(root, user_home)
    stable_link.symlink_to(relative_target, target_is_directory=True)
    print(f"[LINK] {stable_link} -> {relative_target}")


    # Write install info
    info = {
        "version": version,
        "mode": mode,
        "config": "qlc.conf"
    }

    (root / "VERSION.json").write_text(json.dumps(info, indent=2))
    print(f"[WRITE] VERSION.json at {root}")

    # Final version update on the stable link path
    update_qlc_version(stable_link / "config" / "qlc.conf", version)

    print("\n[INFO] QLC installation complete.")
    print("[INFO] The following commands are now available: qlc, qlc-py, sqlc, qlc-install")
    print("\n[ACTION REQUIRED]")
    print("To make these commands available, you may need to add the local bin directory to your PATH.")
    print("For most bash users, you can do this by running the following command:")
    print("  echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.bashrc")
    print("\nFor other shells (like zsh), you may need to add this line to '~/.zshrc' instead.")
    print("After running the command, please open a new terminal or run 'source ~/.bashrc' to apply the changes.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install QLC runtime structure")
    parser.add_argument("--cams", action="store_true", help="Install in CAMS mode")
    parser.add_argument("--test", action="store_true", help="Install in TEST mode")
    parser.add_argument("--interactive", type=str, help="Install using custom config path")
    parser.add_argument("--version", type=str, help="Override QLC version")

    args = parser.parse_args()
    if args.cams:
        setup("cams", version=args.version)
    elif args.test:
        setup("test", version=args.version)
    elif args.interactive:
        setup("interactive", config_file=args.interactive, version=args.version)
    else:
        parser.print_help()