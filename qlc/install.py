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

def copy_or_link(src, dst, symlink=False):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    if symlink:
        dst.symlink_to(src.resolve())
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

def safe_move_and_link(source: Path, target: Path):
    """
    Ensures `target` is a symlink to `source`. 
    If `target` exists but points elsewhere (or is a dir), it gets backed up first.
    """
    if target.is_symlink():
        current = target.resolve()
        if current == source.resolve():
            print(f"[SKIP] {target} already links to {source}")
            return
        else:
            print(f"[BACKUP] {target} symlink points to {current}, backing up")
    elif target.exists():
        if target.is_dir():
            # Only backup if it's not the install root (we don't want to mv source itself)
            if target.resolve() != source.resolve():
                backup = target.with_name(f"{target.name}_backup")
                count = 1
                while backup.exists():
                    backup = target.with_name(f"{target.name}_backup{count}")
                    count += 1
                print(f"[BACKUP] Moving existing directory {target} → {backup}")
                shutil.move(str(target), str(backup))
        else:
            # File or other type — always back up
            backup = target.with_name(f"{target.name}_backup")
            count = 1
            while backup.exists():
                backup = target.with_name(f"{target.name}_backup{count}")
                count += 1
            print(f"[BACKUP] Moving existing file {target} → {backup}")
            shutil.move(str(target), str(backup))

    print(f"[LINK] {target} → {source}")
    target.symlink_to(source, target_is_directory=True)

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

def setup(mode, config_file=None, version="latest"):

    # Define source root
    qlc_root = Path(__file__).resolve().parent.parent
    config_src = qlc_root / "qlc" / "config"
    example_src = qlc_root / "qlc" / "examples"
    sh_src = qlc_root / "qlc" / "sh"
    doc_src = qlc_root / "qlc" / "doc"

    from qlc.py.version import QLC_VERSION as version

    # Select appropriate configuration file
    if mode == "cams":
        perm_path = Path(os.environ.get("PERM", "/perm")) / os.environ.get("USER", "user")
        user_home = perm_path
        selected_conf = config_src / "qlc_cams.conf"
    elif mode == "test":
        user_home = Path.home()
        selected_conf = config_src / "qlc_test.conf"
    elif mode == "interactive":
        if not config_file:
            raise ValueError("You must provide a config file via --interactive=<path>")
        selected_conf = Path(config_file)
    else:
        raise ValueError(f"Unsupported mode: {mode}")

    source = user_home / f"qlc_v{version}"

    if source.exists() and not source.is_symlink():
        backup = source.with_name(f"{source.name}_backup")
        count = 1
        while backup.exists():
            backup = source.with_name(f"{source.name}_backup{count}")
            count += 1
        print(f"[BACKUP] Moving existing install root {source} → {backup}")
        shutil.move(str(source), str(backup))

    root = source / mode
#   safe_move_and_link(source, Path.home() / f"qlc_v{version}")

    print(f"[SETUP] Mode: {mode}, Version: {version}")
    print(f"[PATHS] QLC Root: {root}")

    # Prepare paths
    config_dst = root / "config"
    example_dst = root / "examples"
    bin_dst = root / "bin"
    log_dst = root / "log"
    mod_dst = root / "mod"
    obs_dst = root / "obs"
    doc_dst = root / "doc"
    run_dst = root / "run"
    out_dst = root / "output"
    plug_dst = root / "plugin"

    # Create distribution directories
    for path in [bin_dst, log_dst, mod_dst, obs_dst, doc_dst, run_dst, out_dst, plug_dst, example_dst, config_dst]:
        path.mkdir(parents=True, exist_ok=True)

    # Copy config files
    if config_dst.exists():
        copytree_with_symlinks(config_src, config_dst)

    # Copy example files
    if example_src.exists():
#       shutil.copytree(example_src, example_dst, dirs_exist_ok=True, symlinks=True)
        copytree_with_symlinks(example_src, example_dst)

    # Link all documentation files
#   shutil.copytree(doc_src, doc_dst, dirs_exist_ok=True)
    for doc_file in doc_src.glob("*"):
        dst = doc_dst / doc_file.name
        copy_or_link(doc_file, dst, symlink=True)

    # Link all *.sh files to bin_dst (helpers included)
    for sh_file in sh_src.glob("*.sh"):
        dst = bin_dst / sh_file.name
        copy_or_link(sh_file, dst, symlink=True)

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
        
        # Create the v_20240216 symlink
        link1_target = obs_data_dest_dir / "v_20240216"
        if link1_target.exists() or link1_target.is_symlink():
            link1_target.unlink()
        link1_target.symlink_to(obs_data_source.resolve(), target_is_directory=True)
        print(f"[LINK] {link1_target} -> {obs_data_source}")

        # Create the latest symlink, relative to its location
        link2_target = obs_data_dest_dir / "latest"
        if link2_target.exists() or link2_target.is_symlink():
            link2_target.unlink()
        link2_target.symlink_to("v_20240216", target_is_directory=True)
        print(f"[LINK] {link2_target} -> v_20240216")

        # Copy the station file for the test case
        station_file_source = root / "examples/cams_case_1/obs/ebas_station-locations.csv"
        station_file_dest = root / "obs/data/ebas_station-locations.csv"
        if station_file_source.exists():
            copy_or_link(station_file_source, station_file_dest, symlink=False)
            print(f"[COPY] {station_file_dest}")


        # Link sample model data (unchanged)
        mod_data_src_root = root / "examples" / "cams_case_1" / "mod"
        mod_data_dst_root = root / "mod"
        if mod_data_src_root.is_dir():
            for model_dir in mod_data_src_root.iterdir():
                if model_dir.is_dir():
                    mod_data_dst = mod_data_dst_root / model_dir.name
                    if mod_data_dst.exists() or mod_data_dst.is_symlink():
                        mod_data_dst.unlink()
                    mod_data_dst.symlink_to(model_dir.resolve(), target_is_directory=True)
                    print(f"[LINK] {mod_data_dst} -> {model_dir}")

    # Create a generic qlc.conf symlink
    config_dir = root / "config"
    generic_config_path = config_dir / "qlc.conf"
    if generic_config_path.exists() or generic_config_path.is_symlink():
        generic_config_path.unlink()
    
    if selected_conf.exists():
        generic_config_path.symlink_to(selected_conf.name)
        print(f"[LINK] {generic_config_path} -> {selected_conf.name}")

    # Write install info
    info = {
        "version": version,
        "mode": mode,
        "config": selected_conf.name
    }

    # Preemptively remove 'qlc_latest' symlink to ensure clean update, mimicking `ln -sf`.
    qlc_latest_link = Path.home() / "qlc_latest"
    if qlc_latest_link.is_symlink():
        qlc_latest_link.unlink()

    safe_move_and_link(root, qlc_latest_link)
    safe_move_and_link(qlc_latest_link, Path.home() / "qlc")

    (root / "VERSION.json").write_text(json.dumps(info, indent=2))
    print(f"[WRITE] VERSION.json at {root}")

    version_info = read_version_json(Path.home() / "qlc" / "VERSION.json")
    update_qlc_version(generic_config_path, version_info["version"])

    print("\n[INFO] QLC installation complete.")
    print("[INFO] To get started, you may need to open a new terminal or run 'rehash'.")
    print("[INFO] The following commands are now available: qlc, qlc-py, sqlc, qlc-install")

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