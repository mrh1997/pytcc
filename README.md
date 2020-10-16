PyTCC is a python extension for
[TCC](https://en.wikipedia.org/wiki/Tiny_C_Compiler).

TCC is a full-fledged, blazing fast (up to 9 times faster compilation time than GCC) and extraordinary small (about 300 kb) C99 compiler originally written by Fabrice Bellard and
now actively maintained by community.

This extensions provides a pythonic interface of the API
of TCC's tcclib. This library allows not only generating executables and 
libraries, but also running the generated code in the addressspace
of your python process without the need of creating a file on disk.


# Installation

The easiest way to install the tool is via pip:

```
pip install --upgrade pip      # only needed if current pip version < 19.3
pip install pytcc
```

Alternatively you could build it on your own from source
(see chapter "Howto build").


# First Steps

To compile a bunch of C files to ank executable and run it (with include/library
search path and macros specified):
```python
import pytcc
import subprocess
tcc_setup = pytcc.TCC(include_dirs=['incl'], library_dirs=['libs'], MACRO="value")
exe_binary = tcc_setup.build_to_exe('exename', 'src1.c', 'src2.c')
subprocess.run([str(exe_binary.path)])
```

If you want to build dynamic library instead of an executable and you want
to create it from in-memory source code it would look like:
```python
import pytcc
import ctypes
tcc_setup = pytcc.TCC()
lib_binary = tcc_setup.build_to_lib('libname', pytcc.CCode('''
__attribute__((dllexport)) int func(int p) { 
    return p+1; 
}
'''))
lib = ctypes.CDLL(str(lib_binary.path))
print(lib.func(123))
```

Alternatively you could build a library in memory and retrieve its symbols:
```python
import pytcc
import ctypes
func_t = ctypes.CFUNCTYPE(None, ctypes.c_int)
tcc_setup = pytcc.TCC()
mem_binary = tcc_setup.build_to_mem('src1.c', 'src2.c')
var_obj = ctypes.c_int.from_address(mem_binary['var'])
func_obj = func_t(mem_binary['func'])
func_obj(var_obj)
```


# Current status

![CI Badge](https://github.com/mrh1997/pytcc/workflows/Build%20pytcc%20and%20run%20unittests/badge.svg "Status of CI run of head")

* Provides tcclib API as pythonic interface
* Supports all major platforms:
   * Windows x86 and x64
   * macOS x64 (does not support executable/library generation yet and cannot find standard headers by default)
   * linux x64
* Provide ready to use binary wheels for all supported platforms

## Roadmap
* Make it work on macOS without manually referring to the  headerfiles of XCode by adding the darwin headerfiles to the TCC package
* MAYBE: Extend TCC (and PyTCC) to provide access to AST



# Howto Build

To build this extension the following software (apart from python) is
required as prerequisites:
* CMake
* C Compiler
* tox *[OPTIONAL]*

First of all you have to build the TCC binaries by running cmake to
create your platform specific project files and then build your project
files. In the last step you build the python C-extension as wheel via setup.py.

## Linux
```
>> cmake -B tinycc-bin/linux64
>> cmake --build tinycc-bin/linux64 --config Release
>> pip wheel -w wheels .
```

## macOS
```
>> cmake -B tinycc-bin/mac64
>> cmake --build tinycc-bin/mac64 --config Release
>> pip wheel -w wheels .
```

## Win32
```
>> cmake -A Win32 -B tinycc-bin/win32
>> cmake --build tinycc-bin/win32 --config Release
>> pip wheel -w wheels .
```

## Win64
```
>> cmake -A x64 -B tinycc-bin/win64
>> cmake --build tinycc-bin/win64 --config Release
>> pip wheel -w wheels .
```

Alternatively you could choose any directory as output for the TCC libraries
build by cmake and set the environment variable ``TCC_BUILD_DIR`` to the 
corresponding directory.

If you want to run the unittests the recommended way is running tox after you
built the TCC binaries.



# Howto debug

To debug pytcc it is recommended to run cmake when the python environment
that shall be used for the tests is activated.
CMake will then create an additional target: "pytcc".
This one can be used for creating the C extention without setup.py.
As cmake is supported by most C IDEs you can use the resulting project file
to debug the project:

For example on linux the sequence looks like:
```
>> source .tox/py36/bin/activate  # tox has to be run before this command!
>> cd tinycc-bin/linux64
>> rm -R *                        # necessary as CMake cache has to be reset
>> cmake ../..
>> make pytcc
>> export PYTHONPATH=.
>> python -m pytest ../../tests
```
