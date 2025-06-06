#!/bin/bash

# Set up logging
LOGFILE="conversion.log"
exec 3>&1 4>&2  # Save original file descriptors for terminal output
trap 'exec 2>&4 1>&3' 0 1 2 3  # Restore original file descriptors on exit
exec 1>>"$LOGFILE" 2>&1  # Redirect all output to the log file

# Function to log and print to terminal
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - $1" | tee /dev/fd/3
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR - $1" | tee /dev/fd/3 >&2
}

# Function to print a header
print_header() {
    echo -e "\033[1;34m"  # Set color to blue
    echo "------------------------------------------------" | tee /dev/fd/3
    echo "                   MRI - LAB GRAZ" | tee /dev/fd/3
    echo "------------------------------------------------" | tee /dev/fd/3
    echo -e "\033[0m"  # Reset to default color
    echo "                        Date: $(date '+%Y-%m-%d')" | tee /dev/fd/3
    echo "                        Time: $(date '+%H:%M:%S')" | tee /dev/fd/3
    echo "---------------------------------------------------" | tee /dev/fd/3
}

# Function to validate BIDS format
validate_bids() {
    local bids_rawdata_folder=$1

    log_info "🚀 Running BIDS Validator..."

    # Construct the validation command
    validator_command=(
        "deno"
        "run"
        "-ERN"
        "jsr:@bids/validator"
        "$bids_rawdata_folder"
        "--ignoreWarnings"
        "-v"
    )

    # Run the BIDS Validator and capture output
    if output=$( "${validator_command[@]}" 2>&1 ); then
        log_info "✅ BIDS validation completed successfully!"
        echo "$output" | tee /dev/fd/3
        return 0  # Return success code
    else
        log_error "❌ BIDS validation failed!"
        echo "$output" | tee /dev/fd/3
        return 1  # Return error code
    fi
}

# Function to compute SHA-256 hash of a file
compute_hash() {
    local file=$1
    sha256sum "$file" | awk '{print $1}'
}

# Function to compare files in the source and DataLad dataset
compare_files() {
    local src_dir=$1
    local datalad_dir=$2
    local failed=0
    local temp_file=$(mktemp)

    log_info "🔍 Comparing files in $src_dir and $datalad_dir..."

    # Find all files in the source directory
    find "$src_dir" -type f > "$temp_file"
    
    while read -r src_file; do
        # Construct the corresponding file path in the DataLad dataset
        datalad_file="${src_file/$src_dir/$datalad_dir}"

        # Check if the file exists in the DataLad dataset
        if [[ ! -f "$datalad_file" ]]; then
            log_error "❌ File missing in DataLad dataset: $datalad_file"
            failed=$((failed+1))
            continue
        fi

        # Compute hashes
        src_hash=$(compute_hash "$src_file")
        datalad_hash=$(compute_hash "$datalad_file")

        # Compare hashes
        if [[ "$src_hash" != "$datalad_hash" ]]; then
            log_error "❌ Hash mismatch for file: $src_file"
            log_error "   Source hash: $src_hash"
            log_error "   DataLad hash: $datalad_hash"
            failed=$((failed+1))
        fi
    done < "$temp_file"

    # Clean up
    rm "$temp_file"

    # Check if any files failed the comparison
    if [[ $failed -eq 0 ]]; then
        log_info "✅ All files are identical in the source and DataLad dataset!"
    else
        log_error "❌ $failed files failed the comparison."
    fi

    return $failed  # Return the number of failed comparisons
}

# Usage function
usage() {
    echo "Usage: $0 [-h] [-s src_dir] [-d dest_dir] [--skip_bids_validation]" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Options:" | tee /dev/fd/3
    echo "  -h                       Show this help message" | tee /dev/fd/3
    echo "  -s src_dir               Source directory containing BIDS data" | tee /dev/fd/3
    echo "  -d dest_dir              Destination directory for DataLad datasets" | tee /dev/fd/3
    echo "  --skip_bids_validation   Skip BIDS validation" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Example:" | tee /dev/fd/3
    echo "  $0 -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  $0 --skip_bids_validation -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    exit 1
}

# Initialize variables
skip_bids_validation=false
src_dir=""
dest_root=""
dest_dir=""


# Parse options
while [[ "$1" == -* ]]; do
    case $1 in
        -h)
            usage
            ;;
        -s)
            shift
            src_dir="$1"
            ;;
        -d)
            shift
            dest_root="$1"
            ;;
        --skip_bids_validation)
            skip_bids_validation=true
            ;;
        *)
            usage
            ;;
    esac
    shift
done

# Check for required arguments
if [[ -z "$src_dir" || -z "$dest_root" ]]; then
    usage
fi

study_name=$(basename "$(dirname "$src_dir")")

dest_dir="$dest_root/$study_name/rawdata"


# Convert relative paths to absolute paths
src_dir=$(cd "$src_dir"; pwd)
if [[ -d "$dest_dir" ]]; then
    dest_dir=$(cd "$dest_dir"; pwd)
else
    log_info "Destination directory does not exist. Creating it."
    mkdir -p "$dest_dir"
    dest_dir=$(cd "$dest_dir"; pwd)
fi

# Print the header
print_header

# Validate BIDS dataset if validation is not skipped
if [ "$skip_bids_validation" = false ]; then
    if ! validate_bids "$src_dir"; then
        log_error "❌ BIDS validation failed. Exiting script."
        exit 1
    fi
fi

# Check if the destination directory is empty
if [[ "$(ls -A "$dest_dir")" ]]; then
    log_error "⚠️ Destination directory is not empty: $dest_dir"
    read -p "Do you want to continue and overwrite the contents? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        log_error "❌ Aborting script."
        exit 1
    fi
    log_info "🚨 Overwriting contents in the destination directory..."
fi

# Create DataLad superdataset
log_info "📂 Creating DataLad superdataset in $dest_dir..."
datalad create -c text2git --force "$dest_dir"
if [[ $? -ne 0 ]]; then
    log_error "❌ Failed to create DataLad superdataset. Exiting script."
    exit 1
fi

# Save the initial commit
log_info "📝 Saving initial commit for the superdataset..."
datalad save -m "Initial commit" -d "$dest_dir"
if [[ $? -ne 0 ]]; then
    log_error "❌ Failed to save initial commit. Exiting script."
    exit 1
fi

# Create sub-datasets for each subject
log_info "📂 Creating sub-datasets for each subject..."
for subject_dir in "$src_dir"/sub-*; do
    if [[ -d "$subject_dir" ]]; then
        subject_name=$(basename "$subject_dir")
        log_info "📁 Creating sub-dataset for subject: $subject_name"
        datalad create -d "$dest_dir" "$dest_dir/$subject_name"
        if [[ $? -ne 0 ]]; then
            log_error "❌ Failed to create sub-dataset for subject: $subject_name. Exiting script."
            exit 1
        fi

        # Save the sub-dataset creation in the superdataset
        datalad save -m "Added sub-dataset for $subject_name" -d "$dest_dir"
    fi
done

# Copy files from source to DataLad dataset
log_info "📁 Copying files from $src_dir to $dest_dir..."
rsync -av --checksum "$src_dir/" "$dest_dir/"

# Save all changes in the superdataset and sub-datasets
log_info "📝 Saving all changes in the superdataset and sub-datasets..."
datalad save -m "Copied BIDS data and created sub-datasets" -d "$dest_dir" -r

# Compare files in source and DataLad dataset
if ! compare_files "$src_dir" "$dest_dir"; then
    log_error "❌ File comparison failed. Some files are not identical."
    exit 1
fi

# Final message
log_info "✅ DataLad superdataset and sub-datasets created successfully and files are verified to be identical!"
