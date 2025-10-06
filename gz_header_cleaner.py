#!/usr/bin/env python3
"""
GZIP Header Cleaner for BIDS Compliance
Removes MTIME, FNAME, and FHCRC fields from GZIP headers to ensure BIDS validation compatibility.
"""

from pathlib import Path
import os, sys, struct, argparse

# GZIP Flags
FHCRC    = 0x02
FEXTRA   = 0x04
FNAME    = 0x08
FCOMMENT = 0x10

def parse_gzip_header(f):
    """Parse GZIP header and return metadata and offsets."""
    start = f.tell()
    h = f.read(10)
    if len(h) < 10 or h[:2] != b"\x1f\x8b" or h[2] != 0x08:
        raise ValueError("Not a gzip member")
    flg = h[3]
    mtime = struct.unpack("<I", h[4:8])[0]
    idx = start + 10

    extra_len_off = None
    extra_end = None
    fname_start = fname_end = None
    fcomment_start = fcomment_end = None
    fhcrc_off = None

    # FEXTRA
    if flg & FEXTRA:
        extra_len_off = idx
        raw = f.read(2); idx += 2
        if len(raw) < 2:
            raise ValueError("Truncated EXTRA length")
        xlen = struct.unpack("<H", raw)[0]
        f.seek(xlen, os.SEEK_CUR); idx += xlen
        extra_end = idx

    # FNAME (C-String)
    if flg & FNAME:
        fname_start = idx
        while True:
            b = f.read(1)
            if not b:
                raise ValueError("Truncated FNAME")
            idx += 1
            if b == b"\x00":
                fname_end = idx
                break

    # FCOMMENT (C-String)
    if flg & FCOMMENT:
        fcomment_start = idx
        while True:
            b = f.read(1)
            if not b:
                raise ValueError("Truncated FCOMMENT")
            idx += 1
            if b == b"\x00":
                fcomment_end = idx
                break

    # FHCRC (2 Bytes)
    if flg & FHCRC:
        fhcrc_off = idx
        f.seek(2, os.SEEK_CUR); idx += 2

    payload_start = idx
    return (h, flg, mtime, {
        'start': start,
        'after_fixed': start + 10,
        'extra_len_off': extra_len_off,
        'extra_end': extra_end,
        'fname_start': fname_start,
        'fname_end': fname_end,
        'fcomment_start': fcomment_start,
        'fcomment_end': fcomment_end,
        'fhcrc_off': fhcrc_off,
        'payload_start': payload_start
    })

def needs_cleaning(path: Path):
    """Check if a GZIP file needs header cleaning."""
    with open(path, "rb") as f:
        h, flg, mtime, _ = parse_gzip_header(f)
    need_mtime = (mtime != 0)
    need_fname = bool(flg & FNAME)
    need_fhcrc = bool(flg & FHCRC)
    return need_mtime, need_fname, need_fhcrc, flg, mtime

def rewrite_header_only(inf, outf, meta):
    """
    Rewrite GZIP header with MTIME=0, remove FNAME field, and remove FHCRC if present.
    Preserves FEXTRA and FCOMMENT fields unchanged.
    """
    (first10, flg, mtime, off) = meta

    # Adjust flags: remove FNAME and FHCRC
    new_flg = flg & ~FNAME
    if flg & FHCRC:
        new_flg &= ~FHCRC
        drop_fhcrc = True
    else:
        drop_fhcrc = False

    # Rebuild fixed 10-byte header with mtime=0 and new flags
    new_fixed = bytearray(first10)
    new_fixed[3] = new_flg
    new_fixed[4:8] = b"\x00\x00\x00\x00"  # MTIME = 0

    # Write fixed header
    outf.write(new_fixed)

    # Write optional fields in original order, excluding FNAME and optionally FHCRC
    # 1) FEXTRA (if present): copy unchanged
    if flg & FEXTRA:
        inf.seek(off['extra_len_off'])
        outf.write(inf.read(off['extra_end'] - off['extra_len_off']))

    # 2) FCOMMENT (if present): copy unchanged
    if flg & FCOMMENT:
        inf.seek(off['fcomment_start'])
        outf.write(inf.read(off['fcomment_end'] - off['fcomment_start']))

    # Skip FNAME (removed)

    # 3) Skip FHCRC if dropping it
    payload_from = off['payload_start']
    if drop_fhcrc and off['fhcrc_off'] is not None:
        payload_from = off['fhcrc_off'] + 2

    # Copy rest of file (compressed data + trailer + additional members)
    inf.seek(payload_from, os.SEEK_SET)
    BUF = 1024 * 1024
    while True:
        chunk = inf.read(BUF)
        if not chunk:
            break
        outf.write(chunk)

def clean_file(path: Path):
    """Clean a single GZIP file."""
    with open(path, "rb") as inf:
        meta = parse_gzip_header(inf)
        tmp = path.with_suffix(path.suffix + ".tmp")
        with open(tmp, "wb") as outf:
            rewrite_header_only(inf, outf, meta)
        os.replace(tmp, path)

def clean_gzip_headers(directory, dry_run=False, verbose=False):
    """
    Clean GZIP headers in all .gz files under the given directory.
    Returns (total_files, cleaned_files, errors).
    """
    root = Path(directory)
    if not root.exists():
        raise FileNotFoundError(f"Directory not found: {root}")

    # Find all *.gz files recursively
    targets = list(root.rglob("*.gz"))
    if not targets:
        if verbose:
            print("🔍 No .gz files found.")
        return 0, 0, 0

    total = changed = errors = 0
    
    if verbose:
        print(f"🔍 Found {len(targets)} .gz files to check...")

    for p in sorted(targets):
        total += 1
        try:
            need_mtime, need_fname, need_fhcrc, flg, mtime = needs_cleaning(p)
        except Exception as e:
            if verbose:
                print(f"❌ Error checking {p.name}: {e}")
            errors += 1
            continue

        if need_mtime or need_fname:
            issues = []
            if need_mtime: 
                issues.append(f"mtime={mtime}")
            if need_fname: 
                issues.append("filename")
            if need_fhcrc: 
                issues.append("crc")
            
            if dry_run:
                if verbose:
                    print(f"🧪 Would clean {p.name} ({', '.join(issues)})")
            else:
                try:
                    clean_file(p)
                    if verbose:
                        print(f"✅ Cleaned {p.name} ({', '.join(issues)})")
                    changed += 1
                except Exception as e:
                    if verbose:
                        print(f"❌ Error cleaning {p.name}: {e}")
                    errors += 1

    return total, changed, errors

def main():
    parser = argparse.ArgumentParser(
        description="Clean GZIP headers for BIDS compliance by removing MTIME, FNAME, and FHCRC fields",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /path/to/bids/dataset
  %(prog)s --dry-run /path/to/bids/dataset
  %(prog)s --verbose /path/to/bids/dataset
        """
    )
    parser.add_argument("directory", help="Path to directory containing .gz files")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be cleaned without making changes")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show detailed progress information")
    parser.add_argument("--quiet", "-q", action="store_true", help="Suppress all output except errors")
    
    args = parser.parse_args()

    # Adjust verbosity
    verbose = args.verbose and not args.quiet

    try:
        total, changed, errors = clean_gzip_headers(args.directory, args.dry_run, verbose)
        
        if not args.quiet:
            if args.dry_run:
                print(f"🧪 Dry run complete: {total} files checked, {changed} would be cleaned, {errors} errors")
            else:
                if changed > 0:
                    print(f"✅ GZIP header cleaning complete: {changed}/{total} files cleaned")
                else:
                    print(f"✅ All {total} .gz files already have clean headers")
            
            if errors > 0:
                print(f"⚠️ {errors} files had errors during processing")
                
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()