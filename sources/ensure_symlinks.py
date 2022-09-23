#!/usr/bin/env python3
"""
Takes a list of .so file names from arguments or stdin.

File names are grouped by a shared base name (e.g., libsomething.so) and
symbolic links are created to a single "real" file that has the longest name.

So with files libsomething.so, libsomething.so.1, libsomething.so.1.0.0 you
will get:

libsomething.so -> libsomething.so.1.0.0
libsomething.so.1 -> libsomething.so.1.0.0
libsomething.so.1.0.0 (real)
"""
import re
import shutil
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

# -----------------------------------------------------------------------------


def main():
    # Gather file names
    if len(sys.argv) > 1:
        file_names = sys.argv[1:]
    else:
        file_names = [f.strip() for f in sys.stdin]

    # Convert to Paths
    file_paths = [Path(f) for f in file_names]
    file_groups = defaultdict(list)

    # Group files by shared base name (e.g., libsomething.so)
    for file_path in file_paths:
        match = re.match(r"([^.]+\.so)(.*)", file_path.name)
        if match:
            base_name = match.group(1)
            file_groups[base_name].append(file_path)

    # Keep file copies in temp directory
    with tempfile.TemporaryDirectory() as temp_dir_name:
        temp_dir = Path(temp_dir_name)
        for base_name, group_paths in file_groups.items():
            if len(group_paths) == 1:
                # No need for links with just one file
                continue

            # Make a temporary copy of the first file that exists in the group
            for file_path in group_paths:
                if file_path.is_file():
                    # Follow symlinks so a real file will be copied
                    shutil.copy(str(file_path), str(temp_dir / base_name), follow_symlinks=True)
                    break

            # Delete originals
            longest_path = None
            for file_path in group_paths:
                # Longest file path will be real file (e.g., libsomething.so.1.0.0)
                if (longest_path is None) or (
                    len(file_path.name) > len(longest_path.name)
                ):
                    longest_path = file_path

                file_path.unlink()

            # Copy real file back to longest path
            shutil.copy(str(temp_dir / base_name), str(longest_path))

            # Create links to longest path
            for file_path in group_paths:
                if file_path != longest_path:
                    # Symbolic link will be relative
                    file_path.symlink_to(longest_path.relative_to(file_path.parent))
                    print(str(file_path), "->", str(longest_path))


# -----------------------------------------------------------------------------

if __name__ == "__main__":
    main()
