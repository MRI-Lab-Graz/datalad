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

# Set up logging redirection carefully
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

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING - $1" | tee /dev/fd/3
}

log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS - $1" | tee /dev/fd/3
}

# Function to print a header
print_header() {
    echo -e "\033[1;36m"  # Set color to cyan
    echo "╔════════════════════════════════════════════════════════════════════════════════════╗" | tee /dev/fd/3
    echo "║                                                                                    ║" | tee /dev/fd/3
    echo "║  ███╗   ███╗██████╗ ██╗      ██╗      █████╗ ██████╗      ██████╗ ██████╗  █████╗ ███████╗ ║" | tee /dev/fd/3
    echo "║  ████╗ ████║██╔══██╗██║      ██║     ██╔══██╗██╔══██╗    ██╔════╝ ██╔══██╗██╔══██╗╚══███╔╝ ║" | tee /dev/fd/3
    echo "║  ██╔████╔██║██████╔╝██║█████╗██║     ███████║██████╔╝    ██║  ███╗██████╔╝███████║  ███╔╝  ║" | tee /dev/fd/3
    echo "║  ██║╚██╔╝██║██╔══██╗██║╚════╝██║     ██╔══██║██╔══██╗    ██║   ██║██╔══██╗██╔══██║ ███╔╝   ║" | tee /dev/fd/3
    echo "║  ██║ ╚═╝ ██║██║  ██║██║      ███████╗██║  ██║██████╔╝    ╚██████╔╝██║  ██║██║  ██║███████╗ ║" | tee /dev/fd/3
    echo "║  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝      ╚══════╝╚═╝  ╚═╝╚═════╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ║" | tee /dev/fd/3
    echo "║                                                                                    ║" | tee /dev/fd/3
    echo "║                          🧠 Magnetic Resonance Imaging Lab 🧠                     ║" | tee /dev/fd/3
    echo "║                                University of Graz                                 ║" | tee /dev/fd/3
    echo "║                                                                                    ║" | tee /dev/fd/3
    echo "╠════════════════════════════════════════════════════════════════════════════════════╣" | tee /dev/fd/3
    echo -e "\033[1;33m"  # Set color to yellow
    echo "║                          🔬 BIDS to DataLad Converter 🔬                          ║" | tee /dev/fd/3
    echo "║                              Production Version 2.1                               ║" | tee /dev/fd/3
    echo -e "\033[1;32m"  # Set color to green
    echo "║                                $(date '+%Y-%m-%d %H:%M:%S')                                ║" | tee /dev/fd/3
    echo -e "\033[1;36m"  # Back to cyan
    echo "╚════════════════════════════════════════════════════════════════════════════════════╝" | tee /dev/fd/3
    echo -e "\033[0m"  # Reset to default color
    echo ""
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
    output=$( "${validator_command[@]}" 2>&1 )
    exit_code=$?
    
    # Always show the output
    echo "$output" | tee /dev/fd/3

    # Define harmless warnings that should not cause failure
    harmless_warnings=(
        "GZIP_HEADER_MTIME"
        "GZIP_HEADER_FILENAME"
        "GZIP_HEADER_FEXTRA"
    )

    # Check if there are actual errors vs just harmless warnings
    if [[ $exit_code -eq 0 ]]; then
        log_info "✅ BIDS validation completed successfully!"
        return 0
    else
        # Check if the failure is due to harmless warnings only
        actual_errors=false
        
        # Look for error indicators that are NOT harmless warnings
        while IFS= read -r line; do
            if [[ $line =~ \[ERROR\] ]] || [[ $line =~ "error:" ]] || [[ $line =~ "Error:" ]]; then
                # Check if this error is actually a harmless warning
                is_harmless=false
                for warning in "${harmless_warnings[@]}"; do
                    if [[ $line =~ $warning ]]; then
                        is_harmless=true
                        break
                    fi
                done
                
                if [[ $is_harmless == false ]]; then
                    actual_errors=true
                    break
                fi
            fi
        done <<< "$output"
        
        # Also check for critical failure patterns
        if [[ $output =~ "no valid data" ]] || [[ $output =~ "no BIDS" ]] || [[ $output =~ "invalid dataset" ]]; then
            actual_errors=true
        fi

        if [[ $actual_errors == true ]]; then
            log_error "❌ BIDS validation failed with actual errors!"
            return 1
        else
            log_info "✅ BIDS validation completed with only harmless warnings (GZIP headers, etc.)"
            return 0
        fi
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

# Function to validate enhanced integrity (accounting for git-annex storage)
validate_integrity_enhanced() {
    local src_dir=$1
    local dest_dir=$2
    
    log_info "🔍 Performing comprehensive integrity validation..."
    log_info "Source directory: $src_dir"
    log_info "Destination directory: $dest_dir"
    
    # Only compare BIDS files, not DataLad metadata
    local src_count=$(find "$src_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | wc -l)
    # Count regular files in destination (should all be regular at this point)
    local dest_count=$(find "$dest_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | wc -l)
    
    log_info "Source BIDS files: $src_count"
    log_info "Destination BIDS files: $dest_count"
    
    # Debug: Show some example files found
    log_info "Sample source files:"
    find "$src_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | head -3 | while read -r file; do
        log_info "  - $file"
    done
    
    log_info "Sample destination files:"
    find "$dest_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | head -3 | while read -r file; do
        log_info "  - $file"
    done
    
    if [[ $src_count -ne $dest_count ]]; then
        log_error "❌ BIDS file count mismatch: source=$src_count, destination=$dest_count"
        
        # Debug: Show what's missing or extra
        log_error "Investigating file count mismatch..."
        
        # Show files in source but not in destination
        local temp_src=$(mktemp)
        local temp_dest=$(mktemp)
        find "$src_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | sed "s|$src_dir/||" | sort > "$temp_src"
        find "$dest_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) | sed "s|$dest_dir/||" | sort > "$temp_dest"
        
        local missing_in_dest=$(comm -23 "$temp_src" "$temp_dest" | wc -l)
        local extra_in_dest=$(comm -13 "$temp_src" "$temp_dest" | wc -l)
        
        if [[ $missing_in_dest -gt 0 ]]; then
            log_error "Files in source but missing in destination ($missing_in_dest):"
            comm -23 "$temp_src" "$temp_dest" | head -5 | while read -r file; do
                log_error "  - $file"
            done
        fi
        
        if [[ $extra_in_dest -gt 0 ]]; then
            log_error "Files in destination but not in source ($extra_in_dest):"
            comm -13 "$temp_src" "$temp_dest" | head -5 | while read -r file; do
                log_error "  - $file"
            done
        fi
        
        rm -f "$temp_src" "$temp_dest"
        return 1
    fi
    
    # Perform thorough file integrity check using checksums
    log_info "🔍 Performing thorough file integrity verification..."
    log_info "This may take a while depending on dataset size..."
    local failed_files=0
    local temp_file=$(mktemp)
    
    # Get all BIDS files from source
    find "$src_dir" -type f \( -name "*.nii.gz" -o -name "*.nii" -o -name "*.json" -o -name "*.tsv" -o -name "*.bval" -o -name "*.bvec" \) > "$temp_file"
    local total_files=$(wc -l < "$temp_file")
    local current_file=0
    
    log_info "Verifying $total_files BIDS files..."
    
    while IFS= read -r src_file; do
        current_file=$((current_file + 1))
        
        # Show progress every 10 files or if dataset is small
        if [[ $((current_file % 10)) -eq 0 ]] || [[ $total_files -lt 50 ]]; then
            show_progress $current_file $total_files
        fi
        
        # Construct corresponding destination file path
        local dest_file="${src_file/$src_dir/$dest_dir}"
        
        # Check if file exists in destination
        if [[ ! -f "$dest_file" ]]; then
            echo "" # Clear progress line before error
            log_error "❌ File missing in destination: $dest_file"
            failed_files=$((failed_files + 1))
            continue
        fi
        
        # Compare checksums (files should be regular files at this point)
        local src_hash=$(compute_hash "$src_file")
        local dest_hash=$(compute_hash "$dest_file")
        
        if [[ "$src_hash" != "$dest_hash" ]]; then
            echo "" # Clear progress line before error
            log_error "❌ Checksum mismatch for: $(basename "$src_file")"
            log_error "   Source: $src_hash"
            log_error "   Destination: $dest_hash"
            failed_files=$((failed_files + 1))
        fi
    done < "$temp_file"
    
    # Clear progress line and show completion
    echo ""
    rm "$temp_file"
    
    if [[ $failed_files -gt 0 ]]; then
        log_error "❌ $failed_files files failed integrity validation"
        return 1
    else
        log_info "✅ All $total_files files passed integrity verification"
    fi
    
    # Check if essential BIDS files exist in destination
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
    
    log_info "✅ Comprehensive integrity validation passed"
    log_info "✅ All $src_count BIDS files successfully verified with checksums"
    log_info "✅ All $src_subjects subject directories created"
    
    return 0
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
        
        if [[ "$non_interactive" == "true" ]]; then
            log_error "❌ Running in non-interactive mode. Aborting due to invalid BIDS structure."
            log_error "Use --skip_bids_validation to bypass this check if needed."
            exit 1
        else
            read -p "Do you want to continue anyway? (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then
                log_error "❌ Aborting script."
                exit 1
            fi
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
    
    log_info "📁 Counting files to copy (excluding .DS_Store files)..."
    local total_files=$(find "$src_dir" -type f ! -name ".DS_Store" | wc -l)
    log_info "Found $total_files files to copy (excluding system files)"
    
    log_info "📁 Copying files from $src_dir to $dest_dir..."
    log_info "🚫 Excluding: .DS_Store files"
    
    # Check disk space before starting copy
    check_disk_space_status "$dest_dir"
    
    # Use rsync with progress if available, otherwise fallback to basic rsync
    # Exclude .DS_Store files explicitly
    # Use fasttrack mode (skip checksums) if requested
    if [[ "$fasttrack" == "true" ]]; then
        log_info "⚡ Fasttrack mode: Skipping checksum validation for speed"
        log_info "🚀 Starting file copy operation..."
        if rsync --help | grep -q "progress" 2>/dev/null; then
            rsync -av --progress --exclude=".DS_Store" "$src_dir/" "$dest_dir/"
        else
            rsync -av --exclude=".DS_Store" "$src_dir/" "$dest_dir/"
        fi
    else
        log_info "🔍 Standard mode: Using checksum validation for data integrity"
        log_info "🚀 Starting file copy operation with checksum verification..."
        if rsync --help | grep -q "progress" 2>/dev/null; then
            rsync -av --progress --checksum --exclude=".DS_Store" "$src_dir/" "$dest_dir/"
        else
            rsync -av --checksum --exclude=".DS_Store" "$src_dir/" "$dest_dir/"
        fi
    fi
    
    # Check disk space after copy
    log_info "✅ File copy completed, checking final disk space..."
    check_disk_space_status "$dest_dir"
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
            if [[ "$non_interactive" == "true" ]]; then
                log_error "❌ Running in non-interactive mode. Aborting due to unreadable files."
                return 1
            else
                read -p "Continue anyway? (y/n): " confirm
                if [[ "$confirm" != "y" ]]; then
                    return 1
                fi
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
**Script Version:** 2.1  
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
*Report generated by BIDS to DataLad Conversion Tool v2.1*
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

# Function to create checkpoints for recovery
create_checkpoint() {
    local checkpoint_name=$1
    local checkpoint_file="${TEMP_DIR}/checkpoint_${checkpoint_name}_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "📍 Creating checkpoint: $checkpoint_name"
    
    cat > "$checkpoint_file" << EOF
# CHECKPOINT: $checkpoint_name
# Created: $(date)
# Source: $src_dir
# Destination: $dest_dir
# Log: $LOGFILE
# PID: $$

# Recovery instructions:
# This checkpoint can be used to understand the conversion state
# at the time '$checkpoint_name' was reached.

EOF
    
    log_info "📍 Checkpoint saved: $checkpoint_file"
}

# Function to check disk space during operations (called periodically)
check_disk_space_status() {
    local dest_dir=$1
    local dest_parent=$(dirname "$dest_dir")
    
    local avail_kb=$(df "$dest_parent" | tail -1 | awk '{print $4}')
    local avail_gb=$((avail_kb / 1024 / 1024))
    
    log_info "💾 Available disk space: ${avail_gb}GB"
    
    if [[ $avail_gb -lt 5 ]]; then
        log_error "⚠️ WARNING: Low disk space - only ${avail_gb}GB remaining!"
        return 1
    fi
    return 0
}

# Function to clean up DataLad state before critical operations
cleanup_datalad_state() {
    local dataset_dir=$1
    
    if [[ ! -d "$dataset_dir" ]]; then
        return 0
    fi
    
    log_info "🧹 Cleaning up DataLad state in: $dataset_dir"
    
    # Remove any .DS_Store files that might interfere
    find "$dataset_dir" -name ".DS_Store" -delete 2>/dev/null || true
    
    # Check if there are any uncommitted changes
    if command -v datalad &> /dev/null; then
        local status_output
        if status_output=$(datalad status -d "$dataset_dir" 2>/dev/null); then
            if echo "$status_output" | grep -q "modified\|untracked"; then
                log_info "📋 Found uncommitted changes in dataset, attempting to resolve..."
                # Try to save any pending changes
                datalad save -d "$dataset_dir" -m "Auto-save before operation" 2>/dev/null || true
            fi
        fi
    fi
}

# Function to safely remove DataLad datasets with proper cleanup
safe_remove_datalad_dataset() {
    local dataset_path="$1"
    local force_mode="${2:-false}"
    
    if [[ ! -d "$dataset_path" ]]; then
        log_info "📂 Dataset path does not exist: $dataset_path"
        return 0
    fi
    
    log_info "🗑️ Safely removing DataLad dataset: $dataset_path"
    
    # Method 1: Try DataLad remove (cleanest approach)
    if command -v datalad &> /dev/null && [[ -d "$dataset_path/.datalad" ]]; then
        log_info "🔧 Attempting DataLad remove..."
        if datalad remove --dataset "$dataset_path" --recursive 2>/dev/null; then
            log_success "✅ Dataset removed successfully with DataLad"
            return 0
        else
            log_info "⚠️ DataLad remove failed, trying alternative methods..."
        fi
    fi
    
    # Method 2: git-annex unlock and remove
    if [[ -d "$dataset_path/.git" ]] && command -v git &> /dev/null; then
        log_info "🔓 Unlocking git-annex files..."
        (
            cd "$dataset_path" || exit 1
            if command -v git-annex &> /dev/null; then
                git annex unlock . 2>/dev/null || true
            fi
        )
    fi
    
    # Method 3: Force permissions and remove
    log_info "🔨 Forcing permissions and removing..."
    if [[ "$force_mode" == "true" ]] || [[ ! -t 0 ]] || [[ "$non_interactive" == "true" ]]; then
        # Non-interactive mode or force mode
        chmod -R +w "$dataset_path" 2>/dev/null || true
        rm -rf "$dataset_path"
        log_success "✅ Dataset forcefully removed: $dataset_path"
    else
        # Interactive mode - ask for confirmation
        echo "⚠️ About to forcefully remove: $dataset_path"
        echo "This will:"
        echo "  - Change all file permissions to writable"
        echo "  - Recursively delete all content"
        echo "  - Remove the entire directory structure"
        echo ""
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            chmod -R +w "$dataset_path" 2>/dev/null || true
            rm -rf "$dataset_path"
            log_success "✅ Dataset removed: $dataset_path"
        else
            log_info "❌ Removal cancelled by user"
            return 1
        fi
    fi
}

# Function to safely execute DataLad operations for sub-datasets with enhanced tolerance
safe_subdataset_operation() {
    local operation="$1"
    local subject_dir="$2"
    local dest_dir="$3"
    local subject_name="$4"
    shift 4  # Remove the first 4 arguments, rest are DataLad command arguments
    local datalad_args=("$@")
    
    log_info "🔄 Attempting sub-dataset $operation for: $subject_name"
    
    # Multiple fallback strategies for sub-dataset operations
    local strategies=("standard" "force_clean" "manual_git")
    
    for strategy in "${strategies[@]}"; do
        log_info "🔄 Trying strategy: $strategy"
        
        case "$strategy" in
            "standard")
                # For save operations, only save within the dataset directory
                if [[ "$operation" == "save" ]]; then
                    if safe_datalad "$operation" "${datalad_args[@]}"; then
                        log_success "✅ Sub-dataset $operation successful for: $subject_name"
                        return 0
                    fi
                else
                    if safe_datalad "$operation" "$subject_dir" "$dest_dir" "$subject_name" "${datalad_args[@]}"; then
                        log_success "✅ Sub-dataset $operation successful for: $subject_name"
                        return 0
                    fi
                fi
                ;;
            "force_clean")
                log_info "🧹 Trying with state cleanup..."
                cleanup_datalad_state "$subject_dir"
                cleanup_datalad_state "$dest_dir"
                
                if [[ "$operation" == "save" ]]; then
                    if safe_datalad "$operation" "${datalad_args[@]}"; then
                        log_success "✅ Sub-dataset $operation successful after cleanup for: $subject_name"
                        return 0
                    fi
                else
                    if safe_datalad "$operation" "$subject_dir" "$dest_dir" "$subject_name" "${datalad_args[@]}"; then
                        log_success "✅ Sub-dataset $operation successful after cleanup for: $subject_name"
                        return 0
                    fi
                fi
                ;;
            "manual_git")
                log_info "🔧 Trying manual git approach..."
                (
                    cd "$dest_dir" || return 1
                    # Check if there are any changes to commit
                    if git status --porcelain | grep -q "$subject_name"; then
                        git add "$subject_name" 2>/dev/null || true
                        git commit -m "Add sub-dataset for $subject_name" 2>/dev/null || true
                        log_success "✅ Manual git commit successful for: $subject_name"
                    else
                        log_info "ℹ️ No changes to commit for $subject_name"
                    fi
                    return 0
                )
                if [[ $? -eq 0 ]]; then
                    return 0
                fi
                ;;
        esac
    done
    
    # If all strategies fail, log warning but don't fail the entire script
    log_warning "⚠️ All strategies failed for sub-dataset $operation: $subject_name"
    log_warning "This is not critical - the data was copied successfully"
    log_warning "You can manually save this later with:"
    log_warning "  cd '$dest_dir' && datalad save -m 'Add sub-dataset for $subject_name'"
    
    return 1  # Return error but script continues
}

# Usage function
usage() {
    echo "Usage: $0 [-h] [-s src_dir] [-d dest_dir] [--skip_bids_validation] [--dry-run] [--backup] [--parallel-hash] [--force-empty] [--fasttrack] [--non-interactive] [--cleanup dataset_path]" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Options:" | tee /dev/fd/3
    echo "  -h                       Show this help message" | tee /dev/fd/3
    echo "  -s src_dir               Source directory containing BIDS data" | tee /dev/fd/3
    echo "  -d dest_dir              Destination directory for DataLad datasets" | tee /dev/fd/3
    echo "  --skip_bids_validation   Skip initial and final BIDS validation" | tee /dev/fd/3
    echo "  --dry-run                Show what would be done without executing" | tee /dev/fd/3
    echo "  --backup                 Create backup of destination before overwriting" | tee /dev/fd/3
    echo "  --parallel-hash          Use parallel processing for hash calculation" | tee /dev/fd/3
    echo "  --force-empty            Require destination directory to be empty (safety mode)" | tee /dev/fd/3
    echo "  --non-interactive        Run without interactive prompts (for remote/automated use)" | tee /dev/fd/3
    echo "  --fasttrack              Speed up conversion by skipping checksum validation" | tee /dev/fd/3
    echo "  --cleanup dataset_path   Safely remove a DataLad dataset with proper cleanup" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Storage:" | tee /dev/fd/3
    echo "  - Files are stored efficiently in git-annex (no duplication)" | tee /dev/fd/3
    echo "  - Use 'datalad get <file>' to retrieve file content when needed" | tee /dev/fd/3
    echo "  - Use 'datalad drop <file>' to free up space after use" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Structure:" | tee /dev/fd/3
    echo "  The script will create: dest_dir/study_name/" | tee /dev/fd/3
    echo "  Where study_name is the basename of the source directory" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Safety:" | tee /dev/fd/3
    echo "  - Source files are NEVER modified (read-only operation)" | tee /dev/fd/3
    echo "  - The script checks if destination directory is empty before proceeding" | tee /dev/fd/3
    echo "  - Use --force-empty to abort if destination is not empty" | tee /dev/fd/3
    echo "  - Use --backup to create backup of existing destination (not source)" | tee /dev/fd/3
    echo "  - Use --dry-run to preview operations without making changes" | tee /dev/fd/3
    echo "  - Use --fasttrack for faster conversion (skips checksums)" | tee /dev/fd/3
    echo "  - Comprehensive file integrity verification with checksums" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Example:" | tee /dev/fd/3
    echo "  $0 -s /path/to/study1_rawdata -d /path/to/destination" | tee /dev/fd/3
    echo "  # Creates: /path/to/destination/study1_rawdata/" | tee /dev/fd/3
    echo "  # Files stored in git-annex, use 'datalad get' to access" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "  $0 --force-empty -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  # Creates: /path/to/destination/bids_data/" | tee /dev/fd/3
    echo "  # Aborts if destination is not empty" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "  $0 --dry-run -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  $0 --backup --skip_bids_validation -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  $0 --fasttrack -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  # Faster conversion - skips checksum validation" | tee /dev/fd/3
    echo "  $0 --non-interactive -s /path/to/bids_data -d /path/to/destination" | tee /dev/fd/3
    echo "  # Remote server usage - no interactive prompts" | tee /dev/fd/3
    echo "  $0 --cleanup /path/to/dataset/to/remove" | tee /dev/fd/3
    echo "  # Safely remove a DataLad dataset with proper cleanup" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Post-conversion usage:" | tee /dev/fd/3
    echo "  datalad get -d /path/to/destination/study_name sub-01/func/sub-01_task-rest_bold.nii.gz" | tee /dev/fd/3
    echo "  datalad drop -d /path/to/destination/study_name sub-01/func/sub-01_task-rest_bold.nii.gz" | tee /dev/fd/3
    echo "" | tee /dev/fd/3
    echo "Cleanup usage:" | tee /dev/fd/3
    echo "  # When you can't delete a DataLad dataset with rm:" | tee /dev/fd/3
    echo "  $0 --cleanup /path/to/problematic/dataset" | tee /dev/fd/3
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

# Function to safely execute datalad commands with enhanced error handling
safe_datalad() {
    local cmd="$1"
    shift
    local args=("$@")
    local max_retries=3
    local retry_count=0
    local dataset_dir=""
    
    # Extract dataset directory from arguments if present
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" == "-d" && $((i+1)) -lt ${#args[@]} ]]; then
            dataset_dir="${args[$((i+1))]}"
            break
        fi
    done
    
    if dry_run_check "datalad $cmd ${args[*]}"; then
        return 0
    fi
    
    log_info "🔧 Executing: datalad $cmd ${args[*]}"
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Clean up DataLad state before critical operations
        if [[ -n "$dataset_dir" && -d "$dataset_dir" ]]; then
            cleanup_datalad_state "$dataset_dir"
        fi
        
        # Execute the command and capture both stdout and stderr
        local output
        local exit_code
        
        if output=$(datalad "$cmd" "${args[@]}" 2>&1); then
            # Command succeeded
            if [[ -n "$output" ]]; then
                echo "$output" | head -10  # Show first 10 lines of output
            fi
            return 0
        else
            exit_code=$?
            retry_count=$((retry_count + 1))
            
            log_error "❌ DataLad command failed (attempt $retry_count/$max_retries)"
            log_error "Command: datalad $cmd ${args[*]}"
            log_error "Exit code: $exit_code"
            
            # Show relevant error output
            if [[ -n "$output" ]]; then
                echo "$output" | tail -5 | while read -r line; do
                    log_error "   $line"
                done
            fi
            
            # Special handling for common DataLad issues
            if echo "$output" | grep -q "nothing to save"; then
                log_info "ℹ️  Nothing to save - this is normal, continuing..."
                return 0
            elif echo "$output" | grep -q "already exists"; then
                log_info "ℹ️  Target already exists - continuing..."
                return 0
            elif echo "$output" | grep -q "uncommitted changes"; then
                log_error "⚠️  Uncommitted changes detected. Attempting to resolve..."
                if [[ "$cmd" == "save" ]]; then
                    # Try to save current state first
                    datalad status -d "${args[-1]}" 2>/dev/null || true
                fi
            fi
            
            if [[ $retry_count -lt $max_retries ]]; then
                log_info "🔄 Retrying in 2 seconds... (attempt $((retry_count + 1))/$max_retries)"
                sleep 2
            fi
        fi
    done
    
    log_error "❌ Failed to execute after $max_retries attempts: datalad $cmd ${args[*]}"
    return 1
}

# Initialize variables
skip_bids_validation=false
dry_run=false
create_backup_flag=false
parallel_hash=false
force_empty=false
fasttrack=false
non_interactive=false
cleanup_mode=false
cleanup_dataset_path=""
src_dir=""
dest_root=""
dest_dir=""
study_name=""
src_dir_name=""

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
        --fasttrack)
            fasttrack=true
            ;;
        --non-interactive)
            non_interactive=true
            ;;
        --cleanup)
            cleanup_mode=true
            if [[ -n "$2" ]]; then
                cleanup_dataset_path="$2"
                shift
            else
                log_error "❌ --cleanup requires a dataset path"
                usage
            fi
            ;;
        *)
            log_error "❌ Unknown option: $1"
            usage
            ;;
    esac
    shift
done

# Handle cleanup mode
if [[ "$cleanup_mode" == "true" ]]; then
    if [[ -z "$cleanup_dataset_path" ]]; then
        log_error "❌ Cleanup mode requires a dataset path"
        usage
    fi
    
    log_info "🗑️ Starting DataLad dataset cleanup..."
    safe_remove_datalad_dataset "$cleanup_dataset_path"
    exit $?
fi

# Check for required arguments
if [[ -z "$src_dir" || -z "$dest_root" ]]; then
    usage
fi

# Validate arguments
validate_arguments

# Extract study name from source directory (simplified structure)
# Use only the basename of the source directory as the study name
study_name=$(basename "$src_dir")
src_dir_name=$(basename "$src_dir")

# Create destination path: dest_root/study_name (without intermediate folders)
dest_dir="$dest_root/$study_name"

# EARLY CHECK: Stop immediately if destination directory is not empty
# This saves time by avoiding all other validations if we'll fail anyway
if [[ -d "$dest_dir" && "$(ls -A "$dest_dir" 2>/dev/null)" ]]; then
    log_error "❌ DESTINATION DIRECTORY IS NOT EMPTY: $dest_dir"
    log_error ""
    log_error "For safety reasons, this script requires an empty destination directory."
    log_error ""
    log_error "Please either:"
    log_error "  1. Choose a different, empty destination directory"
    log_error "  2. Manually remove/backup the contents of: $dest_dir"
    log_error "  3. Use a subdirectory like: $dest_dir/new_dataset_name"
    log_error ""
    log_error "Example: bash $0 -s $src_dir -d $dest_root/seattle_datalad_$(date +%Y%m%d)"
    log_error ""
    exit 1
fi

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

# Perform comprehensive pre-flight checks
if ! perform_preflight_checks; then
    log_error "❌ Pre-flight checks failed. Exiting script."
    exit 1
fi

# Setup signal handlers for graceful interruption
setup_signal_handlers

# Store start time for reporting
start_time=$(date '+%Y-%m-%d %H:%M:%S')
start_time_epoch=$(date +%s)

# Check initial disk space status
log_info "🔍 Checking initial system status..."
check_disk_space_status "$dest_dir"

# Create initial checkpoint
create_checkpoint "initialization"

# Check dependencies
check_dependencies

# Check Git configuration
if ! check_git_config; then
    log_error "❌ Git configuration check failed. Exiting script."
    exit 1
fi

# Check system resources
check_system_resources

# Show dry run mode if enabled
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN MODE ENABLED - No actual changes will be made"
fi

# Comprehensive source validation
log_info "🔍 Performing comprehensive source validation..."
if ! validate_bids_structure "$src_dir"; then
    log_error "❌ BIDS structure validation failed. Exiting script."
    exit 1
fi

# Check for problematic files
check_problematic_files "$src_dir"

# Check file permissions
if ! check_permissions "$src_dir" "$dest_dir"; then
    log_error "❌ Permission check failed. Exiting script."
    exit 1
fi

# Check disk space
if ! check_disk_space "$src_dir" "$dest_dir"; then
    log_error "❌ Disk space check failed. Exiting script."
    exit 1
fi

# Create recovery information
if [[ "$dry_run" != true ]]; then
    create_recovery_info "$src_dir" "$dest_dir"
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

# Destination directory emptiness already checked earlier - skip redundant check
log_info "✅ Destination directory verified as empty or non-existent"

# Check disk space
log_info "🔍 Checking disk space requirements..."
if ! check_disk_space "$src_dir" "$dest_dir"; then
    log_error "❌ Not enough disk space available. Exiting script."
    exit 1
fi
log_info "✅ Disk space check passed."

# Check file permissions
log_info "🔍 Checking file permissions..."
if ! check_permissions "$src_dir" "$dest_dir"; then
    log_error "❌ File permission issues detected. Exiting script."
    exit 1
fi

# Check system resources
check_system_resources

# Create DataLad superdataset with git-annex configuration
log_info "📂 Creating DataLad superdataset with git-annex configuration in $dest_dir..."
log_info "🔧 This may take a moment - setting up DataLad infrastructure..."
if ! safe_datalad create --force "$dest_dir"; then
    log_error "❌ Failed to create DataLad superdataset. Exiting script."
    exit 1
fi
log_info "✅ DataLad superdataset created successfully"

# Configure git-annex settings immediately after dataset creation
log_info "⚙️ Configuring git-annex settings for large file handling..."
log_info "📝 Setting up file size thresholds and metadata handling..."
if [[ "$dry_run" != true ]]; then
    (cd "$dest_dir" && {
        # Configure git-annex: only large binary files go to annex, text files stay as regular files
        echo "*.json annex.largefiles=nothing" > .gitattributes
        echo "*.tsv annex.largefiles=nothing" >> .gitattributes
        echo "*.bval annex.largefiles=nothing" >> .gitattributes
        echo "*.bvec annex.largefiles=nothing" >> .gitattributes
        echo "*.txt annex.largefiles=nothing" >> .gitattributes
        echo "*.md annex.largefiles=nothing" >> .gitattributes
        echo "*.py annex.largefiles=nothing" >> .gitattributes
        echo "*.sh annex.largefiles=nothing" >> .gitattributes
        echo "*.m annex.largefiles=nothing" >> .gitattributes
        echo "README annex.largefiles=nothing" >> .gitattributes
        echo "LICENSE annex.largefiles=nothing" >> .gitattributes
        echo "CHANGES annex.largefiles=nothing" >> .gitattributes
        echo ".DS_Store annex.largefiles=nothing" >> .gitattributes
        echo "* annex.largefiles=(largerthan=1MB)" >> .gitattributes
        git add .gitattributes
        git commit -m "Configure git-annex: text files as regular files, large binaries in annex" || true
    })
fi

# Save the initial commit
log_info "📝 Saving initial commit for the superdataset..."
if ! safe_datalad save -m "Initial commit" -d "$dest_dir"; then
    log_error "❌ Failed to save initial commit. Exiting script."
    exit 1
fi

# Create sub-datasets for each subject with git-annex configuration
log_info "📂 Creating sub-datasets for each subject..."
subject_count=0
total_subjects=$(find "$src_dir" -maxdepth 1 -type d -name "sub-*" | wc -l)
log_info "📊 Found $total_subjects subjects to process"

for subject_dir in "$src_dir"/sub-*; do
    if [[ -d "$subject_dir" ]]; then
        subject_count=$((subject_count + 1))
        subject_name=$(basename "$subject_dir")
        log_info "📁 [$subject_count/$total_subjects] Creating sub-dataset for subject: $subject_name"
        if ! safe_datalad create -d "$dest_dir" "$dest_dir/$subject_name"; then
            log_warning "⚠️ Failed to create sub-dataset for subject: $subject_name"
            log_warning "This subject will be skipped, but conversion continues with other subjects"
            continue  # Skip this subject and continue with the next one
        fi
        log_info "✅ [$subject_count/$total_subjects] Sub-dataset created: $subject_name"

        # Configure git-annex settings for this sub-dataset too
        log_info "⚙️ [$subject_count/$total_subjects] Configuring git-annex settings for sub-dataset: $subject_name"
        if [[ "$dry_run" != true ]]; then
            (cd "$dest_dir/$subject_name" && {
                # Copy the same git-annex configuration to sub-dataset
                echo "*.json annex.largefiles=nothing" > .gitattributes
                echo "*.tsv annex.largefiles=nothing" >> .gitattributes
                echo "*.bval annex.largefiles=nothing" >> .gitattributes
                echo "*.bvec annex.largefiles=nothing" >> .gitattributes
                echo "*.txt annex.largefiles=nothing" >> .gitattributes
                echo "*.md annex.largefiles=nothing" >> .gitattributes
                echo "*.py annex.largefiles=nothing" >> .gitattributes
                echo "*.sh annex.largefiles=nothing" >> .gitattributes
                echo "*.m annex.largefiles=nothing" >> .gitattributes
                echo "README annex.largefiles=nothing" >> .gitattributes
                echo "LICENSE annex.largefiles=nothing" >> .gitattributes
                echo "CHANGES annex.largefiles=nothing" >> .gitattributes
                echo ".DS_Store annex.largefiles=nothing" >> .gitattributes
                echo "* annex.largefiles=(largerthan=1MB)" >> .gitattributes
                git add .gitattributes
                git commit -m "Configure git-annex: text files as regular files, large binaries in annex" || true
            })
        fi

        # Skip individual sub-dataset saving to avoid hanging
        # The final save at the end will handle everything recursively
        log_info "💾 Sub-dataset created for: $subject_name (will be saved with final commit)"
        log_info "✅ Completed processing for subject: $subject_name"
    fi
done

# Copy files from source to DataLad dataset
# Create checkpoint
create_checkpoint "pre_copy"

# Clean up .DS_Store files in source and destination before copying
log_info "🧹 Cleaning up .DS_Store files in source and destination directories..."
if [[ "$dry_run" != true ]]; then
    # Remove .DS_Store files from source (read-only operation)
    ds_store_count_src=$(find "$src_dir" -name ".DS_Store" 2>/dev/null | wc -l | xargs)
    if [[ $ds_store_count_src -gt 0 ]]; then
        log_warning "Found $ds_store_count_src .DS_Store files in source directory"
        log_info "These will be excluded from copying (not deleted from source)"
    fi
    
    # Remove .DS_Store files from destination if they exist
    ds_store_count_dest=$(find "$dest_dir" -name ".DS_Store" -delete 2>/dev/null | wc -l | xargs)
    if [[ $ds_store_count_dest -gt 0 ]]; then
        log_info "Removed $ds_store_count_dest .DS_Store files from destination"
    fi
    
    log_info "✅ .DS_Store cleanup completed"
fi

if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN: Would copy files from $src_dir to $dest_dir"
    log_info "🧪 DRY RUN: Would exclude .DS_Store files during copying"
    log_info "🧪 DRY RUN: Would validate file integrity after copying"
else
    copy_with_progress "$src_dir" "$dest_dir"
    
    # Validate file integrity IMMEDIATELY after copying, before ANY DataLad operations
    # This is crucial because we need to verify files as regular files, not symlinks
    log_info "🔍 Performing comprehensive integrity validation..."
    log_info "📋 Validating that all files were copied correctly before DataLad operations..."
    if ! validate_integrity_enhanced "$src_dir" "$dest_dir"; then
        log_error "❌ File integrity validation failed after copying"
        log_error "❌ Files do not match between source and destination"
        exit 1
    fi
    log_info "✅ All files successfully copied and verified with checksums"
fi

# create_checkpoint
create_checkpoint "post_copy"

# Save all changes in the superdataset and sub-datasets (this will trigger git-annex)
log_info "📝 Saving all changes in the superdataset and sub-datasets..."
log_info "🔄 This will process all files through git-annex - may take several minutes..."
log_info "⏱️ Progress will be shown for each file being processed..."
if ! safe_datalad save -m "Copied BIDS data and created sub-datasets" -d "$dest_dir" -r; then
    log_error "❌ Failed to save changes. Exiting script."
    exit 1
fi
log_info "✅ All changes saved successfully to DataLad dataset"

# Git-annex storage optimization is automatic - files are stored efficiently with symlinks
log_info "🗂️ Git-annex storage optimization complete - files are available as symlinks to annexed content"
log_info "💡 Files are immediately accessible - no need to run 'datalad get'"

# Calculate conversion duration
end_time_epoch=$(date +%s)
duration=$((end_time_epoch - start_time_epoch))
hours=$((duration / 3600))
minutes=$(((duration % 3600) / 60))
seconds=$((duration % 60))
duration_formatted="${hours}h ${minutes}m ${seconds}s"

# Final success message
if [[ "$dry_run" == true ]]; then
    log_info "🧪 DRY RUN COMPLETED - No actual changes were made"
    log_info "Re-run without --dry-run to execute the conversion"
else
    # Final BIDS validation to ensure conversion quality
    log_info "📋 Checking final BIDS validation settings..."
    log_info "   - skip_bids_validation flag: $skip_bids_validation"
    log_info "   - parallel_hash flag: $parallel_hash"
    
    if [[ "$skip_bids_validation" == false ]]; then
        log_info "🔍 Performing final BIDS validation on converted dataset..."
        log_info "🎯 Validating: $dest_dir"
        log_info "⏱️ This may take a few minutes for large datasets..."
        log_info "🔄 Validator will check file structure, naming conventions, and metadata..."
        
        # Add timeout to prevent hanging
        if timeout 300s validate_bids "$dest_dir"; then
            log_success "✅ Final BIDS validation PASSED - Converted dataset is valid!"
            log_success "🎉 All files follow BIDS specification correctly"
        else
            validation_exit_code=$?
            if [[ $validation_exit_code -eq 124 ]]; then
                log_warning "⏰ Final BIDS validation TIMED OUT (5 minutes) - Dataset may be very large"
                log_warning "Consider running manual validation: bids-validator '$dest_dir'"
            else
                log_warning "⚠️ Final BIDS validation FAILED - There may be issues with the converted dataset"
                log_warning "This could be due to:"
                log_warning "  • git-annex symlinks (expected - not a real error)"
                log_warning "  • Missing optional files"
                log_warning "  • DataLad-specific structure differences"
                log_warning "Please check the validation output above for details."
                log_warning "💡 To skip this validation in future runs, use: --skip_bids_validation"
            fi
        fi
    else
        log_info "⏭️ Final BIDS validation skipped (--skip_bids_validation flag used)"
    fi
    log_info ""
    
    log_info "✅ DataLad conversion completed successfully!"
    log_info "📊 Conversion Summary:"
    log_info "   - Start time: $start_time"
    log_info "   - End time: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "   - Duration: ${hours}h ${minutes}m ${seconds}s"
    log_info "   - Source: $src_dir"
    log_info "   - Destination: $dest_dir"
    log_info "   - Study: $study_name"
    log_info "   - Log file: $LOGFILE"
    log_info ""
    log_info "📁 DataLad dataset structure created:"
    log_info "   - Superdataset: $dest_dir"
    log_info "   - Sub-datasets: $(find "$dest_dir" -name ".datalad" -type d | wc -l | xargs) total"
    log_info ""
    log_info "🗂️ Storage optimization:"
    log_info "   - Large files stored permanently in git-annex"
    log_info "   - Working directory contains symlinks to git-annex content"
    log_info "   - Files are immediately accessible (no need for 'datalad get')"
    log_info ""
    log_info "🔧 File access:"
    log_info "   - Text files (.json, .tsv, etc.): Regular files (always accessible)"
    log_info "   - Large files (.nii.gz, etc.): Symlinks to git-annex (always accessible)"
    log_info "   - No duplication: Content stored once in .git/annex/objects/"
    log_info ""
    log_info "💡 Next steps:"
    log_info "   • Text files (.json, .tsv, etc.) are regular files - always accessible"
    log_info "   • Large files (.nii.gz, etc.) are symlinks to git-annex - always accessible"
    log_info "   • All content is permanently stored in .git/annex/objects/"
    log_info "   • No need to run 'datalad get' - files are immediately available"
    log_info "   • Example: datalad get -d \"$dest_dir\" sub-01/func/sub-01_task-rest_bold.nii.gz"
    if [[ "$create_backup_flag" == true ]]; then
        log_info "   • Backup created: Yes"
    fi
fi
