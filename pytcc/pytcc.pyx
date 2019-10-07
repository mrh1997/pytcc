from typing import List, Dict, Optional, Union
from sys import getdefaultencoding
from libc.stdint cimport uintptr_t


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


def c_str(s:str) -> bytes:
    return s.encode(getdefaultencoding())


class CompileError(Exception):
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
    (<Binary> opaque)._warnings.append(msg.decode('ascii'))


cdef class Binary:
    """
    This represents the result of compiling multiple source files.
    """
    cdef TCCState * tcc_state
    cdef list _warnings
    cdef _closed

    def __init__(self, output):
        self.tcc_state = tcc_new()
        self._warnings = []
        self._closed = False
        if self.tcc_state == NULL:
            raise MemoryError('Out of memory')
        tcc_set_lib_path(self.tcc_state, b'D:\\PyTCC\\tinycc\\win32')
        tcc_set_output_type(self.tcc_state, output)
        tcc_set_error_func(self.tcc_state, <void*>self, compile_error_func)

    @property
    def closed(self) -> bool:
        return self._closed

    @property
    def warnings(self) -> List[str]:
        return self._warnings

    def __del__(self):
        if not self._closed:
            self.close()

    def close(self):
        tcc_delete(self.tcc_state)
        self._closed = True

    def __enter__(self) -> 'Binary':
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def __contains__(self, symbol_name):
        """
        returns True, if the symbol named "symbol_name" exists in this binary
        """
        symbol_name_cstr = symbol_name.encode('ascii')
        return tcc_get_symbol(self.tcc_state, symbol_name_cstr) != NULL

    def __getitem__(self, symbol_name:str) -> int:
        """
        returns the address of the symbol named "symbol_name"
        """
        symbol_name_cstr = symbol_name.encode('ascii')
        cdef void * adr = tcc_get_symbol(self.tcc_state, symbol_name_cstr)
        if adr == NULL:
            raise KeyError(f'Symbol {symbol_name!r} is not defined')
        else:
            return <uintptr_t>adr


class LinkUnit:
    """
    A link unit is an abstract base class for any object that can be linked
    with TCC
    """
    def link_into(self, bin:Binary):
        raise NotImplementedError('This is an abstract base class')


class CompileUnit(LinkUnit):
    """
    Any kind of C Source Code that can be passed to TCC.run(), ...
    """

    def __init__(self, defines=None, **defines2):
        self.defines = defines2
        self.defines.update(defines or {})

    def link_into(self, bin:Binary):
        for def_name, def_val in self.defines.items():
            if def_val is None:
                tcc_define_symbol(bin.tcc_state, c_str(def_name), NULL)
            else:
                tcc_define_symbol(bin.tcc_state, c_str(def_name),
                                  c_str(str(def_val)))
        if self._link_c_code(bin) == -1:
            raise CompileError(bin.warnings[-1])
        for def_name in self.defines:
            tcc_undefine_symbol(bin.tcc_state, c_str(def_name))

    def _link_c_code(self, bin:Binary) -> int:
        raise NotImplementedError('Has to be implemented by ancestor class')


class CFile(CompileUnit):
    """
    Represents a .c file on your local file system that shall be compiled with
    a set of defines. Has to be passed to TCCConfig.run(),
    """

    def __init__(self, c_file, defines=None, **defines2):
        super().__init__(defines, **defines2)
        self.c_file = c_file

    def _link_c_code(self, bin:Binary):
        return tcc_add_file(bin.tcc_state, c_str(self.c_file))


class CCode(CompileUnit):
    """
    A in-memory C source code file represented as python string
    """

    def __init__(self, c_code, defines=None, **defines2):
        super().__init__(defines, **defines2)
        self.c_code = c_code

    def _link_c_code(self, bin:Binary):
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

    def _build(self, bin:Binary, link_units:List[LinkUnit]):
        for incl_path in self.include_dirs:
            tcc_add_include_path(bin.tcc_state, c_str(incl_path))
        for sys_incl_path in self.sys_include_dirs:
            tcc_add_sysinclude_path(bin.tcc_state, c_str(sys_incl_path))
        for option in self.options:
            tcc_set_options(bin.tcc_state, c_str('-'+option))
        for def_name, def_val in self.defines.items():
            if def_val is None:
                tcc_define_symbol(bin.tcc_state, c_str(def_name), NULL)
            else:
                tcc_define_symbol(bin.tcc_state, c_str(def_name),
                                  c_str(str(def_val)))
        for link_unit in link_units:
            if isinstance(link_unit, str):
                CFile(link_unit).link_into(bin)
            else:
                link_unit.link_into(bin)

    def run(self, *link_units:List[Union[LinkUnit, str]]) -> int:
        with Binary(TCC_OUTPUT_MEMORY) as bin:
            self._build(bin, link_units)
            return tcc_run((<Binary>bin).tcc_state, 0, NULL)

    def load(self, *link_units:List[Union[LinkUnit, str]]) -> Binary:
        bin = Binary(TCC_OUTPUT_MEMORY)
        self._build(bin, link_units)
        r = tcc_relocate(bin.tcc_state, <void*>TCC_RELOCATE_AUTO)
        if r == -1:
            raise MemoryError('Error during Relocation of C Code')
        return bin
