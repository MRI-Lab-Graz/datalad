#!/usr/bin/env bash
set -euo pipefail

# Usage: ./compress_subjects.sh <input_dir> <output_dir> <local_tmp_dir> -s "<pattern>" [--delete] [--pilot]

if [ "$#" -lt 4 ]; then
    echo "❌ Usage: $0 <input_dir> <output_dir> <local_tmp_dir> -s \"<pattern>\" [--delete] [--pilot]"
    echo "   --delete: Delete original source folders after successful verification (DANGEROUS)"
    echo "   --pilot: Process only one randomly selected subject folder (safe for pipeline testing)"
    exit 1
fi

input_dir=$(realpath "$1")
output_dir=$(realpath "$2")
tmp_dir=$(realpath "$3")
shift 3

# Default pattern
subject_pattern="*_*"
delete_source=false
pilot_mode=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s)
            subject_pattern="$2"
            shift 2
            ;;
        --delete)
            delete_source=true
            shift
            ;;
        --pilot)
            pilot_mode=true
            shift
            ;;
        *)
            echo "❌ Unknown argument: $1"
            echo "Usage: $0 <input_dir> <output_dir> <local_tmp_dir> -s \"<pattern>\" [--delete] [--pilot]"
            exit 1
            ;;
    esac
done

# 1. Validate directories
for dir in "$input_dir" "$output_dir" "$tmp_dir"; do
    if [ ! -d "$dir" ]; then
        echo "❌ Directory does not exist: $dir"
        exit 1
    fi
    if [ ! -r "$dir" ]; then
        echo "❌ Directory not readable: $dir"
        exit 1
    fi
done

# Ensure output dir is writable
if [ ! -w "$output_dir" ]; then
    echo "❌ Output directory not writable: $output_dir"
    exit 1
fi

echo "🔍 Input directory: $input_dir"
echo "📂 Output directory: $output_dir"
echo "🗂 Local temp directory: $tmp_dir"
echo "🔎 Subject pattern: $subject_pattern"
echo "🗑️ Delete source after verification: $delete_source"
echo

# 2. Collect subject folders matching pattern
subjects=()
shopt -s nullglob
for d in "$input_dir"/$subject_pattern/ ; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    if [ "$d" != "$output_dir" ]; then
        subjects+=("$base")
    fi
done
shopt -u nullglob

if [ "${#subjects[@]}" -eq 0 ]; then
    echo "❌ No subject folders found in $input_dir with pattern \"$subject_pattern\""
    exit 1
fi

if [ "$pilot_mode" = true ]; then
    # Randomly select one subject
    selected_idx=$(( RANDOM % ${#subjects[@]} ))
    subjects=("${subjects[$selected_idx]}")
    echo "🚀 Pilot mode: Only processing randomly selected subject: ${subjects[0]}"
fi

echo "✅ Found ${#subjects[@]} subject folder(s):"
printf '   - %s\n' "${subjects[@]}"
echo

# 3. Process each subject
for base in "${subjects[@]}"; do
    src="$input_dir/$base"
    tmp_subject="$tmp_dir/$base"
    out_file="$output_dir/$base.tar.xz"
    hash_file="$out_file.sha256"
    verification_dir="$tmp_dir/${base}_verify"

    echo "📋 Copying $src → $tmp_subject"
    cp -a "$src" "$tmp_subject"

    echo "📦 Compressing $tmp_subject → $out_file"
    # Detect OS and tar compatibility for atime-preserve
    if tar --help | grep -q -- '--atime-preserve'; then
        tar -cJf "$out_file" --atime-preserve=system -C "$tmp_dir" "$base"
    else
        tar -cJf "$out_file" -C "$tmp_dir" "$base"
    fi

    echo "🔑 Hashing $out_file → $hash_file"
    sha256sum "$out_file" > "$hash_file"

    echo "🔍 Verifying archive integrity..."
    # Test archive can be extracted
    if ! tar -tf "$out_file" > /dev/null; then
        echo "❌ Archive verification FAILED: Cannot list contents of $out_file"
        rm -rf "$tmp_subject"
        exit 1
    fi

    # Extract archive to verify contents
    mkdir -p "$verification_dir"
    if ! tar -xJf "$out_file" -C "$verification_dir"; then
        echo "❌ Archive verification FAILED: Cannot extract $out_file"
        rm -rf "$tmp_subject" "$verification_dir"
        exit 1
    fi

    # Compare original with extracted using checksums
    echo "🔍 Comparing original vs extracted content..."
    if ! diff -r "$src" "$verification_dir/$base" > /dev/null; then
        echo "❌ Archive verification FAILED: Content differs between original and extracted"
        rm -rf "$tmp_subject" "$verification_dir"
        exit 1
    fi

    # Verify SHA-256 hash
    echo "🔍 Verifying SHA-256 checksum..."
    if ! sha256sum -c "$hash_file" > /dev/null; then
        echo "❌ Hash verification FAILED for $out_file"
        rm -rf "$tmp_subject" "$verification_dir"
        exit 1
    fi

    echo "✅ Archive verification PASSED: $out_file"
    
    # Clean up verification directory
    rm -rf "$verification_dir"
    
    # Clean up temporary copy
    echo "🧹 Cleaning up temporary copy"
    rm -rf "$tmp_subject"

    # CONDITIONAL DELETION: Only delete source if --delete flag is set
    if [ "$delete_source" = true ]; then
        echo "⚠️  Verification complete. Ready to delete original: $src"
        echo "🗑️  Deleting original source folder: $src"
        rm -rf "$src"
        echo "✅ Source folder deleted: $src"
    else
        echo "💾 Source folder preserved: $src"
        echo "💡 Use --delete flag to remove source files after verification"
    fi
    echo
done

echo "🎉 Done! All subject folders compressed, verified, and archived."
echo "📊 Summary:"
echo "   - ${#subjects[@]} subjects processed successfully"
echo "   - All archives verified with SHA-256 checksums"
echo "   - All archives tested for extractability"
if [ "$delete_source" = true ]; then
    echo "   - Original source folders DELETED after verification"
    echo ""
    echo "⚠️  IMPORTANT: Original source data has been DELETED after verification."
else
    echo "   - Original source folders PRESERVED"
    echo ""
    echo "� SAFE: Original source data has been PRESERVED."
    echo "💡 Use --delete flag if you want to remove source files after archiving."
fi
echo "📦 All data archived with SHA-256 verification in: $output_dir"