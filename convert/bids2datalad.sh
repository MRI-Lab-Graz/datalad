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
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        log_error "❌ No SHA-256 hash tool available (sha256sum or shasum)"
        exit 1
    fi
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
    local total_files=$(wc -l < "$temp_file")
    local current_file=0
    
    if [[ "$dry_run" == true ]]; then
        log_info "🧪 DRY RUN: Would compare $total_files files"
        rm "$temp_file"
        return 0
    fi
    
    if [[ "$parallel_hash" == true ]] && command -v xargs &> /dev/null; then
        log_info "🚀 Using parallel hash calculation for better performance"
        
        # Function for parallel processing
        compare_single_file() {
            local src_file=$1
            local src_dir=$2
            local datalad_dir=$3
            
            local datalad_file="${src_file/$src_dir/$datalad_dir}"
            
            if [[ ! -f "$datalad_file" ]]; then
                echo "MISSING:$datalad_file"
                return 1
            fi
            
            local src_hash=$(compute_hash "$src_file")
            local datalad_hash=$(compute_hash "$datalad_file")
            
            if [[ "$src_hash" != "$datalad_hash" ]]; then
                echo "MISMATCH:$src_file:$src_hash:$datalad_hash"
                return 1
            fi
            
            return 0
        }
        
        export -f compare_single_file
        export -f compute_hash
        
        # Use xargs for parallel processing
        if parallel_results=$(cat "$temp_file" | xargs -I {} -P 4 bash -c 'compare_single_file "{}" "'$src_dir'" "'$datalad_dir'"' 2>&1); then
            log_info "✅ All files are identical in the source and DataLad dataset!"
        else
            echo "$parallel_results" | while read -r line; do
                if [[ "$line" == MISSING:* ]]; then
                    log_error "❌ File missing in DataLad dataset: ${line#MISSING:}"
                    failed=$((failed+1))
                elif [[ "$line" == MISMATCH:* ]]; then
                    IFS=':' read -r _ file src_hash datalad_hash <<< "$line"
                    log_error "❌ Hash mismatch for file: $file"
                    log_error "   Source hash: $src_hash"
                    log_error "   DataLad hash: $datalad_hash"
                    failed=$((failed+1))
                fi
            done
        fi
    else
        # Sequential processing (original method)
        while read -r src_file; do
            current_file=$((current_file + 1))
            
            # Show progress every 10 files or for small datasets
            if [[ $((current_file % 10)) -eq 0 ]] || [[ $total_files -lt 50 ]]; then
                show_progress $current_file $total_files
            fi
            
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
        
        # Clear progress line
        echo ""
    fi

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

# Function to check if required dependencies are available
check_dependencies() {
    local missing_deps=()
    
    # Check for required commands
    local required_commands=("deno" "datalad" "rsync" "find" "awk")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for SHA hash tools (either sha256sum or shasum should be available)
    if ! command -v sha256sum &> /dev/null && ! command -v shasum &> /dev/null; then
        missing_deps+=("sha256sum or shasum")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "❌ Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    log_info "✅ All required dependencies are available."
}

# Function to validate arguments and paths
validate_arguments() {
    # Check that source directory path doesn't contain problematic characters
    if [[ "$src_dir" =~ [[:space:]] ]]; then
        log_error "❌ Source directory path contains spaces, which may cause issues: $src_dir"
        log_error "Consider using a path without spaces or quote all path usage."
    fi
    
    # Validate that source directory contains BIDS-like structure
    if [[ ! -d "$src_dir" ]]; then
        log_error "❌ Source directory does not exist: $src_dir"
        exit 1
    fi
    
    # Check if source directory has any sub-* directories (basic BIDS check)
    if ! ls "$src_dir"/sub-* &> /dev/null; then
        log_error "⚠️  Warning: No 'sub-*' directories found in source directory."
        log_error "This may not be a valid BIDS dataset structure."
        read -p "Do you want to continue anyway? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            log_error "❌ Aborting script."
            exit 1
        fi
    fi
}

# Function to create progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    
    printf "\r["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $((width - completed)) | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# Function to copy files with progress
copy_with_progress() {
    local src_dir=$1
    local dest_dir=$2
    
    log_info "📁 Counting files to copy..."
    local total_files=$(find "$src_dir" -type f | wc -l)
    log_info "Found $total_files files to copy"
    
    log_info "📁 Copying files from $src_dir to $dest_dir..."
    
    # Use rsync with progress if available, otherwise fallback to basic rsync
    if rsync --help | grep -q "progress" 2>/dev/null; then
        rsync -av --progress --checksum "$src_dir/" "$dest_dir/"
    else
        rsync -av --checksum "$src_dir/" "$dest_dir/"
    fi
}

# Function to create backup
create_backup() {
    local dest_dir=$1
    local backup_dir="${dest_dir}_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$dest_dir" ]] && [[ "$(ls -A "$dest_dir")" ]]; then
        log_info "💾 Creating backup of existing destination: $backup_dir"
        if cp -r "$dest_dir" "$backup_dir"; then
            log_info "✅ Backup created successfully: $backup_dir"
            return 0
        else
            log_error "❌ Failed to create backup"
            return 1
        fi
    fi
    return 0
}

# Usage function
usage() {
    echo "Usage: $0 [-h] [-s src_dir] [-d dest_dir] [--skip_bids_validation] [--dry-run] [--backup] [--parallel-hash]" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Options:" | tee /dev/fd/3
    echo "  -h                       Show this help message" | tee /dev/fd/3
    echo "  -s src_dir               Source directory containing BIDS data" | tee /dev/fd/3
    echo "  -d dest_dir              Destination directory for DataLad datasets" | tee /dev/fd/3
    echo "  --skip_bids_validation   Skip BIDS validation" | tee /dev/fd/3
    echo "  --dry-run                Show what would be done without executing" | tee /dev/fd/3
    echo "  --backup                 Create backup of destination before overwriting" | tee /dev/fd/3
    echo "  --parallel-hash          Use parallel processing for hash calculation" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Example:" | tee /dev/fd/3
    echo "  $0 -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  $0 --dry-run -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  $0 --backup --skip_bids_validation -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    exit 1
}

# Initialize variables
skip_bids_validation=false
dry_run=false
create_backup_flag=false
parallel_hash=false
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
        --dry-run)
            dry_run=true
            ;;
        --backup)
            create_backup_flag=true
            ;;
        --parallel-hash)
            parallel_hash=true
            ;;
        *)
            log_error "❌ Unknown option: $1"
            usage
            ;;
    esac
    shift
done

# Check for required arguments
if [[ -z "$src_dir" || -z "$dest_root" ]]; then
    usage
fi

# Validate arguments
validate_arguments

study_name=$(basename "$(dirname "$src_dir")")

dest_dir="$dest_root/$study_name/rawdata"


# Convert relative paths to absolute paths
if [[ ! -d "$src_dir" ]]; then
    log_error "❌ Source directory does not exist: $src_dir"
    exit 1
fi

src_dir=$(cd "$src_dir" && pwd) || {
    log_error "❌ Failed to resolve absolute path for source directory: $src_dir"
    exit 1
}

if [[ -d "$dest_dir" ]]; then
    dest_dir=$(cd "$dest_dir" && pwd) || {
        log_error "❌ Failed to resolve absolute path for destination directory: $dest_dir"
        exit 1
    }
else
    log_info "Destination directory does not exist. Creating it."
    if ! mkdir -p "$dest_dir"; then
        log_error "❌ Failed to create destination directory: $dest_dir"
        exit 1
    fi
    dest_dir=$(cd "$dest_dir" && pwd) || {
        log_error "❌ Failed to resolve absolute path for destination directory: $dest_dir"
        exit 1
    }
fi

# Print the header
print_header

# Check dependencies
check_dependencies

# Show dry run mode if enabled
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN MODE ENABLED - No actual changes will be made"
fi

# Validate BIDS dataset if validation is not skipped
if [ "$skip_bids_validation" = false ]; then
    if ! validate_bids "$src_dir"; then
        log_error "❌ BIDS validation failed. Exiting script."
        exit 1
    fi
fi

# Validate arguments and paths
validate_arguments

# Check if the destination directory is empty
if [[ "$(ls -A "$dest_dir" 2>/dev/null)" ]]; then
    log_error "⚠️ Destination directory is not empty: $dest_dir"
    
    if [[ "$create_backup_flag" == true ]]; then
        if ! create_backup "$dest_dir"; then
            log_error "❌ Failed to create backup. Aborting."
            exit 1
        fi
    else
        read -p "Do you want to continue and overwrite the contents? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            log_error "❌ Aborting script."
            exit 1
        fi
    fi
    log_info "🚨 Overwriting contents in the destination directory..."
fi

# Create backup of existing destination if not empty
create_backup "$dest_dir"

# Create DataLad superdataset
log_info "📂 Creating DataLad superdataset in $dest_dir..."
if ! safe_datalad create -c text2git --force "$dest_dir"; then
    log_error "❌ Failed to create DataLad superdataset. Exiting script."
    exit 1
fi

# Save the initial commit
log_info "📝 Saving initial commit for the superdataset..."
if ! safe_datalad save -m "Initial commit" -d "$dest_dir"; then
    log_error "❌ Failed to save initial commit. Exiting script."
    exit 1
fi

# Create sub-datasets for each subject
log_info "📂 Creating sub-datasets for each subject..."
for subject_dir in "$src_dir"/sub-*; do
    if [[ -d "$subject_dir" ]]; then
        subject_name=$(basename "$subject_dir")
        log_info "📁 Creating sub-dataset for subject: $subject_name"
        if ! safe_datalad create -d "$dest_dir" "$dest_dir/$subject_name"; then
            log_error "❌ Failed to create sub-dataset for subject: $subject_name. Exiting script."
            exit 1
        fi

        # Save the sub-dataset creation in the superdataset
        if ! safe_datalad save -m "Added sub-dataset for $subject_name" -d "$dest_dir"; then
            log_error "❌ Failed to save sub-dataset creation for: $subject_name. Exiting script."
            exit 1
        fi
    fi
done

# Copy files from source to DataLad dataset
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN: Would copy files from $src_dir to $dest_dir"
else
    copy_with_progress "$src_dir" "$dest_dir"
fi

# Save all changes in the superdataset and sub-datasets
log_info "📝 Saving all changes in the superdataset and sub-datasets..."
if ! safe_datalad save -m "Copied BIDS data and created sub-datasets" -d "$dest_dir" -r; then
    log_error "❌ Failed to save changes. Exiting script."
    exit 1
fi

# Compare files in source and DataLad dataset
if ! compare_files "$src_dir" "$dest_dir"; then
    log_error "❌ File comparison failed. Some files are not identical."
    exit 1
fi

# Final message
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN COMPLETED - No actual changes were made"
    log_info "Re-run without --dry-run to execute the conversion"
else
    log_info "✅ DataLad superdataset and sub-datasets created successfully and files are verified to be identical!"
    log_info "📊 Conversion Summary:"
    log_info "   Source: $src_dir"
    log_info "   Destination: $dest_dir"
    log_info "   Study: $study_name"
    if [[ "$create_backup_flag" == true ]]; then
        log_info "   Backup created: Yes"
    fi
    log_info "   Log file: $LOGFILE"
fi
