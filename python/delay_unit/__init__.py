"""
delay_unit - FPGA-based picosecond delay control package.

A Python package for controlling FPGA-based trigger delay systems
with 20.12ps resolution using Xilinx MMCM technology.
"""

from .core import DelayUnit, EdgeType, Command
from .version import __version__

__all__ = ['DelayUnit', 'EdgeType', 'Command', '__version__']

# Package metadata
__author__ = 'TU Berlin - SASS Group'
__email__ = 'sass@tu-berlin.de'
__license__ = 'MIT'