#!/usr/bin/env python3
"""Measure both first and subsequent warm native hooks against 30 seconds."""
import argparse
from pathlib import Path

from initial_scale_probe import run


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'scale', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--labels', nargs='+', choices=['2', '1024', '10000', '50000'],
        default=['10000', '50000', '2', '1024'])
    parser.add_argument('--prepared-from', type=Path)
    parser.add_argument('--ready-inputs', type=Path)
    run(parser.parse_args(), uniform_deadline=True, entrypoint=Path(__file__))
