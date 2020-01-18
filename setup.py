import os
from distutils.core import setup
from distutils.extension import Extension
from pathlib import Path
try:
    from Cython.Build import cythonize
except ImportError:
    def cythonize(ext, **argv): return ext

# This environment variable has to point to the build directory of cmake:
TCC_BUILD_DIR = Path(os.environ['TCC_BUILD_DIR'])
TINYCC_DIR = Path('tinycc')
RTLIB_DEST_DIR = Path('tcc-rtlib')

def collect_includes(src_path, dest_path):
    for src_incl_dir in Path(src_path).glob('**/'):
        dest_incl_dir = dest_path / src_incl_dir.relative_to(src_path)
        src_incl_files = src_incl_dir.glob('*.h')
        yield str(dest_incl_dir), list(map(str, src_incl_files))

setup(
    name='PyTCC',
    ext_modules = cythonize(
        [Extension(
            "pytcc",
            sources=["pytcc/pytcc.pyx"],
            libraries=['libtcc'],
            library_dirs=[str(TCC_BUILD_DIR)],
            include_dirs=[str(TINYCC_DIR)])],
        compiler_directives=dict(
            language_level=3)),
    data_files=[
        (str(RTLIB_DEST_DIR/'lib'), [str(TCC_BUILD_DIR/'rtlib/libtcc1-32.a')])]+
        list(collect_includes(TINYCC_DIR/'include', RTLIB_DEST_DIR/'include')) +
        list(collect_includes(TINYCC_DIR/'win32/include',
                              RTLIB_DEST_DIR/'include/win32'))
)
