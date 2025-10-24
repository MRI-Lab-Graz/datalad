#!/usr/bin/env python3

import os
import re
import subprocess
import argparse
import glob
import shutil
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def get_bidscoin_version(yaml_path):
    """Extract bidscoin version from bidsmap.yaml."""
    if not os.path.exists(yaml_path):
        print(f"[ERROR] bidsmap.yaml not found: {yaml_path}")
        return None
    try:
        with open(yaml_path, "r") as f:
            for line in f:
                if line.strip().startswith("version:"):
                    version_str = line.split(":", 1)[1].strip()
                    match = re.search(r"(\d+\.\d+\.\d+)", version_str)
                    if match:
                        return match.group(1)
        print(f"[WARN] No version found in {yaml_path}")
        return None
    except Exception as e:
        print(f"[ERROR] Failed to read {yaml_path}: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Run bidscoiner on a single BIDS study using correct environment and deface anatomical images."
    )
    parser.add_argument(
        "study_dir",
        type=str,
        help="Path to the study directory (e.g., /data/local/BIDSCOINER/STUDY123)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Show commands without executing"
    )
    args = parser.parse_args()

    study_dir = Path(args.study_dir).resolve()
    if not study_dir.exists():
        print(f"[ERROR] Study directory does not exist: {study_dir}")
        return

    # Paths
    bds_dir = study_dir.parent
    bidsmap_yaml = study_dir / "rawdata" / "code" / "bidscoin" / "bidsmap.yaml"
    sourcedata = study_dir / "sourcedata"
    rawdata = study_dir / "rawdata"

    # Get version
    version = get_bidscoin_version(bidsmap_yaml)
    if not version:
        print("[ERROR] Could not determine bidscoin version. Aborting.")
        return

    # Environment setup
    env_dir = bds_dir / "_ENVIRONMENTS" / f"bidscoin_v{version}"
    activate_script = env_dir / "env" / "bin" / "activate"

    if not activate_script.exists():
        print(f"[ERROR] Virtual environment not found: {activate_script}")
        return

    print(f"[INFO] Using bidscoin version: {version}")
    print(f"[INFO] Environment: {activate_script}")

    cmd = f"source {activate_script} && bidscoiner {sourcedata} {rawdata}"
    print(f"\n[RUN] {cmd}")

    if args.dry_run:
        print("   [DRY-RUN] Skipping execution.")
    else:
        try:
            result = subprocess.run(
                cmd, shell=True, check=True, capture_output=True, text=True
            )
            print("[SUCCESS] bidscoiner completed for the whole study")
        except subprocess.CalledProcessError as e:
            print("[ERROR] bidscoiner failed:")
            print(e.stderr)
            return

    # Defacing part starts here
    study_name = study_dir.name
    faced_dir = str(sourcedata / "bidsonym" / "faced")
    subject_dirs = glob.glob(str(rawdata / "sub-*"))

    metas = []
    for subj_dir in subject_dirs:
        subj_name = os.path.basename(subj_dir)
        if not subj_name.startswith('sub-'):
            print(f"[INFO] Skipping invalid subject directory: {subj_name}")
            continue

        parts = subj_name.split('sub-')[1]
        if len(parts) < len(study_name):
            print(f"[INFO] Invalid subject format: {subj_name}")
            continue
        study, subjnr = parts[:len(study_name)], parts[len(study_name):]
        if study != study_name:
            print(f"[INFO] Skipping subject {subj_name} (study {study} does not match {study_name})")
            continue

        sessions = [os.path.basename(s) for s in glob.glob(os.path.join(subj_dir, 'ses-*'))]
        if not sessions:
            print(f"[INFO] No sessions found for {subj_name}")
            continue
        meta = {'study': study, 'subjnr': subjnr, 'sessions': sessions}
        metas.append(meta)

    print("Defacing starts now")
    print("The following subjects will be defaced:")
    for meta in metas:
        print(f" - sub-{meta['study']}{meta['subjnr']} (sessions: {', '.join(meta['sessions'])})")

    if not metas:
        print("[INFO] No subjects to deface.")
        return

    if args.dry_run:
        print("[INFO] Would perform defacing for the above subjects (dry-run mode)")
    else:
        response = input("Do you want to proceed with defacing these subjects? (Y/n): ").strip().lower()
        if response != 'y':
            print("Defacing cancelled by user.")
            return

    if not args.dry_run:
        print("Creating faced directory...")
        os.makedirs(faced_dir, exist_ok=True)
        print("Faced directory created.")
    else:
        print("[INFO] Would create faced directory.")

    def process_image(img_path):
        img_path = Path(img_path)
        filename = img_path.name
        dest_path = os.path.join(faced_dir, f"faced_{filename}")
        if os.path.exists(dest_path):
            print(f"[INFO] Already defaced (backup exists): {img_path}, skipping.")
            return
        print(f"Copying {filename} to faced directory...")
        if not args.dry_run:
            shutil.copy(img_path, dest_path)
        print(f"File copied: {dest_path}")
        print(f"Defacing file: {img_path}")
        if not args.dry_run:
            try:
                subprocess.run(['pydeface', str(img_path), '--outfile', str(img_path), '--force'], check=True)
                print(f"File defaced: {img_path}")
            except subprocess.CalledProcessError as e:
                print(f"Error defacing {img_path}: {e}")

    for meta in metas:
        print(f"Subject Number: {meta['subjnr']}")
        print(f"Sessions: {', '.join(meta['sessions'])}")

        subject_path = str(rawdata / f"sub-{meta['study']}{meta['subjnr']}")
        image_patterns = ['*_T1w.nii.gz', '*_T2w.nii.gz', '*_PDw.nii.gz']
        image_files = []
        print("Finding and processing T1w, T2w, and PDw images...")
        for pattern in image_patterns:
            image_files.extend(glob.glob(os.path.join(subject_path, 'ses-*', 'anat', pattern)))

        if not image_files:
            print(f"[INFO] No anatomical images found for sub-{meta['study']}{meta['subjnr']}")
            continue

        if args.dry_run:
            print(f"[INFO] Would process {len(image_files)} images for sub-{meta['study']}{meta['subjnr']}")
            for img in image_files:
                dest_path = os.path.join(faced_dir, f"faced_{os.path.basename(img)}")
                if os.path.exists(dest_path):
                    print(f"[INFO] Already defaced: {img}")
                else:
                    print(f"[INFO] Would deface: {img}")
        else:
            with ThreadPoolExecutor(max_workers=5) as executor:
                executor.map(process_image, image_files)

        print(f"Copying and defacing completed for subject {meta['study']}{meta['subjnr']}\n")


if __name__ == "__main__":
    main()
