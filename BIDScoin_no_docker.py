import os
import re
import subprocess
from collections import defaultdict
import argparse
import glob
import shutil
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# parse command-line arguments
parser = argparse.ArgumentParser(description="BIDS processing script with dry-run option")
parser.add_argument('--dry-run', action='store_true', help="Perform a dry run without executing file operations")
args = parser.parse_args()

params = {
    'dcm_dir': '/data/local/DICOM_RAW',
    'bds_dir': '/data/local/BIDSCOINER',
    'mrivault_dir': '/data/mrivault/_0_STAGING'
}

def get_bidscoin_version(path):
    if not os.path.exists(path):
        print(f"[INFO] Would check if file exists: {path} (not found)")
        return None
    try:
        with open(path, 'r') as f:
            content = f.read()
        for line in content.splitlines():
            if line.strip().startswith('version:'):
                version_string = line.split(':', 1)[1].strip()
                matcher = re.search(r'(\d+\.\d+\.\d+)', version_string)
                if matcher:
                    return matcher.group(1)
    except Exception as e:
        print(f"Error reading YAML file: {e}")
    return None

raw_dirs = glob.glob(os.path.join(params['dcm_dir'], '1*_*/1*_*'))

metas = []
for path in raw_dirs:
    file_name = os.path.basename(path)
    parts = file_name.split('_')
    if len(parts) != 2:
        print(f"[INFO] Invalid directory name: {file_name}")
        continue
    study, subjnr = parts
    yaml_path = os.path.join(params['bds_dir'], study, 'rawdata', 'code', 'bidscoin', 'bidsmap.yaml')
    version = get_bidscoin_version(yaml_path)
    if version is None:
        print(f"[INFO] No version found for {yaml_path}")
        continue
    try:
        ses = os.listdir(path)[0]
    except IndexError:
        print(f"[INFO] No contents in directory: {path}")
        continue
    meta = {'study': study, 'subjnr': subjnr, 'version': version, 'ses': ses}
    metas.append((meta, path))

for meta, path in metas:
    print(f"\nstudy: {meta['study']}")
    print(f"session: {meta['ses']}")
    print(f"subjectnr: {meta['subjnr']}")
    print(f"version: {meta['version']}")
    
    sourcedata_ses = os.path.join(params['bds_dir'], meta['study'], 'sourcedata', f"sub-{meta['study']}_{meta['subjnr']}", meta['ses'])
    rawdata = os.path.join(params['bds_dir'], meta['study'], 'rawdata')
    
    print(f"[INFO] Would create directory: {sourcedata_ses}")
    print(f"[INFO] Would create directory: {rawdata}")
    
    src = os.path.join(path, meta['ses'])
    src_files = glob.glob(os.path.join(src, "*"))
    copy_cmd = ["cp", "-r"] + src_files + [sourcedata_ses]
    print(f"cp -r {params['dcm_dir']}/*/{os.path.basename(path)}/{meta['ses']}/* {sourcedata_ses}")

# group by study_subjnr
grouped = defaultdict(list)
for meta_file in metas:
    meta = meta_file[0]
    key = f"{meta['study']}_{meta['subjnr']}"
    grouped[key].append(meta_file)

for key, group_data in grouped.items():
    combined_meta = group_data[0][0].copy()
    combined_meta['sessions'] = list(set(m[0]['ses'] for m in group_data))
    
    print(f"\nGrouped: subject={combined_meta['subjnr']}, sessions={', '.join(combined_meta['sessions'])}")
    print(f"Local environment: {combined_meta['version']}")
    print(f"Host directory: {os.path.join(params['bds_dir'], combined_meta['study'])}")
    print(f"subject to process: sub-{combined_meta['study']}_{combined_meta['subjnr']}")
    
    environments_dir = os.path.join(params['bds_dir'], '_ENVIRONMENTS')
    env_dir = os.path.join(environments_dir, 'bidscoin_v' + combined_meta['version'])
    activate_path = os.path.join(env_dir, 'env', 'bin', 'activate')
    
    sourcedata = os.path.join(params['bds_dir'], combined_meta['study'], 'sourcedata')
    rawdata = os.path.join(params['bds_dir'], combined_meta['study'], 'rawdata')
    sub_label = f"sub-{combined_meta['study']}_{combined_meta['subjnr']}"
    sub_dir = f"sub-{combined_meta['study']}{combined_meta['subjnr']}"
    
    cmd = f"source {activate_path} && bidscoiner {sourcedata} {rawdata} -p {sub_label}"
    print(f"[INFO] Would execute: {cmd}")
    print(f"[INFO] Would execute chown: chown -R 1002:1004 {os.path.join(rawdata, sub_dir)}")


if not args.dry_run:
    response = input("Do you want to proceed with these operations? (Y/n): ").strip().lower()
    if response != 'y':
        print("Operation cancelled by user.")
        exit()

for meta, path in metas:
    sourcedata_ses = os.path.join(params['bds_dir'], meta['study'], 'sourcedata', f"sub-{meta['study']}_{meta['subjnr']}", meta['ses'])
    rawdata = os.path.join(params['bds_dir'], meta['study'], 'rawdata')
    
    if not args.dry_run:
        os.makedirs(sourcedata_ses, exist_ok=True)
        os.makedirs(rawdata, exist_ok=True)
    
    src = os.path.join(path, meta['ses'])
    src_files = glob.glob(os.path.join(src, "*"))
    copy_cmd = ["cp", "-r"] + src_files + [sourcedata_ses]
    if not args.dry_run:
        subprocess.run(copy_cmd)

for key, group_data in grouped.items():
    combined_meta = group_data[0][0].copy()
    environments_dir = os.path.join(params['bds_dir'], '_ENVIRONMENTS')
    env_dir = os.path.join(environments_dir, 'bidscoin_v' + combined_meta['version'])
    activate_path = os.path.join(env_dir, 'env', 'bin', 'activate')
    
    sourcedata = os.path.join(params['bds_dir'], combined_meta['study'], 'sourcedata')
    rawdata = os.path.join(params['bds_dir'], combined_meta['study'], 'rawdata')
    sub_label = f"sub-{combined_meta['study']}_{combined_meta['subjnr']}"
    sub_dir = f"sub-{combined_meta['study']}{combined_meta['subjnr']}"
    
    cmd = f"source {activate_path} && bidscoiner {sourcedata} {rawdata} -p {sub_label}"
    if not args.dry_run:
        subprocess.run(cmd, shell=True)
        chown_cmd = ["chown", "-R", "1002:1004", os.path.join(rawdata, sub_dir)]
        subprocess.run(chown_cmd)

# JSON Adjustment Section
print("\nJSON adjustment starts now")
unique_studies = set(combined_meta['study'] for key, group_data in grouped.items() for combined_meta in [group_data[0][0]])

for study in unique_studies:
    rawdata_path = os.path.join(params['bds_dir'], study, 'rawdata')
    
    print(f"\nProcessing JSON files for study: {study}")
    print(f"Rawdata directory: {rawdata_path}")
    
    adjust_json_cmd = [
        "bash", "adjust_json.sh",
        "-delete",
        "-t", "AcquisitionDuration",
        "-d", rawdata_path,
        "-I", "func"
    ]
    if args.dry_run:
        adjust_json_cmd.append("--dry-run")
    
    print(f"[INFO] Would execute: {' '.join(adjust_json_cmd)}")
    
    response = input(f"Do you want to proceed with JSON adjustment for {rawdata_path}? (Y/n): ").strip().lower()
    if response != 'y':
        print(f"JSON adjustment cancelled for {rawdata_path}.")
        continue
    try:
        subprocess.run(adjust_json_cmd, check=True)
        print(f"JSON adjustment completed for {rawdata_path}")
    except subprocess.CalledProcessError as e:
        print(f"Error executing adjust_json.sh for {rawdata_path}: {e}")



# Defacing section
print("Defacing starts now")
for key, group_data in grouped.items():
    combined_meta = group_data[0][0].copy()
    combined_meta['sessions'] = list(set(m[0]['ses'] for m in group_data))
    print(f" - sub-{combined_meta['study']}{combined_meta['subjnr']} (sessions: {', '.join(combined_meta['sessions'])})")

    rawdata_path = os.path.join(params['bds_dir'], meta['study']) + '/'
    faced_dir = os.path.join(params['bds_dir'], meta['study'], 'sourcedata/faced')

    print("--- Deface Process Variables ---")
    print(f"Study: {meta['study']}")
    print(f"Sessions: {', '.join(combined_meta['sessions'])}")
    print(f"Subject Number: {meta['subjnr']}")
    print(f"Version: {meta['version']}")
    print(f"Raw Data Path: {rawdata_path}")
    print(f"BIDS Directory: {params['bds_dir']}")
    print(f"Full Subject Path: {rawdata_path}rawdata/sub-{meta['study']}{meta['subjnr']}")
    print(f"Faced Directory: {faced_dir}")
    print("--------------------------------")

if args.dry_run:
    print("[INFO] Would perform defacing for the above subjects (dry-run mode)")
else:
    response = input("Do you want to proceed with defacing? (Y/n): ").strip().lower()
    if response != 'y':
        print("Defacing cancelled by user.")
    else:
        for key, group_data in grouped.items():
            meta = group_data[0][0]
            rawdata_path = os.path.join(params['bds_dir'], meta['study']) + '/'
            faced_dir = os.path.join(params['bds_dir'], meta['study'], 'sourcedata/bidsonym/faced')

            print("Creating faced directory...")
            os.makedirs(faced_dir, exist_ok=True)
            print("Faced directory created.")

            def process_image(img_path):
                img_path = Path(img_path)
                filename = img_path.name
                print(f"Copying {filename} to faced directory...")
                dest_path = os.path.join(faced_dir, f"faced_{filename}")
                shutil.copy(img_path, dest_path)
                print(f"File copied: {dest_path}")
                print(f"Defacing file: {img_path}")
                try:
                    subprocess.run(['pydeface', str(img_path), '--outfile', str(img_path), '--force'], check=True)
                    print(f"File defaced: {img_path}")
                except subprocess.CalledProcessError as e:
                    print(f"Error defacing {img_path}: {e}")

            subject_path = os.path.join(rawdata_path, 'rawdata', f"sub-{meta['study']}{meta['subjnr']}")
            image_patterns = ['*_T1w.nii.gz', '*_T2w.nii.gz', '*_PDw.nii.gz']
            image_files = []
            print("Finding and processing T1w, T2w, and PDw images...")
            for pattern in image_patterns:
                p = glob.glob(os.path.join(subject_path, combined_meta['ses'], 'anat', pattern))
                image_files.extend(p)

            with ThreadPoolExecutor(max_workers=5) as executor:
                executor.map(process_image, image_files)

            print(f"Copying and defacing completed for subject {meta['study']}{meta['subjnr']}")
