from typing import List, Dict, Optional
from sys import getdefaultencoding


TCC_OUTPUT_MEMORY =      1 # output will be run in memory (default)
TCC_OUTPUT_EXE =         2 # executable file
TCC_OUTPUT_DLL =         3 # dynamic library
TCC_OUTPUT_OBJ =         4 # object file
TCC_OUTPUT_PREPROCESS =  5 # only preprocess (used internally)

TCC_RELOCATE_AUTO = 1

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


cdef char * c_str(s:str) except NULL:
    return str.encode(getdefaultencoding())

cdef class TCC:
    cdef TCCState * tcc_state;

    def __init__(self, macros:Dict[str, Optional[str]]={},
                 incl_paths:List[str]=[], sys_incl_paths:List[str]=[]):
        """
        @param macros
        """
        self.tcc_state = tcc_new()
        for incl_path in incl_paths:
            tcc_add_include_path(self.tcc_state, c_str(incl_path))
        for sys_incl_path in sys_incl_paths:
            tcc_add_include_path(self.tcc_state, c_str(sys_incl_path))
        for m_name, m_val in macros.items():
            m_val_cstr = c_str(str(m_val)) if m_val is not None else None
            tcc_define_symbol(self.tcc_state, c_str(m_name), m_val_cstr)

    def __del__(self):
        tcc_delete(self.tcc_state)