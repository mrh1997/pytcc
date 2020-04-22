from typing import List, Dict, Optional, Union
from libc.stdint cimport uintptr_t
from pathlib import Path
import os
import platform
import sys
import pkg_resources


TCC_LIB_PATH = Path(sys.prefix) / 'tcc-rtlib'
if platform.system() != 'Windows':
    TCC_LIB_PATH /= 'lib'


DEF TCC_OUTPUT_MEMORY =      1 # output will be run in memory (default)
DEF TCC_OUTPUT_EXE =         2 # executable file
DEF TCC_OUTPUT_DLL =         3 # dynamic library
DEF TCC_OUTPUT_OBJ =         4 # object file
DEF TCC_OUTPUT_PREPROCESS =  5 # only preprocess (used internally)

DEF TCC_RELOCATE_AUTO = 1

cdef extern from "libtcc.h":
    ctypedef struct TCCState:
        pass
    cdef TCCState *tcc_new()
    cdef void tcc_delete(TCCState *s)
    cdef void tcc_set_lib_path(TCCState *s, const char *path)
    cdef void tcc_set_error_func(TCCState *s, void *error_opaque,
        void (*error_func)(void *opaque, const char *msg))
    cdef void tcc_set_options(TCCState *s, const char *str)
    cdef int tcc_add_include_path(TCCState *s, const char *pathname)
    cdef int tcc_add_sysinclude_path(TCCState *s, const char *pathname)
    cdef void tcc_define_symbol(TCCState *s, const char *sym, const char *value)
    cdef void tcc_undefine_symbol(TCCState *s, const char *sym)
    cdef int tcc_add_file(TCCState *s, const char *filename)
    cdef int tcc_compile_string(TCCState *s, const char *buf)
    cdef int tcc_set_output_type(TCCState *s, int output_type)
    cdef int tcc_add_library_path(TCCState *s, const char *pathname)
    cdef int tcc_add_library(TCCState *s, const char *libraryname)
    cdef int tcc_add_symbol(TCCState *s, const char *name, const void *val)
    cdef int tcc_output_file(TCCState *s, const char *filename)
    cdef int tcc_run(TCCState *s, int argc, char **argv)
    cdef int tcc_relocate(TCCState *s1, void *ptr)
    cdef void *tcc_get_symbol(TCCState *s, const char *name)
    cdef void tcc_list_symbols(TCCState *s, void *ctx,
        void (*symbol_cb)(void *ctx, const char *name, const void *val))


__version__ = pkg_resources.get_distribution('PyTCC').version


def c_str(s:str) -> bytes:
    return s.encode(sys.getdefaultencoding())


class TccError(Exception):
    """
    Generic base class for TCC errors
    """


class CompileError(TccError):
    """
    Any error that happens during compilation due to invalid code
    """

    def __parts(self):
        return [p.strip() for p in str(self).split(':', 3)]

    @property
    def filename(self):
        """
        Returns the name of the file in which the error occurred
        (or <string> if CCode() was used)
        """
        filename, lineno, type, text = self.__parts()
        return filename

    @property
    def lineno(self):
        """
        Returns the line number in which the error occured
        """
        filename, lineno, type, text = self.__parts()
        return int(lineno)

    @property
    def type(self):
        """
        returns the error type. Usually "error". If option "Werror" is set,
        this field can also be "warning"
        """
        filename, lineno, type, text = self.__parts()
        return type

    @property
    def text(self):
        """
        The actual error text
        (without additional info like filename, lineno, ...)
        """
        filename, lineno, type, text = self.__parts()
        return text


cdef void compile_error_func(void *opaque, const char *msg):
    (<InMemBinary> opaque)._warnings.append(msg.decode('ascii'))


cdef class InMemBinary:
    """
    This represents the output of TCC when processing the input with
    .build_to_mem().
    """
    cdef TCCState * tcc_state
    cdef list _warnings
    cdef int _closed
    cdef int _relocated
    cdef dict _global_defines

    def __init__(self, output:int):
        if platform.system() == 'Darwin' and output != TCC_OUTPUT_MEMORY:
            raise TccError('exe/lib file generation on macOS not supported yet')
        self._warnings = []
        self._closed = False
        self._relocated = False
        self._global_defines = {}
        self.tcc_state = tcc_new()
        if self.tcc_state == NULL:
            raise MemoryError('Out of memory')
        tcc_set_lib_path(self.tcc_state, os.fsencode(TCC_LIB_PATH))
        tcc_set_output_type(self.tcc_state, output)
        tcc_set_error_func(self.tcc_state, <void*>self, compile_error_func)

    cdef define(self, name:str, value:Union[str, None]=None, is_global=False):
        if value is None:
            tcc_define_symbol(self.tcc_state, c_str(name), NULL)
        else:
            tcc_define_symbol(self.tcc_state, c_str(name), c_str(str(value)))
        if is_global:
            self._global_defines[name] = value

    cdef undef(self, name:str, is_global=False):
        if not is_global and name in self._global_defines:
            self.define(name, self._global_defines[name])
        else:
            tcc_undefine_symbol(self.tcc_state, c_str(name))
        if is_global:
            del self._global_defines[name]

    @property
    def global_defines(self) -> Dict[str, Union[str, None]]:
        return self._global_defines

    @property
    def relocated(self) -> bool:
        return self._relocated

    @property
    def closed(self) -> bool:
        return self._closed

    @property
    def warnings(self) -> List[str]:
        self.relocate()
        return self._warnings

    def run(self):
        if self._relocated:
            raise NotImplementedError(
                'Currently running after relocation is not supported')
        if self._closed:
            raise ValueError('InMemoryBinary is already closed')
        result = tcc_run(self.tcc_state, 0, NULL)
        self._relocated = True
        self.close()
        return result

    def __del__(self):
        self.close()

    def close(self):
        if not self._closed:
            tcc_delete(self.tcc_state)
            self._closed = True

    def __enter__(self) -> 'InMemBinary':
        self.relocate()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def __contains__(self, symbol_name):
        """
        returns True, if the symbol named "symbol_name" exists in this binary
        """
        self.relocate()
        symbol_name_cstr = symbol_name.encode('ascii')
        return tcc_get_symbol(self.tcc_state, symbol_name_cstr) != NULL

    def __getitem__(self, symbol_name:str) -> int:
        """
        returns the address of the symbol named "symbol_name"
        """
        self.relocate()
        symbol_name_cstr = symbol_name.encode('ascii')
        cdef void * adr = tcc_get_symbol(self.tcc_state, symbol_name_cstr)
        if adr == NULL:
            raise KeyError(f'Symbol {symbol_name!r} is not defined')
        else:
            return <uintptr_t>adr

    def relocate(self):
        """
        ensures that Binary is relocated in memory.
        Can be called multiple times.
        """
        if self._closed:
            raise ValueError('InMemoryBinary is already closed')
        if not self._relocated:
            if tcc_relocate(self.tcc_state, <void*>TCC_RELOCATE_AUTO) == -1:
                self.error('Error during Relocation of C Code')
            self._relocated = True

    def error(self, msg):
        if len(self._warnings) > 0:
            raise TccError(msg + ': ' + self._warnings[-1])
        else:
            raise TccError(msg)


class FileBinary:

    def __init__(self, filename:os.PathLike, warnings:List[str]=None,
                 auto_add_suffix=True, dest_os=None):
        abs_filename = Path.cwd() / Path(filename)
        if auto_add_suffix:
            suffix = self.DEFAULT_SUFFIXES[dest_os or platform.system()]
            self.filename = abs_filename.with_suffix(suffix)
        else:
            self.filename = abs_filename
        self.warnings = warnings or []


class ExeBinary(FileBinary):
    """
    This represents the output of TCC when processing the input with
    build_to_exe()
    """

    DEFAULT_SUFFIXES = dict(
        Windows='.exe',
        Linux='',
        Darwin='')


class LibBinary(FileBinary):
    """
    This represents the output of TCC when processing the input with
    build_to_lib()
    """

    DEFAULT_SUFFIXES = dict(
        Windows='.dll',
        Linux='.so',
        Darwin='.dylib')


class LinkUnit:
    """
    A link unit is an abstract base class for any object that can be linked
    with TCC
    """
    def link_into(self, bin:InMemBinary):
        raise NotImplementedError('This is an abstract base class')


class ArchBinary(FileBinary, LinkUnit):
    """
    An archive binary represents a static library.
    It can be the the result of build_to_arch() plus the input
    to build_to_*().
    """

    DEFAULT_SUFFIXES = dict(
        Windows='.a',
        Linux='.a',
        Darwin='.a')

    def link_into(self, bin:InMemBinary):
        if tcc_add_file(bin.tcc_state, c_str(str(self.filename))) == -1:
            raise CompileError(bin.warnings[-1])


class CompileUnit(LinkUnit):
    """
    Any kind of C Source Code that can be passed to TCC.run(), ...
    """

    def __init__(self, defines=None, **defines2):
        self.defines = defines2
        self.defines.update(defines or {})

    def link_into(self, bin:InMemBinary):
        for def_name, def_val in self.defines.items():
            bin.define(def_name, def_val)
        if self._link_c_code(bin) == -1:
            raise CompileError(bin.warnings[-1])
        for def_name in self.defines:
            bin.undef(def_name)

    def _link_c_code(self, bin:InMemBinary) -> int:
        raise NotImplementedError('Has to be implemented by ancestor class')


class SourceFile(CompileUnit):
    """
    Represents a .c file on your local file system that shall be compiled with
    a set of defines. Has to be passed to TCCConfig.run(),
    """

    def __init__(self, filename, defines=None, **defines2):
        super().__init__(defines, **defines2)
        self.filename = filename

    def _link_c_code(self, bin:InMemBinary):
        return tcc_add_file(bin.tcc_state, c_str(self.filename))


class CFile(SourceFile):
    pass


class AsmFile(SourceFile):
    pass


class CCode(CompileUnit):
    """
    A in-memory C source code file represented as python string
    """

    def __init__(self, c_code, defines=None, **defines2):
        super().__init__(defines, **defines2)
        self.c_code = c_code

    def _link_c_code(self, bin:InMemBinary):
        return tcc_compile_string(bin.tcc_state, self.c_code.encode('ascii'))


class TCC:
    """
    A TCC object represents the setup that is used to compile and link files.
    """

    def __init__(self,
                 *options2, options:List[str]=[],
                 defines:Dict[str, Optional[str]]={},
                 include_dirs:List[str]=[],
                 sys_include_dirs:List[str]=[],
                 library_dirs:List[str]=[],
                 **defines2):
        """
        It is possible to set command line options, defines and include and
        library directories
        """
        self.options = list(options2) + options
        self.defines = dict(defines)
        self.defines.update(defines2)
        self.include_dirs = list(include_dirs)
        self.sys_include_dirs = list(sys_include_dirs)
        self.library_dirs = list(library_dirs)

    def _build(self, bin:InMemBinary, link_units:List[LinkUnit],
               additional_options=None):
        for incl_path in self.include_dirs:
            tcc_add_include_path(bin.tcc_state, c_str(incl_path))
        for sys_incl_path in self.sys_include_dirs:
            tcc_add_sysinclude_path(bin.tcc_state, c_str(sys_incl_path))
        for option in self.options + (additional_options or []):
            tcc_set_options(bin.tcc_state, c_str(option))
        for def_name, def_val in self.defines.items():
            bin.define(def_name, def_val, is_global=True)
        for link_unit in link_units:
            if isinstance(link_unit, str):
                link_unit = CFile(link_unit)
            link_unit.link_into(bin)

    def build_to_mem(self, *link_units:List[Union[LinkUnit, str]],
                     eager:bool=False) -> InMemBinary:
        bin = InMemBinary(TCC_OUTPUT_MEMORY)
        self._build(bin, link_units)
        if eager:
            bin.relocate()
        return bin

    def build_to_exe(self, filename:os.PathLike,
                     *link_units:List[Union[LinkUnit, str]],
                     auto_add_suffix=True) -> ExeBinary:
        mem_bin = InMemBinary(TCC_OUTPUT_EXE)
        self._build(mem_bin, link_units)
        exe_bin = ExeBinary(filename, mem_bin._warnings, auto_add_suffix)
        if tcc_output_file(mem_bin.tcc_state, c_str(str(exe_bin.filename)))!=0:
            mem_bin.error(f'Failed to write executable to {exe_bin.filename}')
        return exe_bin

    def build_to_lib(self, filename:os.PathLike,
                     *link_units:List[Union[LinkUnit, str]],
                     auto_add_suffix=True) -> LibBinary:
        mem_bin = InMemBinary(TCC_OUTPUT_DLL)
        self._build(mem_bin, link_units)
        lib_bin = LibBinary(filename, mem_bin._warnings, auto_add_suffix)
        if tcc_output_file(mem_bin.tcc_state, c_str(str(lib_bin.filename)))!=0:
            mem_bin.error(f'Failed to write dynamic library to '
                          f'{lib_bin.filename}')
        return lib_bin

    def build_to_arch(self, filename:os.PathLike,
                      *link_units:List[Union[LinkUnit, str]]) -> ArchBinary:
        mem_bin = InMemBinary(TCC_OUTPUT_OBJ)
        self._build(mem_bin, link_units, ['-ar'])
        arch_bin = ArchBinary(filename, mem_bin._warnings, False)
        if tcc_output_file(mem_bin.tcc_state, c_str(str(arch_bin.filename)))!=0:
            mem_bin.error(f'Failed to write archive file to '
                          f'{arch_bin.filename}')
        return arch_bin
