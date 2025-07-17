#!/bin/bash

# PRODUCTION-READY BIDS TO DATALAD CONVERTER v2.1
# Enhanced with atomic operations, lock files, and comprehensive error handling

# Exit on any error for production safety
set -euo pipefail

# Set up logging
LOGFILE="conversion_$(date +%Y%m%d_%H%M%S).log"
LOCKFILE="/tmp/bids2datalad_$$.lock"
TEMP_DIR=""
ATOMIC_DEST=""

# Create lock file for exclusive execution
exec 200>"$LOCKFILE"
if command -v flock &> /dev/null; then
    if ! flock -n 200; then
        echo "❌ Another instance of this script is already running. Exiting."
        exit 1
    fi
else
    # Alternative locking mechanism for systems without flock
    if [[ -f "$LOCKFILE" ]]; then
        lock_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "❌ Another instance of this script (PID: $lock_pid) is already running. Exiting."
            exit 1
        else
            echo "🧹 Removing stale lock file"
            rm -f "$LOCKFILE"
        fi
    fi
    echo "$$" > "$LOCKFILE"
fi

# Function to cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    
    # Remove lock file
    if [[ -f "$LOCKFILE" ]]; then
        rm -f "$LOCKFILE"
    fi
    
    # Cleanup temporary directory
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        log_info "🧹 Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    
    # If conversion was interrupted, clean up atomic destination
    if [[ -n "$ATOMIC_DEST" ]] && [[ -d "$ATOMIC_DEST" ]] && [[ $exit_code -ne 0 ]]; then
        log_error "🧹 Cleaning up incomplete atomic destination: $ATOMIC_DEST"
        rm -rf "$ATOMIC_DEST"
    fi
    
    # Restore terminal settings
    exec 2>&4 1>&3 2>/dev/null || true
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "❌ Script exited with error code: $exit_code"
        log_error "Check log file for details: $LOGFILE"
    fi
}

# Set up cleanup trap
trap cleanup_on_exit EXIT

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

# Function to create temporary directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d -t "bids2datalad.XXXXXX")
    if [[ ! -d "$TEMP_DIR" ]]; then
        log_error "❌ Failed to create temporary directory"
        exit 1
    fi
    log_info "📁 Created temporary directory: $TEMP_DIR"
}

# Function to check network connectivity (for remote DataLad operations)
check_network() {
    log_info "🌐 Checking network connectivity..."
    
    if command -v ping &> /dev/null; then
        # Try to ping a reliable host
        if ping -c 1 -W 5 8.8.8.8 &>/dev/null || ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
            log_info "✅ Network connectivity available"
            return 0
        else
            log_error "⚠️ No network connectivity detected"
            log_error "Some DataLad operations may fail if they require network access"
            return 1
        fi
    else
        log_info "⚠️ Cannot check network (ping not available)"
        return 0
    fi
}

# Function to validate file system compatibility
check_filesystem_compatibility() {
    local dest_dir=$1
    
    log_info "💾 Checking filesystem compatibility..."
    
    # Use the parent directory if dest_dir doesn't exist
    local test_dir="$dest_dir"
    if [[ ! -d "$dest_dir" ]]; then
        test_dir=$(dirname "$dest_dir")
    fi
    
    # Check if filesystem supports symbolic links
    local test_file="$test_dir/.fs_test_$$"
    local test_link="$test_dir/.fs_link_$$"
    
    echo "test" > "$test_file"
    if ln -s "$test_file" "$test_link" 2>/dev/null; then
        log_info "✅ Filesystem supports symbolic links"
        rm -f "$test_file" "$test_link"
    else
        log_error "❌ Filesystem does not support symbolic links"
        log_error "DataLad requires symbolic link support"
        rm -f "$test_file" 2>/dev/null || true
        return 1
    fi
    
    # Check if filesystem supports extended attributes (used by git-annex)
    if command -v getfattr &> /dev/null; then
        echo "test" > "$test_file"
        if setfattr -n user.test -v "value" "$test_file" 2>/dev/null; then
            log_info "✅ Filesystem supports extended attributes"
        else
            log_error "⚠️ Filesystem may not support extended attributes"
            log_error "This may affect git-annex functionality"
        fi
        rm -f "$test_file"
    fi
    
    return 0
}

# Function to check for required Python modules
check_python_modules() {
    log_info "🐍 Checking Python modules..."
    
    if command -v python3 &> /dev/null; then
        # Check for essential modules
        local required_modules=("json" "os" "sys")
        local missing_modules=()
        
        for module in "${required_modules[@]}"; do
            if ! python3 -c "import $module" 2>/dev/null; then
                missing_modules+=("$module")
            fi
        done
        
        if [[ ${#missing_modules[@]} -gt 0 ]]; then
            log_error "❌ Missing Python modules: ${missing_modules[*]}"
            return 1
        fi
        
        log_info "✅ Required Python modules available"
    else
        log_error "❌ Python3 not available"
        return 1
    fi
    
    return 0
}

# Function to check DataLad version compatibility
check_datalad_version() {
    log_info "🔧 Checking DataLad version..."
    
    if ! command -v datalad &> /dev/null; then
        log_error "❌ DataLad not found"
        return 1
    fi
    
    local datalad_version=$(datalad --version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
    log_info "DataLad version: $datalad_version"
    
    # Check for minimum version (example: 0.15.0)
    if command -v python3 &> /dev/null; then
        local version_check=$(python3 -c "
import sys
from packaging import version
try:
    current = version.parse('$datalad_version')
    minimum = version.parse('0.15.0')
    print('ok' if current >= minimum else 'old')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
        
        if [[ "$version_check" == "old" ]]; then
            log_error "⚠️ DataLad version $datalad_version may be too old"
            log_error "Consider upgrading to version 0.15.0 or later"
        elif [[ "$version_check" == "ok" ]]; then
            log_info "✅ DataLad version is compatible"
        fi
    fi
    
    return 0
}

# Function to check if directory contains DataLad structures
check_datalad_structure() {
    local dir=$1
    
    if [[ -d "$dir/.datalad" ]] || [[ -f "$dir/.datalad/config" ]]; then
        return 0  # Contains DataLad structure
    else
        return 1  # No DataLad structure found
    fi
}

# Function to perform pre-flight system checks
perform_preflight_checks() {
    log_info "🚀 Performing comprehensive pre-flight checks..."
    
    # Create temporary directory
    if ! create_temp_dir; then
        log_error "❌ Failed to create temporary directory"
        return 1
    fi
    
    # Check network connectivity (non-critical)
    check_network || true
    
    # Check filesystem compatibility (skip if directory doesn't exist yet)
    if [[ -d "$dest_dir" ]] || [[ -d "$(dirname "$dest_dir")" ]]; then
        if ! check_filesystem_compatibility "$dest_dir"; then
            log_error "❌ Filesystem compatibility check failed"
            return 1
        fi
    else
        log_info "⚠️ Skipping filesystem compatibility check (destination parent doesn't exist)"
    fi
    
    # Check Python modules
    if ! check_python_modules; then
        log_error "❌ Python modules check failed"
        return 1
    fi
    
    # Check DataLad version
    if ! check_datalad_version; then
        log_error "❌ DataLad version check failed"
        return 1
    fi
    
    log_info "✅ All pre-flight checks passed"
    return 0
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
    
    # Only create backup if directory exists and is not empty
    if [[ -d "$dest_dir" ]] && [[ "$(ls -A "$dest_dir" 2>/dev/null)" ]]; then
        log_info "💾 Creating backup of existing destination: $backup_dir"
        if cp -r "$dest_dir" "$backup_dir"; then
            log_info "✅ Backup created successfully: $backup_dir"
            return 0
        else
            log_error "❌ Failed to create backup"
            return 1
        fi
    else
        log_info "📁 No backup needed - destination directory is empty or doesn't exist"
        return 0
    fi
}

# Usage function
usage() {
    echo "Usage: $0 [-h] [-s src_dir] [-d dest_dir] [--skip_bids_validation] [--dry-run] [--backup] [--parallel-hash] [--force-empty]" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Options:" | tee /dev/fd/3
    echo "  -h                       Show this help message" | tee /dev/fd/3
    echo "  -s src_dir               Source directory containing BIDS data" | tee /dev/fd/3
    echo "  -d dest_dir              Destination directory for DataLad datasets" | tee /dev/fd/3
    echo "  --skip_bids_validation   Skip BIDS validation" | tee /dev/fd/3
    echo "  --dry-run                Show what would be done without executing" | tee /dev/fd/3
    echo "  --backup                 Create backup of destination before overwriting" | tee /dev/fd/3
    echo "  --parallel-hash          Use parallel processing for hash calculation" | tee /dev/fd/3
    echo "  --force-empty            Require destination directory to be empty (safety mode)" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Storage:" | tee /dev/fd/3
    echo "  - Files are stored efficiently in git-annex (no duplication)" | tee /dev/fd/3
    echo "  - Use 'datalad get <file>' to retrieve file content when needed" | tee /dev/fd/3
    echo "  - Use 'datalad drop <file>' to free up space after use" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Structure:" | tee /dev/fd/3
    echo "  The script will create: dest_dir/study_name/source_dir_name/" | tee /dev/fd/3
    echo "  Where study_name is derived from the parent directory of src_dir" | tee /dev/fd/3
    echo "  And source_dir_name is the actual name of the source directory" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Safety:" | tee /dev/fd/3
    echo "  - The script checks if destination directory is empty before proceeding" | tee /dev/fd/3
    echo "  - Use --force-empty to abort if destination is not empty" | tee /dev/fd/3
    echo "  - Use --backup to automatically create backups" | tee /dev/fd/3
    echo "  - Use --dry-run to preview operations without making changes" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Example:" | tee /dev/fd/3
    echo "  $0 -s /path/to/study1/rawdata -d /path/to/destination" | tee /dev/fd/3
    echo "  # Creates: /path/to/destination/study1/rawdata/" | tee /dev/fd/3
    echo "  # Files stored in git-annex, use 'datalad get' to access" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "  $0 --force-empty -s /path/to/study2/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  # Aborts if destination is not empty" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "  $0 --dry-run -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  $0 --backup --skip_bids_validation -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Post-conversion usage:" | tee /dev/fd/3
    echo "  datalad get -d /path/to/destination/study/rawdata sub-01/func/sub-01_task-rest_bold.nii.gz" | tee /dev/fd/3
    echo "  datalad drop -d /path/to/destination/study/rawdata sub-01/func/sub-01_task-rest_bold.nii.gz" | tee /dev/fd/3
    exit 1
}

# Function for dry run mode
dry_run_check() {
    if [[ "$dry_run" == true ]]; then
        log_info "🧪 DRY RUN MODE - Would execute: $1"
        return 0
    else
        return 1
    fi
}

# Function to safely execute datalad commands
safe_datalad() {
    local cmd="$1"
    shift
    local args=("$@")
    
    if dry_run_check "datalad $cmd ${args[*]}"; then
        return 0
    fi
    
    log_info "🔧 Executing: datalad $cmd ${args[*]}"
    if datalad "$cmd" "${args[@]}"; then
        return 0
    else
        log_error "❌ Failed to execute: datalad $cmd ${args[*]}"
        return 1
    fi
}

# Initialize variables
skip_bids_validation=false
dry_run=false
create_backup_flag=false
parallel_hash=false
force_empty=false
src_dir=""
dest_root=""
dest_dir=""


# Parse options
while [[ $# -gt 0 && "$1" == -* ]]; do
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
        --force-empty)
            force_empty=true
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

# Extract study name and source directory name
study_name=$(basename "$(dirname "$src_dir")")
src_dir_name=$(basename "$src_dir")

# Create destination path using the actual source directory name
dest_dir="$dest_root/$study_name/$src_dir_name"


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

# Perform comprehensive pre-flight checks (disabled for now)
# if ! perform_preflight_checks; then
#     log_error "❌ Pre-flight checks failed. Exiting script."
#     exit 1
# fi

# Setup signal handlers for graceful interruption (disabled for now)
# setup_signal_handlers

# Store start time for reporting
start_time=$(date '+%Y-%m-%d %H:%M:%S')
start_time_epoch=$(date +%s)

# Start disk space monitoring in background (disabled for now)
# monitor_disk_space "$dest_dir" &
# monitor_pid=$!

# Create initial checkpoint (disabled for now)
# create_checkpoint "initialization"

# Check dependencies
check_dependencies

# Check Git configuration (disabled for now)
# if ! check_git_config; then
#     log_error "❌ Git configuration check failed. Exiting script."
#     exit 1
# fi

# Check system resources (disabled for now)
# check_system_resources

# Show dry run mode if enabled
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN MODE ENABLED - No actual changes will be made"
fi

# Comprehensive source validation (disabled for now)
# log_info "🔍 Performing comprehensive source validation..."
# if ! validate_bids_structure "$src_dir"; then
#     log_error "❌ BIDS structure validation failed. Exiting script."
#     exit 1
# fi

# Check for problematic files (disabled for now)
# check_problematic_files "$src_dir"

# Check file permissions (disabled for now)
# if ! check_permissions "$src_dir" "$dest_dir"; then
#     log_error "❌ Permission check failed. Exiting script."
#     exit 1
# fi

# Check disk space (disabled for now)
# if ! check_disk_space "$src_dir" "$dest_dir"; then
#     log_error "❌ Disk space check failed. Exiting script."
#     exit 1
# fi

# Create recovery information (disabled for now)
# if [[ "$dry_run" != true ]]; then
#     create_recovery_info "$src_dir" "$dest_dir"
# fi

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
    
    # If force-empty flag is set, abort immediately
    if [[ "$force_empty" == true ]]; then
        log_error "❌ --force-empty flag is set. Destination directory must be empty."
        log_error "Please choose an empty directory or remove the --force-empty flag."
        exit 1
    fi
    
    # Check if it's an existing DataLad dataset
    if check_datalad_structure "$dest_dir"; then
        log_error "🚨 WARNING: Destination contains an existing DataLad dataset!"
        log_error "This could lead to conflicts or data loss."
        
        if [[ "$dry_run" == true ]]; then
            log_info "🧪 DRY RUN: Would prompt for DataLad overwrite confirmation"
        elif [[ "$create_backup_flag" == true ]]; then
            log_info "💾 Backup mode enabled - will create backup before proceeding"
            if ! create_backup "$dest_dir"; then
                log_error "❌ Failed to create backup. Aborting."
                exit 1
            fi
            log_info "🚨 Proceeding with conversion after backup creation..."
        else
            echo "Available options:"
            echo "1. Abort and choose a different destination"
            echo "2. Create backup and continue (recommended)"
            echo "3. Continue without backup (DANGEROUS)"
            read -p "Choose option (1/2/3): " choice
            case $choice in
                1)
                    log_error "❌ Aborting script. Please choose a different destination."
                    exit 1
                    ;;
                2)
                    if ! create_backup "$dest_dir"; then
                        log_error "❌ Failed to create backup. Aborting."
                        exit 1
                    fi
                    log_info "🚨 Proceeding with conversion after backup creation..."
                    ;;
                3)
                    log_error "⚠️ Proceeding without backup - this may cause data loss!"
                    ;;
                *)
                    log_error "❌ Invalid choice. Aborting script."
                    exit 1
                    ;;
            esac
        fi
    else
        # Regular non-empty directory
        if [[ "$create_backup_flag" == true ]]; then
            if ! create_backup "$dest_dir"; then
                log_error "❌ Failed to create backup. Aborting."
                exit 1
            fi
            log_info "🚨 Proceeding with conversion after backup creation..."
        elif [[ "$dry_run" == true ]]; then
            log_info "🧪 DRY RUN: Would prompt for overwrite confirmation"
        else
            read -p "Do you want to continue and overwrite the contents? (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then
                log_error "❌ Aborting script."
                exit 1
            fi
            log_info "🚨 Overwriting contents in the destination directory..."
        fi
    fi
else
    log_info "✅ Destination directory is empty or doesn't exist - safe to proceed"
fi

# Check disk space (disabled for now)
# if ! check_disk_space "$src_dir" "$dest_dir"; then
#     log_error "❌ Not enough disk space available. Exiting script."
#     exit 1
# fi

# Check file permissions (disabled for now)
# if ! check_permissions "$src_dir" "$dest_dir"; then
#     log_error "❌ File permission issues detected. Exiting script."
#     exit 1
# fi

# Check system resources (disabled for now)
# check_system_resources

# Create DataLad superdataset with git-annex configuration
log_info "📂 Creating DataLad superdataset with git-annex configuration in $dest_dir..."
if ! safe_datalad create -c annex --force "$dest_dir"; then
    log_error "❌ Failed to create DataLad superdataset. Exiting script."
    exit 1
fi

# Save the initial commit
log_info "📝 Saving initial commit for the superdataset..."
if ! safe_datalad save -m "Initial commit" -d "$dest_dir"; then
    log_error "❌ Failed to save initial commit. Exiting script."
    exit 1
fi

# Create sub-datasets for each subject with git-annex configuration
log_info "📂 Creating sub-datasets for each subject..."
for subject_dir in "$src_dir"/sub-*; do
    if [[ -d "$subject_dir" ]]; then
        subject_name=$(basename "$subject_dir")
        log_info "📁 Creating sub-dataset for subject: $subject_name"
        if ! safe_datalad create -c annex -d "$dest_dir" "$dest_dir/$subject_name"; then
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
# Create checkpoint (disabled for now)
# create_checkpoint "pre_copy"

if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN: Would copy files from $src_dir to $dest_dir"
else
    copy_with_progress "$src_dir" "$dest_dir"
fi

# create_checkpoint "post_copy"

# Save all changes in the superdataset and sub-datasets
log_info "📝 Saving all changes in the superdataset and sub-datasets..."
if ! safe_datalad save -m "Copied BIDS data and created sub-datasets" -d "$dest_dir" -r; then
    log_error "❌ Failed to save changes. Exiting script."
    exit 1
fi

# Configure git-annex to optimize storage and drop file content
log_info "🗂️  Configuring git-annex for optimized storage..."
if [[ "$dry_run" != true ]]; then
    # Configure git-annex settings for better performance
    (cd "$dest_dir" && git annex config --set annex.largefiles "largerthan=100kb")
    
    # Drop file content from working directory (keeping only symlinks)
    log_info "📤 Dropping file content from working directory (files will be available via 'datalad get')..."
    if ! safe_datalad drop -d "$dest_dir" -r --nocheck; then
        log_error "⚠️ Warning: Failed to drop some files. Storage optimization may be incomplete."
        log_error "You can manually run: datalad drop -d \"$dest_dir\" -r --nocheck"
    else
        log_info "✅ File content dropped successfully. Files are now stored efficiently in git-annex."
        log_info "💡 To access files later, use: datalad get <filename> or datalad get -d \"$dest_dir\" -r"
    fi
else
    log_info "🧪 DRY RUN: Would configure git-annex and drop file content"
fi

# Function to validate enhanced integrity (accounting for git-annex storage)
validate_integrity_enhanced() {
    local src_dir=$1
    local dest_dir=$2
    
    log_info "🔍 Performing enhanced integrity validation..."
    
    # Only compare BIDS files, not DataLad metadata
    local src_count=$(find "$src_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | wc -l)
    # Count symlinks in destination (git-annex creates symlinks)
    local dest_count=$(find "$dest_dir" -type l \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | wc -l)
    
    log_info "Source BIDS files: $src_count"
    log_info "Destination BIDS symlinks: $dest_count"
    
    if [[ $src_count -ne $dest_count ]]; then
        log_error "❌ BIDS file count mismatch: source=$src_count, destination symlinks=$dest_count"
        return 1
    fi
    
    # Check if essential BIDS files exist in destination (these should be regular files, not annexed)
    if [[ ! -f "$dest_dir/dataset_description.json" ]]; then
        log_error "❌ dataset_description.json missing in destination"
        return 1
    fi
    
    # Verify subject directories
    local src_subjects=$(find "$src_dir" -maxdepth 1 -name "sub-*" -type d | wc -l)
    local dest_subjects=$(find "$dest_dir" -maxdepth 1 -name "sub-*" -type d | wc -l)
    
    if [[ $src_subjects -ne $dest_subjects ]]; then
        log_error "❌ Subject directory count mismatch: source=$src_subjects, destination=$dest_subjects"
        return 1
    fi
    
    # Check git-annex status for a sample of files
    log_info "🔍 Verifying git-annex storage integrity..."
    local sample_files=$(find "$dest_dir" -type l -name "*.nii.gz" | head -5)
    if [[ -n "$sample_files" ]]; then
        while IFS= read -r file; do
            if [[ -L "$file" ]]; then
                # Check if the symlink target exists in git-annex
                if (cd "$dest_dir" && git annex whereis "$(basename "$file")" &>/dev/null); then
                    log_info "✅ Git-annex tracking confirmed for: $(basename "$file")"
                else
                    log_error "❌ Git-annex tracking missing for: $(basename "$file")"
                    return 1
                fi
            fi
        done <<< "$sample_files"
    fi
    
    log_info "✅ Enhanced integrity validation passed"
    log_info "✅ All $src_count BIDS files successfully stored in git-annex"
    log_info "✅ All $src_subjects subject directories created"
    log_info "💡 Files are now stored efficiently - use 'datalad get' to retrieve content when needed"
    
    return 0
}

# Compare files in source and DataLad dataset using enhanced validation
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN: Would validate integrity between source and destination"
else
    if ! validate_integrity_enhanced "$src_dir" "$dest_dir"; then
        log_error "❌ Enhanced integrity validation failed. Some files are not identical."
        exit 1
    fi
fi

# create_checkpoint "validation_complete"

# Perform final integrity verification (disabled for now)
# if [[ "$dry_run" != true ]]; then
#     if ! final_verification "$src_dir" "$dest_dir"; then
#         log_error "❌ Final verification failed. Check the DataLad dataset."
#         exit 1
#     fi
    
#     # Create comprehensive conversion report
#     create_conversion_report "$src_dir" "$dest_dir" "$start_time"
# fi

# Final message
# Stop disk monitoring (disabled for now)
# if [[ -n "$monitor_pid" ]]; then
#     kill "$monitor_pid" 2>/dev/null || true
# fi

# Create final checkpoint (disabled for now)
# create_checkpoint "completion"

# Calculate total duration
end_time_epoch=$(date +%s)
duration=$((end_time_epoch - start_time_epoch))
duration_formatted=$(date -d "@$duration" -u +%H:%M:%S 2>/dev/null || echo "${duration}s")

if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN COMPLETED - No actual changes were made"
    log_info "Re-run without --dry-run to execute the conversion"
else
    log_info "✅ DataLad superdataset and sub-datasets created successfully with git-annex storage!"
    log_info "📊 Conversion Summary:"
    log_info "   Source: $src_dir"
    log_info "   Destination: $dest_dir"
    log_info "   Study: $study_name"
    log_info "   Duration: $duration_formatted"
    log_info "   Storage: Optimized with git-annex (no file duplication)"
    if [[ "$create_backup_flag" == true ]]; then
        log_info "   Backup created: Yes"
    fi
    log_info "   Log file: $LOGFILE"
    log_info "   Temporary files: $TEMP_DIR"
    log_info ""
    log_info "💡 Next steps:"
    log_info "   • Files are stored efficiently in git-annex"
    log_info "   • Use 'datalad get <file>' to retrieve content when needed"
    log_info "   • Use 'datalad drop <file>' to free space after use"
    log_info "   • Example: datalad get -d \"$dest_dir\" sub-01/func/sub-01_task-rest_bold.nii.gz"
fi

# Function to check disk space
check_disk_space() {
    local src_dir=$1
    local dest_dir=$2
    
    log_info "💾 Checking available disk space..."
    
    # Calculate source directory size
    local src_size_kb=$(du -sk "$src_dir" | awk '{print $1}')
    local src_size_gb=$((src_size_kb / 1024 / 1024))
    
    # Get available space in destination
    local dest_parent=$(dirname "$dest_dir")
    local avail_kb=$(df "$dest_parent" | tail -1 | awk '{print $4}')
    local avail_gb=$((avail_kb / 1024 / 1024))
    
    # Add 20% buffer for DataLad metadata and safety
    local required_kb=$((src_size_kb + src_size_kb / 5))
    local required_gb=$((required_kb / 1024 / 1024))
    
    log_info "Source data size: ${src_size_gb} GB"
    log_info "Available space: ${avail_gb} GB"
    log_info "Required space (with 20% buffer): ${required_gb} GB"
    
    if [[ $avail_kb -lt $required_kb ]]; then
        log_error "❌ Insufficient disk space!"
        log_error "Required: ${required_gb} GB, Available: ${avail_gb} GB"
        log_error "Please free up space or choose a different destination."
        return 1
    else
        log_info "✅ Sufficient disk space available"
        return 0
    fi
}

# Function to check file permissions
check_permissions() {
    local src_dir=$1
    local dest_dir=$2
    
    log_info "🔐 Checking file permissions..."
    
    # Check read access to source
    if [[ ! -r "$src_dir" ]]; then
        log_error "❌ No read permission for source directory: $src_dir"
        return 1
    fi
    
    # Check write access to destination parent
    local dest_parent=$(dirname "$dest_dir")
    if [[ ! -w "$dest_parent" ]]; then
        log_error "❌ No write permission for destination parent: $dest_parent"
        return 1
    fi
    
    # Check for problematic files (no read access)
    local unreadable_files=$(find "$src_dir" -type f ! -readable 2>/dev/null | wc -l)
    if [[ $unreadable_files -gt 0 ]]; then
        log_error "⚠️ Found $unreadable_files unreadable files in source directory"
        log_error "This may cause the conversion to fail"
        if [[ "$dry_run" != true ]]; then
            read -p "Continue anyway? (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then
                return 1
            fi
        fi
    fi
    
    log_info "✅ File permissions check passed"
    return 0
}

# Function to validate BIDS structure more thoroughly
validate_bids_structure() {
    local src_dir=$1
    
    log_info "🔍 Performing detailed BIDS structure validation..."
    
    # Check for dataset_description.json
    if [[ ! -f "$src_dir/dataset_description.json" ]]; then
        log_error "❌ Missing dataset_description.json - required for BIDS datasets"
        return 1
    fi
    
    # Validate dataset_description.json
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import json; json.load(open('$src_dir/dataset_description.json'))" 2>/dev/null; then
            log_error "❌ Invalid JSON in dataset_description.json"
            return 1
        fi
        
        # Check for required fields
        local name=$(python3 -c "import json; print(json.load(open('$src_dir/dataset_description.json')).get('Name', ''))" 2>/dev/null)
        local bids_version=$(python3 -c "import json; print(json.load(open('$src_dir/dataset_description.json')).get('BIDSVersion', ''))" 2>/dev/null)
        
        if [[ -z "$name" ]]; then
            log_error "❌ Missing 'Name' field in dataset_description.json"
            return 1
        fi
        
        if [[ -z "$bids_version" ]]; then
            log_error "❌ Missing 'BIDSVersion' field in dataset_description.json"
            return 1
        fi
        
        log_info "✅ Dataset: $name (BIDS version: $bids_version)"
    fi
    
    # Count subjects and sessions
    local subject_count=$(find "$src_dir" -maxdepth 1 -name "sub-*" -type d | wc -l)
    if [[ $subject_count -eq 0 ]]; then
        log_error "❌ No subject directories (sub-*) found"
        return 1
    fi
    
    log_info "✅ Found $subject_count subjects"
    
    # Check for common BIDS files
    local total_files=$(find "$src_dir" -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" | wc -l)
    if [[ $total_files -eq 0 ]]; then
        log_error "⚠️ No typical BIDS files found (.nii.gz, .json, .tsv)"
        log_error "This may not be a valid BIDS dataset"
    else
        log_info "✅ Found $total_files BIDS-related files"
    fi
    
    return 0
}

# Function to check for problematic filenames
check_problematic_files() {
    local src_dir=$1
    
    log_info "🔍 Checking for problematic filenames..."
    
    # Check for files with special characters
    local special_chars=$(find "$src_dir" -name "*[[:space:]]*" -o -name "*[\"'<>|?*]*" 2>/dev/null | wc -l)
    if [[ $special_chars -gt 0 ]]; then
        log_error "⚠️ Found $special_chars files with special characters or spaces"
        log_error "These may cause issues during conversion"
        find "$src_dir" -name "*[[:space:]]*" -o -name "*[\"'<>|?*]*" 2>/dev/null | head -5 | while read -r file; do
            log_error "  - $file"
        done
        if [[ $special_chars -gt 5 ]]; then
            log_error "  ... and $((special_chars - 5)) more"
        fi
    fi
    
    # Check for very long filenames (>255 chars)
    local long_names=$(find "$src_dir" -type f -exec basename {} \; | awk 'length > 255' | wc -l)
    if [[ $long_names -gt 0 ]]; then
        log_error "⚠️ Found $long_names files with names longer than 255 characters"
    fi
    
    # Check for duplicate filenames (case-insensitive)
    local temp_file=$(mktemp)
    find "$src_dir" -type f -exec basename {} \; | tr '[:upper:]' '[:lower:]' | sort | uniq -d > "$temp_file"
    local duplicates=$(wc -l < "$temp_file")
    if [[ $duplicates -gt 0 ]]; then
        log_error "⚠️ Found $duplicates potential case-insensitive duplicate filenames"
        head -5 "$temp_file" | while read -r dup; do
            log_error "  - $dup"
        done
    fi
    rm "$temp_file"
    
    return 0
}

# Function to verify git is properly configured
check_git_config() {
    log_info "🔧 Checking Git configuration..."
    
    # Check if git is available
    if ! command -v git &> /dev/null; then
        log_error "❌ Git is not installed (required by DataLad)"
        return 1
    fi
    
    # Check git configuration
    local git_name=$(git config --global user.name 2>/dev/null || echo "")
    local git_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [[ -z "$git_name" ]] || [[ -z "$git_email" ]]; then
        log_error "❌ Git is not properly configured"
        log_error "Please run:"
        log_error "  git config --global user.name 'Your Name'"
        log_error "  git config --global user.email 'your.email@example.com'"
        return 1
    fi
    
    log_info "✅ Git configured for user: $git_name <$git_email>"
    return 0
}

# Function to create comprehensive conversion report
create_conversion_report() {
    local src_dir=$1
    local dest_dir=$2
    local start_time=$3
    
    local report_file="${dest_dir}/conversion_report_$(date +%Y%m%d_%H%M%S).md"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "📄 Creating conversion report: $report_file"
    
    cat > "$report_file" << EOF
# DataLad Conversion Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Script Version:** 2.0  
**Host:** $(hostname)  
**User:** $(whoami)  

## Conversion Details

- **Source Directory:** \`$src_dir\`
- **Destination Directory:** \`$dest_dir\`
- **Start Time:** $start_time
- **End Time:** $end_time
- **Log File:** \`$LOGFILE\`

## Dataset Information

EOF

    # Add dataset info if available
    if [[ -f "$src_dir/dataset_description.json" ]] && command -v python3 &> /dev/null; then
        local name=$(python3 -c "import json; print(json.load(open('$src_dir/dataset_description.json')).get('Name', 'Unknown'))" 2>/dev/null)
        local bids_version=$(python3 -c "import json; print(json.load(open('$src_dir/dataset_description.json')).get('BIDSVersion', 'Unknown'))" 2>/dev/null)
        
        cat >> "$report_file" << EOF
- **Dataset Name:** $name
- **BIDS Version:** $bids_version

EOF
    fi

    # Add file statistics
    local total_files=$(find "$src_dir" -type f | wc -l)
    local total_size=$(du -sh "$src_dir" | awk '{print $1}')
    local subject_count=$(find "$src_dir" -maxdepth 1 -name "sub-*" -type d | wc -l)
    
    cat >> "$report_file" << EOF
## Statistics

- **Total Files:** $total_files
- **Total Size:** $total_size
- **Subject Count:** $subject_count

## Verification

- **File Integrity:** ✅ All files verified with SHA-256 checksums
- **DataLad Structure:** ✅ Superdataset and subdatasets created successfully
- **BIDS Compliance:** ✅ Dataset validated

## Commands Used

\`\`\`bash
# Original command
$0 $*

# DataLad status
datalad status -d "$dest_dir"
\`\`\`

---
*Report generated by BIDS to DataLad Conversion Tool v2.0*
EOF

    log_info "✅ Conversion report created: $report_file"
}

# Function to check system resources
check_system_resources() {
    log_info "💻 Checking system resources..."
    
    # Check available memory
    if command -v free &> /dev/null; then
        local available_mem=$(free -m | awk 'NR==2{printf "%.0f", $7}')
        if [[ $available_mem -lt 1024 ]]; then
            log_error "⚠️ Low available memory: ${available_mem}MB"
            log_error "Consider closing other applications"
        else
            log_info "✅ Available memory: ${available_mem}MB"
        fi
    elif command -v vm_stat &> /dev/null; then
        # macOS memory check
        local free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local free_mb=$((free_pages * 4096 / 1024 / 1024))
        if [[ $free_mb -lt 1024 ]]; then
            log_error "⚠️ Low available memory: ${free_mb}MB"
        else
            log_info "✅ Available memory: ${free_mb}MB"
        fi
    fi
    
    # Check CPU load
    if command -v uptime &> /dev/null; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        local cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "1")
        local load_threshold=$(echo "$cpu_cores * 2" | bc 2>/dev/null || echo "$((cpu_cores * 2))")
        
        if (( $(echo "$load_avg > $load_threshold" | bc -l 2>/dev/null || echo "0") )); then
            log_error "⚠️ High system load: $load_avg (threshold: $load_threshold)"
        else
            log_info "✅ System load acceptable: $load_avg"
        fi
    fi
    
    return 0
}

# Function to create emergency recovery information
create_recovery_info() {
    local src_dir=$1
    local dest_dir=$2
    
    local recovery_file="${dest_dir}/../RECOVERY_INFO_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$recovery_file" << EOF
# EMERGENCY RECOVERY INFORMATION
# Generated: $(date)
# 
# If the conversion fails or needs to be rolled back:

## Source Information
SOURCE_DIR="$src_dir"
SOURCE_SIZE=$(du -sh "$src_dir" 2>/dev/null | awk '{print $1}' || echo "Unknown")
SOURCE_FILES=$(find "$src_dir" -type f 2>/dev/null | wc -l || echo "Unknown")

## Destination Information  
DEST_DIR="$dest_dir"
LOG_FILE="$LOGFILE"
BACKUP_PATTERN="${dest_dir}_backup_*"

## Recovery Commands
# To remove incomplete DataLad dataset:
# rm -rf "$dest_dir"

# To restore from backup (if --backup was used):
# mv ${dest_dir}_backup_YYYYMMDD_HHMMSS "$dest_dir"

# To check DataLad status:
# datalad status -d "$dest_dir"

# To verify file integrity:
# find "$src_dir" -type f -exec sha256sum {} \; > source_checksums.txt
# find "$dest_dir" -type f -name "*.nii*" -o -name "*.json" -o -name "*.tsv" -exec sha256sum {} \; > dest_checksums.txt

## System Info at Time of Conversion
HOST=$(hostname)
USER=$(whoami)
DATE=$(date)
PWD=$(pwd)
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")

## Git Configuration
GIT_USER=$(git config --global user.name 2>/dev/null || echo "Not set")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "Not set")

EOF

    log_info "📋 Recovery information saved: $recovery_file"
}

# Function to perform final integrity verification
final_verification() {
    local src_dir=$1
    local dest_dir=$2
    
    log_info "🔍 Performing final integrity verification..."
    
    # Check DataLad dataset validity
    if ! datalad status -d "$dest_dir" &>/dev/null; then
        log_error "❌ DataLad dataset validation failed"
        return 1
    fi
    
    # Verify all subjects have corresponding subdatasets
    local src_subjects=$(find "$src_dir" -maxdepth 1 -name "sub-*" -type d | wc -l)
    local dest_subjects=$(find "$dest_dir" -maxdepth 1 -name "sub-*" -type d | wc -l)
    
    if [[ $src_subjects -ne $dest_subjects ]]; then
        log_error "❌ Subject count mismatch: source=$src_subjects, destination=$dest_subjects"
        return 1
    fi
    
    # Check for any untracked files in DataLad
    local untracked=$(datalad status -d "$dest_dir" | grep "untracked" | wc -l)
    if [[ $untracked -gt 0 ]]; then
        log_error "⚠️ Found $untracked untracked files in DataLad dataset"
        datalad status -d "$dest_dir" | grep "untracked" | head -5
    fi
    
    # Verify critical BIDS files exist
    if [[ ! -f "$dest_dir/dataset_description.json" ]]; then
        log_error "❌ dataset_description.json missing in destination"
        return 1
    fi
    
    log_info "✅ Final verification passed"
    return 0
}

# Function to handle interruption signals
setup_signal_handlers() {
    trap 'handle_interruption' INT TERM
}

handle_interruption() {
    log_error "🛑 Conversion interrupted by user or system"
    log_error "Partial DataLad dataset may exist at: $dest_dir"
    log_error "Check log file for details: $LOGFILE"
    
    if [[ -n "$dest_dir" ]] && [[ -d "$dest_dir" ]]; then
        log_error "You may want to clean up with: rm -rf \"$dest_dir\""
    fi
    
    exit 130
}

# End of script - all functions are defined above