"""
delay_unit - FPGA-based picosecond delay control package.

A Python package for controlling FPGA-based trigger delay systems
with 20.12ps resolution using Xilinx MMCM technology.
"""

from .core import DelayUnit, EdgeType, Command, TriggerMode, CounterMode, ArmedMode
from .version import __version__

__all__ = ['DelayUnit', 'EdgeType', 'Command', 'TriggerMode', 'CounterMode', 'ArmedMode', '__version__']

# Package metadata
__author__ = 'Marvin Sass'
__email__ = 'sass@tu-berlin.de'
__license__ = 'MIT'