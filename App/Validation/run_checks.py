#!/usr/bin/env python3
"""Run Foundation-only checks without requiring the iOS SDK."""
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parent.parent
sources = [root / 'Yoru' / name for name in ['Anime.swift', 'Kitsu.swift', 'AnimeAPI.swift', 'Journal.swift', 'RustCore.swift', 'Library.swift', 'WeeklySchedule.swift']]
with tempfile.TemporaryDirectory(prefix='yoru-checks-') as directory:
    for check in ['ModelChecks', 'JournalChecks', 'ScheduleChecks']:
        binary = Path(directory) / check
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', *map(str, sources), str(root / 'Validation' / (check + '.swift')), '-L', str(root.parent / 'rust-core/target/release'), '-lyoru_rust_core', '-o', str(binary)], check=True)
        args = [str(binary)]
        if check in ['ModelChecks', 'ScheduleChecks']:
            args.append(str(root / 'Validation'))
            if '--live' in sys.argv: args.append('--live')
        subprocess.run(args, check=True)
