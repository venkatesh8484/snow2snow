#!/usr/bin/env python3
"""DEPRECATED shim. The canonical report generator is build_report.py.
Kept only so any stale reference still produces the correct rich report."""
import runpy, pathlib, sys
sys.argv = [str(pathlib.Path(__file__).with_name("build_report.py"))] + sys.argv[1:]
runpy.run_path(str(pathlib.Path(__file__).with_name("build_report.py")), run_name="__main__")
