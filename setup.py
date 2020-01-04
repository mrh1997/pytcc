from distutils.core import setup
from distutils.extension import Extension
import os
try:
    from Cython.Build import cythonize
except ImportError:
    def cythonize(ext, **argv): return ext

def to_tinycc_path(p):
    return os.path.join(TCC_SRC_DIR, p)

TCC_SRC_DIR = 'tinycc'
TCC_VERSION = open(to_tinycc_path('VERSION'), 'rt').read().strip()

TCC_CORE_FILES = list(map(to_tinycc_path, [
    'libtcc.c',
    'tccpp.c',
    'tccgen.c',
    'tccelf.c',
    'tccpe.c',
    'tccasm.c',
    'tccrun.c']))

TCC_I386_FILES = list(map(to_tinycc_path, [
    'i386-gen.c',
    'i386-link.c',
    'i386-asm.c']))

open(to_tinycc_path('config.h'), 'wt').write('/* generated dummyfile */')

setup(
    name='PyTCC',
    ext_modules = cythonize(
        [Extension(
            "pytcc",
            sources=["pytcc/pytcc.pyx"] + TCC_CORE_FILES + TCC_I386_FILES,
            define_macros=[('ONE_SOURCE', '0'),
                           ('TCC_TARGET_I386', None),
                           ('TCC_TARGET_PE', None),
                           ('TCC_VERSION', r'\"{}\"'.format(TCC_VERSION)),
                           ('TCC_LIBTCC1', r'\"libtcc1-32.a\"'),],
            include_dirs=['tinycc'])],
        compiler_directives=dict(
            language_level=3)
    ),
)
