## 🧠 MRI Data Conversion Script

This script is designed to convert, validate, and store BIDS-formatted MRI data into a [DataLad](https://www.datalad.org/) superdataset with subject-level subdatasets. It also verifies file integrity using SHA-256 checksums and logs all operations to a file (`conversion.log`).

### ❗ Usage Notes

Please ensure that the script arguments are provided **correctly**, as they directly affect the output structure and behavior.

- `src_dir` should point to the **rawdata folder** of your BIDS-valid study, e.g.,

  ```
  path/to/your-study/rawdata
  ```

- `dest_dir` should be the **base directory** where you want the DataLad dataset(s) to be created.

#### ✅ Example

Assuming you have:

- A BIDS-valid dataset located at:

  ```
  /data/local/study-01/rawdata
  ```

- A destination base directory for your DataLad dataset at:

  ```
  /data/repo/datalad
  ```

You would run:

```
./bids2datalad.sh -s /data/local/study-01/rawdata -d /data/repo/datalad
```

This will result in a DataLad superdataset at:

```
/data/repo/datalad/study-01/rawdata
```

With sub-datasets for each subject created automatically under that path.



### 📦 Prerequisites

Before using the script, ensure the following are installed:

- [`datalad`](https://www.datalad.org/)
- [`deno`](https://deno.land/) (for running the [BIDS Validator](https://github.com/bids-standard/bids-validator))
- `rsync`, `sha256sum`, and other standard Unix utilities

------

### 🚀 Usage

```
./bids2datalad.sh [-h] [-s src_dir] [-d dest_dir] [--skip_bids_validation]
```

#### 🔧 Options

| Option                   | Description                                                  |
| ------------------------ | ------------------------------------------------------------ |
| `-h`                     | Show help message                                            |
| `-s src_dir`             | Source directory containing BIDS data (must contain `sub-*` subject folders) |
| `-d dest_dir`            | Root destination directory for creating the DataLad dataset  |
| `--skip_bids_validation` | Skip the BIDS format validation step                         |



------

### 🧪 Example

```
# Validate and convert a BIDS dataset
./your_script_name.sh -s /data/bids_dataset -d /datalad_storage

# Skip BIDS validation (if already validated)
./your_script_name.sh --skip_bids_validation -s /data/bids_dataset -d /datalad_storage
```

------

### 📁 Output Structure

Given `-s /data/study1/bids_raw` and `-d /output`, the resulting structure will be:

```
/output/study1/rawdata/
├── sub-01/    (as a DataLad sub-dataset)
├── sub-02/
└── ...
```

- A **DataLad superdataset** will be created at `rawdata/`
- **Each subject** is stored as a **sub-dataset**
- All files are **verified by hash** against the original source

------

### 🛠 Features

- ✅ **BIDS validation** (with option to skip)
- 📂 **Automatic creation of sub-datasets** per subject
- 🔐 **SHA-256 checksum comparison** between source and destination
- 📜 **Detailed logging** to `conversion.log`
- ❓ **Interactive confirmation** when overwriting destination

------

### 📑 Log Output

All logs are stored in `conversion.log` and streamed to the terminal for transparency.

Example:

```
2025-06-06 12:34:56 - INFO - ✅ BIDS validation completed successfully!
2025-06-06 12:35:01 - INFO - 📁 Copying files from /data/bids_dataset to /datalad_storage/study1/rawdata...
```

------

### ❗ Notes

- Ensure that `src_dir` ends at the subject folder level, e.g., `/study_name/bids_raw` with `/bids_raw/sub-*`
- `dest_dir` will be used to auto-create `/study_name/rawdata`
- This script **does not anonymize** or modify the dataset — it simply validates, copies, and verifies.

------

### 📬 Feedback

Please open an issue if you encounter bugs or have feature requests.
