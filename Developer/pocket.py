#!/usr/bin/env python3
"""Deprecated command shim. All validation lives in the TypeScript CLI."""
import subprocess
import sys
from pathlib import Path

if __name__ == '__main__':
    raise SystemExit(subprocess.call(['node', str(Path(__file__).with_name('src') / 'cli.ts'), *sys.argv[1:]]))
