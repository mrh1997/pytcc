**Work in Progress!**

PyTCC shall become a python extension that contains 
[TCC](https://en.wikipedia.org/wiki/Tiny_C_Compiler), 
a full fledged C compiler from Fabrice Bellard.

In a first step it will only be a one to one adaption of the API
of TCC's tcclib. This library allows not only generating executables and 
libraries, but also running the generated code in the addressspace
of the current process without the need of creating a new file.

Current status:
* Supports 32bit Python on Windows
* Provide tcclib API in Pytho

Roadmap:
* Create Wheels for all platforms
* MAYBE: Make it Crossplatform
* MAYBE: Extend TCC (and PyTCC) to provide access to AST


# Howto Build

To build this extension the following software (apart from python) is
required as prerequisites:
* CMake
* C Compiler
* tox *[OPTIONAL]*

First of all you have to build the TCC binaries by running cmake to
create your platform specific project files and then build your project
files.

To build and test pytcc there are two options (depends on your use
case):
1. build and run the cmake target "pytcc" (see CMakeLists.txt). Requires
   to be tested by the following executable invocation: ```python.exe -m
   pytest <testname>```, where "testname" looks like
   ```test_pytcc.py::TestTcc::test_...```. To ensure that your pytcc
   module is found set the environment variable ```PYTHONPATH``` to the
   build directory (i.e. ```tinycc-bin/win32```).
2. run "tox". If The build was not done in the ```tinycc-bin```
   subdirectory please set ```TCC_BUILD_DIR``` to the build directory!

The first variant is preferrably used to debbug your C code with a C
debugger, while the second one is preferrably used to debug your
python code.