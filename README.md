# shtdlib
Shell Standard Library

For an example of how to install/import see:

import_install_example.sh


For testing bash code across multiple versions of bash we highly recommend
using the bashtester submodule, you can pull it with this repository by using:

git clone --recurse-submodules https://github.com/sdelements/shtdlib.git

Or if you've already cloned this project you can initialize and pull using:

git submodule init
git submodule update --recursive


Test Examples:

- all supported versions

import shtdlib.sh && test_shtdlib

- local bash only, no containers

import shtdlib.sh && test_shtdlib local

- specific bash version(s)

import shtdlib.sh && test_shtdlib 3.1.23 4.4.23


Supported bash versions currently include the following though not all
functions will be supported on all versions.

3.1.23
3.2.57
4.0.44
4.1.17
4.2.53
4.3.48
4.4.23
5.0-beta
