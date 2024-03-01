from setuptools import setup, find_packages

setup(
    name="rhumb",
    version="0.1.0",
    description="Python client library and bindings for the Rhumb geospatial routing and map-matching engine",
    author="Aneesh Krishna",
    packages=find_packages(),
    python_requires=">=3.9",
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Topic :: Scientific/Engineering :: GIS",
    ],
)
