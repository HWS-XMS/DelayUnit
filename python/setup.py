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
    author="TU Berlin - SASS Group",
    author_email="sass@tu-berlin.de",
    description="FPGA-based picosecond delay control with 20ps resolution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://git.tu-berlin.de/sass/delay_unit",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Science/Research",
        "Topic :: Scientific/Engineering :: Electronic Design Automation (EDA)",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
    python_requires=">=3.7",
    install_requires=[
        "pyserial>=3.4",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0",
            "pytest-cov>=4.0",
            "black>=22.0",
            "flake8>=5.0",
        ],
    },
)