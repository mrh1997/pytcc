**Work in Progress!**

PyTCC shall become a python extension that contains 
[TCC](https://en.wikipedia.org/wiki/Tiny_C_Compiler), 
a full fledged C compiler from Fabrice Bellard.

In a first step it will only be a one to one adaption of the API
of TCC's tcclib. This library allows not only generating executables and 
libraries, but also running the generated code in the addressspace
of the current process without the need of creating a new file.

Current status:
 * Compiles on Windows with Visual Studio

Roadmap:
 * Provide tcclib API in Python
 * Create Wheels
 * Make it Crossplatform
 * MAYBE: Extend TCC (and PyTCC) to provide access to AST