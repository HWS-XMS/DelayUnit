"""Setup script for delay_unit package."""

from setuptools import setup, find_packages
from pathlib import Path

# Read the README file
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text()

# Read version
version = {}
with open("delay_unit/version.py") as fp:
    exec(fp.read(), version)

setup(
    name="delay-unit",
    version=version['__version__'],
    description="FPGA-based trigger delay control with 5ns resolution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Science/Research",
        "Topic :: Scientific/Engineering",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
    ],
    python_requires=">=3.7",
    install_requires=[
        "pyserial>=3.4",
    ],
)