#!/usr/bin/env python3
# coding=utf-8

"""python distribute file

"""

from setuptools import setup, find_packages

def get_version_from_CliVersion():
    with open("../../lib/RD/CliVersion.hs", "r") as f:
        for line in f:
            if line.startswith("cliVersion = "):
                return line.split('"')[1].strip()
    raise Exception("version not found in CliVersion.hs")

setup(
    name="rd",
    version=get_version_from_CliVersion(),
    packages=find_packages(),
    package_data={
        'rdclient': ['rd']
    },
    entry_points={
        'console_scripts': [
            'rd = rdclient.main:main',
        ],
    },
    install_requires=[],
    author="Yuanle Song",
    author_email="sylecn@gmail.com",
    maintainer="Yuanle Song",
    maintainer_email="sylecn@gmail.com",
    description="reliable-download client tool",
    long_description=open('README.rst').read(),
    long_description_content_type="text/x-rst",
    license="GPLv3+",
    url="https://pypi.python.org/pypi/rd/",
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: End Users/Desktop',
        'Intended Audience :: System Administrators',
        'License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)',
        'Operating System :: POSIX :: Linux',
        'Topic :: System :: Networking',
        'Programming Language :: Haskell',
        'Programming Language :: Python :: 2.7',
        'Programming Language :: Python :: 3.4',
        'Programming Language :: Python :: 3.5',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
    ]
)
