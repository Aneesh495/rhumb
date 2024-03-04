#!/usr/bin/env python3
import os
import sys

IGNORED_DIRS = {'.git', 'bin', '__pycache__', '.vmodules', 'lib', 'build', 'dist', '.idea', '.vscode'}
IGNORED_EXTS = {'.pyc', '.dylib', '.so', '.o', '.a', '.png', '.jpg', '.jpeg', '.mvt', '.pbf', '.rhumb'}

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    violations = []
    total_files = 0
    total_lines = 0

    for root, dirs, files in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS]
        for f in files:
            ext = os.path.splitext(f)[1]
            if ext in IGNORED_EXTS:
                continue
            path = os.path.join(root, f)
            rel_path = os.path.relpath(path, repo_root)

            try:
                with open(path, 'r', encoding='utf-8') as fp:
                    total_files += 1
                    for line_idx, line in enumerate(fp, 1):
                        total_lines += 1
                        if '\u2014' in line or '\u2013' in line:
                            violations.append((rel_path, line_idx, line.strip()))
            except UnicodeDecodeError:
                continue

    print(f"Scanned {total_files} files ({total_lines:,} lines of text)...")

    if violations:
        print(f"ERROR: Found {len(violations)} dash violation(s):")
        for file_path, line_no, content in violations:
            print(f"  {file_path}:{line_no}: {content}")
        sys.exit(1)
    else:
        print("VERIFICATION PASSED: Absolute zero em/en dashes found across the entire repository!")
        sys.exit(0)

if __name__ == '__main__':
    main()
