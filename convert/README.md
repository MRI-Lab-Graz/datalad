# 🧠 BIDS to DataLad Conversion Tool

[![Version](https://img.shields.io/badge/version-2.0-blue.svg)](https://github.com/yourusername/bids2datalad)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](#required-dependencies)

A robust and feature-rich script for converting BIDS-formatted MRI datasets into DataLad superdatasets with subject-level subdatasets. This tool ensures data integrity through comprehensive validation and verification processes.

## ✨ Features

- 🔍 **BIDS Validation** - Automatic validation using the official BIDS validator
- 📂 **Hierarchical DataLad Structure** - Creates superdatasets with subject-level subdatasets
- 🔐 **Data Integrity Verification** - SHA-256 checksum comparison between source and destination
- 🚀 **Performance Optimizations** - Parallel hash calculation and progress monitoring
- 🧪 **Dry Run Mode** - Preview operations without making changes
- 💾 **Automatic Backups** - Optional backup creation before overwriting
- 📊 **Comprehensive Logging** - Detailed logs with timestamps and progress tracking
- 🛡️ **Robust Error Handling** - Cross-platform compatibility and dependency checking
- ⚡ **Progress Tracking** - Real-time progress bars for file operations
- 🔒 **Production Safety** - Atomic operations, lock files, and comprehensive error recovery
- 🌐 **System Validation** - Network, filesystem, and dependency checking
- 📋 **Checkpoint System** - Resume capability with detailed progress tracking
- 💻 **Resource Monitoring** - Disk space, memory, and CPU monitoring
- 🔄 **Atomic Operations** - Fail-safe copying with rollback capabilities

## 🚀 Quick Start

```bash
# Basic conversion
./bids2datalad.sh -s /path/to/bids_rawdata -d /path/to/datalad_destination

# With all safety features enabled
./bids2datalad.sh --backup --parallel-hash -s /path/to/bids_rawdata -d /path/to/datalad_destination

# Preview what would be done (dry run)
./bids2datalad.sh --dry-run -s /path/to/bids_rawdata -d /path/to/datalad_destination
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
./bids2datalad.sh [OPTIONS] -s SOURCE_DIR -d DESTINATION_DIR
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
./bids2datalad.sh -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Creates `/storage/datalad/my-study/rawdata/` with DataLad structure

### Different Source Directory Names

```bash
./bids2datalad.sh -s /data/my-study/bids_data -d /storage/datalad
```

**Result:** Creates `/storage/datalad/my-study/bids_data/` with DataLad structure

### Safe Conversion with Backup

```bash
./bids2datalad.sh --backup -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Creates backup before conversion if destination exists

### Fast Conversion with Parallel Processing

```bash
./bids2datalad.sh --parallel-hash -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Uses parallel hash calculation for faster verification

### Preview Mode (Recommended First Run)

```bash
./bids2datalad.sh --dry-run -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Shows what would be done without making changes

### Skip Validation (For Pre-validated Datasets)

```bash
./bids2datalad.sh --skip_bids_validation -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Skips BIDS validation step

### Safe Mode (Force Empty Directory)

```bash
./bids2datalad.sh --force-empty -s /data/my-study/rawdata -d /storage/datalad
```

**Result:** Aborts if destination directory is not empty (safest option)

### Full-Featured Conversion

```bash
./bids2datalad.sh --backup --parallel-hash -s /data/my-study/rawdata -d /storage/datalad
```

## 📊 Output Structure

Given the command:

```bash
./bids2datalad.sh -s /data/study-name/rawdata -d /storage/datalad
```

The resulting DataLad structure will be:

```text
/storage/datalad/study-name/rawdata/     ← DataLad superdataset
├── .datalad/                            ← DataLad metadata
├── dataset_description.json             ← BIDS metadata
├── participants.tsv                     ← BIDS participants file
├── sub-01/                              ← DataLad subdataset
│   ├── .datalad/                        ← Subdataset metadata
│   ├── anat/
│   │   └── sub-01_T1w.nii.gz
│   └── func/
│       └── sub-01_task-rest_bold.nii.gz
├── sub-02/                              ← DataLad subdataset
│   ├── .datalad/
│   └── ...
└── conversion_20250710_194530.log       ← Conversion log with timestamp
```

**Important:** The script preserves the original source directory name. If your source is `/data/study/bids_data`, the output will be `/storage/datalad/study/bids_data/`.

## 📝 Logging and Monitoring

### Log File

All operations are logged to `conversion_YYYYMMDD_HHMMSS.log` with timestamps:

```text
2025-07-10 19:46:15 - INFO - 🚀 Running BIDS Validator...
2025-07-10 19:46:20 - INFO - ✅ BIDS validation completed successfully!
2025-07-10 19:46:21 - INFO - 📂 Creating DataLad superdataset...
2025-07-10 19:46:25 - INFO - 📁 Creating sub-dataset for subject: sub-01
2025-07-10 19:46:30 - INFO - 📁 Copying files from source to destination...
2025-07-10 19:46:45 - INFO - ✅ All files are identical in source and DataLad dataset!
```

### Progress Monitoring

- Real-time progress bars for file operations
- File counting and processing status
- Hash verification progress (with parallel option)

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

### Data Integrity

- 🔐 **SHA-256 verification** - Every file is hash-verified
- 📝 **Operation logging** - Complete operation history
- 🔄 **Atomic operations** - Rollback on failure

## 🚀 Performance Features

### Parallel Processing

- **Parallel hash calculation** - Significantly faster for large datasets
- **Concurrent file verification** - Uses multiple CPU cores
- **Optimized rsync** - Efficient file copying with progress

### Resource Management

- **Memory efficient** - Streams large files without loading into memory
- **Disk space aware** - Checks available space before operations
- **Process monitoring** - Graceful handling of interruptions

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

### Debug Mode

For detailed debugging, check the log file:

```bash
tail -f conversion_$(date +%Y%m%d)_*.log
```

## 🆕 Recent Updates

### Version 2.1 Changes (Production-Ready)

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

## 🔄 Migration from Previous Versions

If you're upgrading from an earlier version:

1. **New options available** - Check updated usage with `-h`
2. **Improved error handling** - Better error messages and recovery
3. **Enhanced logging** - More detailed operation logs
4. **Performance improvements** - Faster execution with parallel options

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
- [BIDS Validator](https://github.com/bids-standard/bids-validator) - Official BIDS validation tool

## 📞 Support

- 🐛 **Bug Reports:** [Open an issue](https://github.com/yourusername/bids2datalad/issues)
- 💡 **Feature Requests:** [Start a discussion](https://github.com/yourusername/bids2datalad/discussions)
- 🧠 **BIDS Questions:** [Post on NeuroStars](https://neurostars.org/tags/bids)
- 📧 **Email:** [your.email@institution.edu](mailto:your.email@institution.edu)

---

Made with ❤️ by the MRI Lab Graz
