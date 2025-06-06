# Convert BIDS into datalad 

## Overview
The script performs the following steps:

- Creates a DataLad superdataset in the specified destination directory.
- Initializes subdatasets for each subject in the BIDS dataset.
- Uses rsync to copy the BIDS data into the DataLad dataset while preserving the hierarchical structure.
- Ensures that all files are tracked and versioned by DataLad.

## Usage

Usage: bids2datalad.sh [-h] [-s src_dir] [-d dest_dir] [--skip_bids_validation]

Options:
  -h                       Show this help message
  -s src_dir               Source directory containing BIDS data
  -d dest_dir              Destination directory for DataLad datasets
  --skip_bids_validation   Skip BIDS validation

Example:
  bids2datalad.sh -s /path/to/bids_data -d /path/to/destination
  bids2datalad.sh --skip_bids_validation -s /path/to/bids_data -d /path/to/destination

# What Happens During Execution?
Superdataset Creation:

A DataLad superdataset is created in the specified destination directory.
The superdataset is initialized with Git and DataLad metadata.
Subdataset Initialization:

For each subject in the BIDS dataset (e.g., sub-01, sub-02), a corresponding subdataset is created within the superdataset.
Data Synchronization:

The script uses rsync to copy the data from the BIDS dataset into the DataLad dataset.
Files are organized hierarchically to match the BIDS structure (e.g., sub-01/anat, sub-01/func).
Versioning:

All files are tracked and versioned by DataLad, ensuring that the dataset history is preserved.

# Add Container

datalad containers-add mriqc --url /data/local/container/mriqc/mriqc_25.0.0rc0.sif 
