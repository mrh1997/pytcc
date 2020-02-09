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
 * Provide tcclib API in Python

Roadmap:
*  Create Wheels for all platforms
*  MAYBE: Make it Crossplatform
 * MAYBE: Extend TCC (and PyTCC) to provide access to AST