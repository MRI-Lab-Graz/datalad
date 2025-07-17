# 🧠 BIDS to DataLad Conversion Tool

[![Version](https://img.shields.io/badge/version-2.2-blue.svg)](https://github.com/MRI-Lab-Graz/datalad)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](#prerequisites)
[![Production Ready](https://img.shields.io/badge/production-ready-brightgreen.svg)](#production-ready-features)

A robust, production-ready script for converting BIDS-formatted MRI datasets into DataLad superdatasets with subject-level subdatasets. This tool ensures data integrity through comprehensive validation and verification processes while optimizing storage efficiency using git-annex.

## ✨ Features

- 🔍 **BIDS Validation** - Automatic validation using the official BIDS validator
- 📂 **Hierarchical DataLad Structure** - Creates superdatasets with subject-level subdatasets  
- 🗂️ **Git-Annex Storage Optimization** - Eliminates file duplication using git-annex
- 🔐 **Comprehensive Data Integrity** - SHA-256 checksum verification of every file
- ⚡ **Fasttrack Mode** - Skip checksum validation for faster conversions
- 🚀 **Performance Optimizations** - Parallel hash calculation and progress monitoring
- 🔍 **Real-time Transparency** - All processes run in foreground with live status updates
- 🧪 **Dry Run Mode** - Preview operations without making changes
- 💾 **Smart Backup System** - Optional backup creation for destination (not needed for source)
- 📊 **Detailed Logging** - Comprehensive logs with timestamps and progress tracking
- 🛡️ **Robust Error Handling** - Cross-platform compatibility and dependency checking
- ⚡ **Progress Tracking** - Real-time progress bars for all file operations
- 🔒 **Production Safety** - Atomic operations, lock files, and comprehensive error recovery
- 🌐 **System Validation** - Network, filesystem, and dependency checking
- 💻 **Resource Monitoring** - Disk space, memory, and CPU monitoring
- 🔄 **Atomic Operations** - Fail-safe copying with rollback capabilities
- 🧹 **Smart .DS_Store Cleanup** - Automatic exclusion of macOS system files

## 🏭 Production-Ready Features

### Enterprise-Grade Safety
- **Atomic Operations** - All-or-nothing conversions with automatic rollback
- **Lock File Management** - Prevents concurrent execution conflicts
- **Comprehensive Pre-flight Checks** - Validates all requirements before starting
- **Graceful Error Recovery** - Automatic cleanup on interruption or failure
- **Resource Monitoring** - Real-time tracking of disk space, memory, and CPU usage

### Data Integrity Assurance
- **SHA-256 Verification** - Every file is checksummed before and after conversion
- **Git-Annex Integrity Checks** - Verifies storage optimization is working correctly
- **Progress Monitoring** - Real-time progress tracking with detailed logging
- **Checkpoint System** - Resume capability with detailed progress tracking

## 🚀 Quick Start

```bash
# Basic conversion with git-annex optimization
./convert/bids2datalad.sh -s /path/to/bids_rawdata -d /path/to/datalad_destination

# Fast conversion without checksum validation (recommended for large datasets)
./convert/bids2datalad.sh --fasttrack -s /path/to/bids_rawdata -d /path/to/datalad_destination

# With all safety features enabled
./convert/bids2datalad.sh --backup --parallel-hash -s /path/to/bids_rawdata -d /path/to/datalad_destination

# Preview what would be done (dry run)
./convert/bids2datalad.sh --dry-run -s /path/to/bids_rawdata -d /path/to/datalad_destination
```

## 💾 Storage Efficiency

### Git-Annex Integration

This tool automatically configures your DataLad dataset for optimal storage:

- **No File Duplication** - Files are stored only once in git-annex, not in both working directory and .git
- **Symlink Structure** - Working directory contains symlinks to git-annex content
- **On-Demand Access** - Use `datalad get` to retrieve files when needed
- **Space Optimization** - Significantly reduces storage requirements

### Before and After

**Traditional approach:**
```text
dataset/
├── sub-01_T1w.nii.gz         # 500MB file
└── .git/annex/objects/       # 500MB duplicate
    └── [hash]/sub-01_T1w.nii.gz
```

**Our optimized approach:**
```text
dataset/
├── sub-01_T1w.nii.gz -> .git/annex/objects/[hash]  # symlink
└── .git/annex/objects/       # 500MB (only copy)
    └── [hash]/sub-01_T1w.nii.gz
```

## 📋 Prerequisites

### Required Dependencies

The script automatically checks for these dependencies:

- **[DataLad](https://www.datalad.org/)** - Data management system
- **[Deno](https://deno.land/)** - JavaScript runtime for BIDS validator
- **rsync** - File synchronization utility
- **find, awk** - Standard Unix utilities
- **SHA tools** - Either `sha256sum` (Linux) or `shasum` (macOS)

### Installation Commands

#### Ubuntu/Debian

```bash
# Install DataLad
sudo apt-get update
sudo apt-get install datalad

# Install Deno
curl -fsSL https://deno.land/x/install/install.sh | sh

# Other tools are usually pre-installed
```

#### macOS

```bash
# Install DataLad
brew install datalad

# Install Deno
curl -fsSL https://deno.land/x/install/install.sh | sh

# shasum is pre-installed on macOS
```

## 🔧 Usage

```bash
./convert/bids2datalad.sh [OPTIONS] -s SOURCE_DIR -d DESTINATION_DIR
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h` | Show help message and exit | - |
| `-s SOURCE_DIR` | **Required.** Source directory containing BIDS data | - |
| `-d DEST_DIR` | **Required.** Destination directory for DataLad datasets | - |
| `--skip_bids_validation` | Skip BIDS format validation | `false` |
| `--dry-run` | Show what would be done without executing | `false` |
| `--backup` | Create backup of destination before overwriting | `false` |
| `--parallel-hash` | Use parallel processing for hash calculation | `false` |
| `--force-empty` | Require destination directory to be empty (safety mode) | `false` |
| `--fasttrack` | Skip checksum validation for faster conversion | `false` |

### 📁 Directory Structure Requirements

Your source directory should follow BIDS structure:

```text
your-study/
└── rawdata/           ← Point -s here (can be any name)
    ├── dataset_description.json
    ├── participants.tsv
    ├── sub-01/
    │   ├── anat/
    │   └── func/
    ├── sub-02/
    │   ├── anat/
    │   └── func/
    └── ...
```

**Note:** The source directory name doesn't have to be "rawdata" - it can be any name (e.g., "bids_data", "data", etc.). The script will preserve the original directory name in the DataLad structure.

## 📖 Examples

### Basic Conversion

```bash
./convert/bids2datalad.sh -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Creates `/storage/datalad/my-study/rawdata/` with DataLad structure

### Different Source Directory Names

```bash
./convert/bids2datalad.sh -s /data/my-study/bids_data -d /storage/datalad
```

**Result:** Creates `/storage/datalad/my-study/bids_data/` with DataLad structure

### Safe Conversion with Backup

```bash
./convert/bids2datalad.sh --backup -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Creates backup before conversion if destination exists

### Fast Conversion with Fasttrack Mode

```bash
./convert/bids2datalad.sh --fasttrack -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Skips checksum validation for significantly faster processing (recommended for large datasets)

### Fast Conversion with Parallel Processing

```bash
./convert/bids2datalad.sh --parallel-hash -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Uses parallel hash calculation for faster verification

### Ultimate Speed Conversion

```bash
./convert/bids2datalad.sh --fasttrack --parallel-hash -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Combines fasttrack mode with parallel processing for maximum speed

### Preview Mode (Recommended First Run)

```bash
./convert/bids2datalad.sh --dry-run -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Shows what would be done without making changes

### Skip Validation (For Pre-validated Datasets)

```bash
./convert/bids2datalad.sh --skip_bids_validation -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Skips BIDS validation step

### Safe Mode (Force Empty Directory)

```bash
./convert/bids2datalad.sh --force-empty -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Aborts if destination directory is not empty (safest option)

### Full-Featured Conversion

```bash
./convert/bids2datalad.sh --backup --parallel-hash -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Maximum safety with backup and parallel processing

### Real-Time Progress Monitoring

All operations now provide live status updates:

```text
📁 Counting files to copy (excluding .DS_Store files)...
Found 4,494 files to copy (excluding system files)
📁 Copying files from /source to /destination...
⚡ Fasttrack mode: Skipping checksum validation for speed
🚀 Starting file copy operation...
[====================] 100% (4,494/4,494 files)
✅ File copy completed, checking final disk space...
💾 Available disk space: 142GB

📂 Creating sub-datasets for each subject...
📊 Found 24 subjects to process
📁 [1/24] Creating sub-dataset for subject: sub-01
✅ [1/24] Sub-dataset created: sub-01
⚙️ [1/24] Configuring git-annex settings for sub-dataset: sub-01
...
```

## 📊 Output Structure

Given the command:

```bash
./convert/bids2datalad.sh -s /data/study-name/rawdata -d /storage/datalad
```

The resulting DataLad structure will be:

```text
/storage/datalad/study-name/rawdata/     ← DataLad superdataset
├── .datalad/                            ← DataLad metadata
├── .git/                                ← Git repository
│   └── annex/                           ← Git-annex content storage
│       └── objects/                     ← Actual file content
├── dataset_description.json             ← BIDS metadata (regular file)
├── participants.tsv                     ← BIDS participants file (regular file)
├── sub-01/                              ← DataLad subdataset
│   ├── .datalad/                        ← Subdataset metadata
│   ├── anat/
│   │   └── sub-01_T1w.nii.gz           ← Symlink to git-annex
│   └── func/
│       └── sub-01_task-rest_bold.nii.gz ← Symlink to git-annex
├── sub-02/                              ← DataLad subdataset
│   ├── .datalad/
│   └── ...
└── conversion_YYYYMMDD_HHMMSS.log       ← Conversion log
```

**Important:** The script preserves the original source directory name. If your source is `/data/study/bids_data`, the output will be `/storage/datalad/study/bids_data/`.

## 🗂️ Working with Git-Annex Files

### Accessing Files

After conversion, large files are stored as symlinks. To access them:

```bash
# Get a specific file
datalad get sub-01/anat/sub-01_T1w.nii.gz

# Get all files in a directory
datalad get sub-01/func/

# Get all files in the dataset
datalad get -r .
```

### Freeing Space

After you're done with files, you can free up space:

```bash
# Drop a specific file
datalad drop sub-01/anat/sub-01_T1w.nii.gz

# Drop all files in a directory
datalad drop sub-01/func/

# Drop all files in the dataset
datalad drop -r .
```

### Checking File Status

```bash
# Check which files are present locally
datalad status

# Check file availability
git annex whereis sub-01/anat/sub-01_T1w.nii.gz

# List all files (both present and absent)
git annex list
```

## 🔍 Data Integrity Verification

### Comprehensive File Checking

The script performs thorough integrity verification:

1. **Pre-conversion verification** - Checks all files are copied correctly
2. **SHA-256 checksum validation** - Every file is verified with checksums
3. **Git-annex integrity check** - Verifies git-annex storage is working
4. **Progress monitoring** - Real-time progress during verification

### Verification Process

```text
🔍 Performing comprehensive integrity validation...
This may take a while depending on dataset size...
Verifying 150 BIDS files...
[====================] 100% (150/150)
✅ All 150 files passed integrity verification
🔍 Verifying git-annex storage integrity...
✅ Git-annex tracking confirmed for: sub-01_T1w.nii.gz
✅ Git-annex storage verification passed
```

## 📝 Logging and Monitoring

### Log File

All operations are logged to `conversion_YYYYMMDD_HHMMSS.log` with timestamps:

```text
2025-07-17 14:30:15 - INFO - 🚀 Running BIDS Validator...
2025-07-17 14:30:20 - INFO - ✅ BIDS validation completed successfully!
2025-07-17 14:30:21 - INFO - 📂 Creating DataLad superdataset...
2025-07-17 14:30:25 - INFO - 📁 Creating sub-dataset for subject: sub-01
2025-07-17 14:30:30 - INFO - 📁 Copying files from source to destination...
2025-07-17 14:30:45 - INFO - 🔍 Performing comprehensive integrity validation...
2025-07-17 14:30:50 - INFO - ✅ All 150 files passed integrity verification
2025-07-17 14:30:55 - INFO - 🗂️ Configuring git-annex for optimized storage...
2025-07-17 14:31:00 - INFO - ✅ File content dropped successfully
2025-07-17 14:31:05 - INFO - ✅ DataLad conversion completed successfully!
```

### Progress Monitoring

- Real-time progress bars for file operations
- File counting and processing status
- Hash verification progress (with parallel option)
- Git-annex configuration progress

### Terminal Output

The script provides color-coded output:

- 🔵 **Blue** - Headers and important information
- ✅ **Green** - Success messages
- ⚠️ **Yellow** - Warnings
- ❌ **Red** - Errors

## 🛡️ Error Handling and Safety

### Automatic Checks

- ✅ Dependency verification before execution
- ✅ Source directory validation (BIDS structure check)
- ✅ Path resolution and accessibility
- ✅ Destination directory collision detection
- ✅ DataLad structure detection in destination
- ✅ Empty directory enforcement (with `--force-empty`)

### Safety Features

- 💾 **Backup creation** - Optional automatic backups with `--backup`
- 🧪 **Dry run mode** - Preview without changes with `--dry-run`
- 🔒 **Force empty mode** - Require empty destination with `--force-empty`
- 🔍 **Interactive confirmations** - For destructive operations
- 📊 **Comprehensive logging** - Full audit trail
- 🚨 **DataLad conflict detection** - Warns about existing DataLad datasets

### Why Backup is Not Needed for Source

**Important:** You do **NOT** need to backup your source BIDS data because:

- ✅ **Read-only operation** - Source files are never modified
- ✅ **Source remains untouched** - Original BIDS dataset is completely preserved
- ✅ **Creates new dataset** - Conversion creates a new DataLad dataset elsewhere
- ✅ **Git-annex integrity** - Files are checksummed and tracked by git-annex

### When Backup is Useful

The `--backup` option is for the **destination** directory only:

- 🔄 **Re-running conversion** - Backup existing DataLad dataset before overwriting
- 🛡️ **Safety net** - Preserve previous conversion attempts
- 📁 **Destination conflicts** - Handle existing destination directories safely

### Automatic Safety Checks

- ✅ **Dependency verification** - Checks all required tools are installed
- ✅ **Source validation** - Verifies BIDS structure and accessibility
- ✅ **Path resolution** - Ensures all paths are valid and accessible
- ✅ **Destination collision** - Detects and handles existing destinations
- ✅ **File integrity** - Comprehensive SHA-256 verification
- ✅ **Git-annex validation** - Ensures storage optimization works correctly

### Data Integrity

- 🔐 **SHA-256 verification** - Every file is hash-verified before and after git-annex conversion
- 📝 **Operation logging** - Complete operation history
- 🔄 **Atomic operations** - Rollback on failure
- 🗂️ **Git-annex integrity** - Verifies git-annex storage is working correctly

## 🚀 Performance Features

### Speed Optimization Options

- **Fasttrack Mode (`--fasttrack`)** - Skip checksum validation for 2-3x faster processing
- **Parallel Processing (`--parallel-hash`)** - Use multiple CPU cores for hash calculation
- **Combined Mode** - Use both options together for maximum speed
- **Optimized rsync** - Efficient file copying with progress tracking
- **Smart .DS_Store Exclusion** - Automatic filtering of macOS system files

### Performance Comparison

| Mode | Speed | Data Integrity | Use Case |
|------|--------|----------------|----------|
| Standard | Baseline | Full SHA-256 validation | Production, critical data |
| Fasttrack | 2-3x faster | File size/timestamp validation | Large datasets, trusted sources |
| Parallel | 1.5-2x faster | Full SHA-256 validation | CPU-bound operations |
| Combined | 3-4x faster | File size/timestamp validation | Large datasets, time-critical |

### Real-time Monitoring

All processes now run transparently in the foreground with live status updates:

- **File counting and progress** - See exactly what's being processed
- **Disk space monitoring** - Real-time available space tracking  
- **Subject-by-subject progress** - Track sub-dataset creation ([1/24], [2/24], etc.)
- **DataLad operation visibility** - See every git-annex and DataLad command
- **Error detection** - Immediate feedback when issues occur

### Resource Management

- **Memory efficient** - Streams large files without loading into memory
- **Disk space aware** - Checks available space before operations
- **Process monitoring** - Graceful handling of interruptions
- **Git-annex optimization** - Eliminates storage duplication

## 🐛 Troubleshooting

### Common Issues

#### Missing Dependencies

```bash
❌ Missing required dependencies: deno datalad
```

**Solution:** Install missing dependencies using your package manager

#### Permission Issues

```bash
❌ Failed to create destination directory: /path/to/dest
```

**Solution:** Check write permissions or run with appropriate privileges

#### BIDS Validation Failure

```bash
❌ BIDS validation failed!
```

**Solution:** Fix BIDS structure or use `--skip_bids_validation` if false positive

#### Hash Mismatch

```bash
❌ Hash mismatch for file: /path/to/file
```

**Solution:** Check source file integrity and re-run conversion

#### Git-Annex Issues

```bash
❌ Git-annex tracking missing for: filename
```

**Solution:** Check git-annex installation and repository integrity

### Git-Annex File Access Issues

If you can't access files after conversion:

```bash
# Check if files are present
datalad status

# Get missing files
datalad get <filename>

# Check git-annex status
git annex whereis <filename>
```

### Debug Mode

For detailed debugging, check the log file:

```bash
tail -f conversion_$(date +%Y%m%d)_*.log
```

## 🔄 Migration from Previous Versions

If you're upgrading from an earlier version:

1. **New git-annex optimization** - Files are now stored efficiently
2. **Enhanced integrity checking** - More thorough file verification
3. **Improved error handling** - Better error messages and recovery
4. **Enhanced logging** - More detailed operation logs
5. **Performance improvements** - Faster execution with parallel options

### Post-Conversion File Access

After conversion, remember to use `datalad get` to access files:

```bash
# Old way (files were always present)
cat sub-01/anat/sub-01_T1w.nii.gz

# New way (get files first)
datalad get sub-01/anat/sub-01_T1w.nii.gz
cat sub-01/anat/sub-01_T1w.nii.gz
```

## 🆕 Recent Updates

### Version 2.2 Changes (Enhanced Transparency & Speed)

- **⚡ Fasttrack Mode:** New `--fasttrack` option skips checksum validation for 2-3x faster conversions
- **🔍 Real-time Transparency:** All processes now run in foreground with live status updates
- **📊 Enhanced Progress Tracking:** Subject-by-subject progress indicators and detailed status messages
- **🧹 Improved .DS_Store Handling:** Comprehensive cleanup and exclusion of macOS system files
- **💾 Disk Space Monitoring:** Real-time available space tracking throughout conversion
- **🛠️ Logging Improvements:** Added missing `log_warning` and `log_success` functions
- **🔄 Process Visibility:** See every DataLad and git-annex operation as it happens
- **⏱️ Time Estimation:** Better progress indication with detailed operation descriptions
- **🚀 Performance Analysis:** Speed comparison table and optimization recommendations
- **🔧 Bug Fixes:** Fixed critical script abort issues and improved error handling

### Version 2.1 Changes (Production-Ready)

- **🗂️ Git-Annex Storage Optimization:** Eliminates file duplication using git-annex
- **🔐 Comprehensive Integrity Verification:** SHA-256 checksum validation of every file
- **🔒 Production Safety:** Added atomic operations, lock files, and comprehensive error recovery
- **🌐 System Validation:** Network connectivity, filesystem compatibility, and dependency checking
- **📋 Checkpoint System:** Resume capability with detailed progress tracking and recovery
- **💻 Resource Monitoring:** Real-time disk space, memory, and CPU monitoring
- **🔄 Atomic Operations:** Fail-safe copying with automatic rollback on failures
- **⚡ Enhanced Performance:** Improved parallel processing and progress estimation
- **🛡️ Advanced Error Handling:** Comprehensive pre-flight checks and validation
- **📊 Detailed Reporting:** Enhanced logging with duration tracking and system information

### Version 2.0 Changes

- **Fixed rawdata assumption:** Script now preserves original source directory name instead of hardcoding "rawdata"
- **Timestamped log files:** Log files now include timestamp in filename (e.g., `conversion_20250710_194530.log`)
- **Missing function fix:** Added missing `safe_datalad` and `dry_run_check` functions
- **Enhanced safety checks:** Added `--force-empty` option and DataLad structure detection
- **Improved destination handling:** Better validation and backup options for non-empty directories
- **Interactive safety prompts:** Multiple options when DataLad datasets are detected in destination
- **Improved error handling:** Better error messages and debugging information
- **Enhanced documentation:** Updated examples and usage instructions

### Breaking Changes

- **Output path structure:** The destination path now uses the actual source directory name instead of always using "rawdata"
- **Log file names:** Log files now have timestamps in the filename
- **File access:** Large files are now stored as git-annex symlinks, requiring `datalad get` to access
- **Process transparency:** All operations now run in foreground - no background processes
- **Fasttrack mode:** New speed optimization changes verification behavior

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Setup

```bash
git clone https://github.com/yourusername/bids2datalad.git
cd bids2datalad
chmod +x convert/bids2datalad.sh
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [BIDS Standard](https://bids.neuroimaging.io/) - Brain Imaging Data Structure
- [DataLad](https://www.datalad.org/) - Data management and publication platform
- [Git-Annex](https://git-annex.branchable.com/) - Managing files with git, without checking their contents in
- [BIDS Validator](https://github.com/bids-standard/bids-validator) - Official BIDS validation tool

## 📞 Support

- 🐛 **Bug Reports:** [Open an issue](https://github.com/yourusername/bids2datalad/issues)
- 💡 **Feature Requests:** [Start a discussion](https://github.com/yourusername/bids2datalad/discussions)
- 🧠 **BIDS Questions:** [Post on NeuroStars](https://neurostars.org/tags/bids)
- 📧 **Email:** [your.email@institution.edu](mailto:your.email@institution.edu)

---

## Made with ❤️ by the MRI Lab Graz
