#!python3.6
# -*- coding: utf-8 -*-
import os
from distutils.core import setup
from distutils.extension import Extension
from pathlib import Path
try:
    from Cython.Build import cythonize
except ImportError:
    def cythonize(ext, **argv): return ext

# TCC_BUILD_DIR can be used to link against alternative TCC library build.
# Please note that this path has to be absolute (or MANIFEST.in had
# to be adapted)
TCC_BUILD_DIR = Path(os.environ.get('TCC_BUILD_DIR','tinycc-bin/win32'))
TINYCC_DIR = Path('tinycc')
TCC_VERSION = (TINYCC_DIR / 'VERSION').read_text().strip()
PYTCC_VERSION =Path('PYTCC_VERSION').read_text().format(TCC_VERSION=TCC_VERSION)
RTLIB_DEST_DIR = Path('tcc-rtlib')

def collect_files(src_path, dest_path, glob):
    for src_incl_dir in Path(src_path).glob('**/'):
        dest_incl_dir = dest_path / src_incl_dir.relative_to(src_path)
        src_incl_files = src_incl_dir.glob(glob)
        yield str(dest_incl_dir), list(map(str, src_incl_files))

setup(
    name='pytcc',
    version=PYTCC_VERSION,
    description='A Python Wrapper for the API of the Tiny C Compiler (TCC)',
    long_description=Path('README.md').read_text(),
    long_description_content_type='text/markdown',
    author='Robert Hölzl',
    author_email='robert.hoelzl@posteo.de',
    url='https://github.com/mrh1997/pytcc',
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Operating System :: Microsoft :: Windows',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: C',
        'Topic :: Software Development :: Assemblers',
        'Topic :: Software Development :: Compilers',
    ],
    ext_modules = cythonize(
        [Extension(
            "pytcc",
            sources=["pytcc.pyx"],
            libraries=['libtcc'],
            library_dirs=[str(TCC_BUILD_DIR)],
            include_dirs=[str(TINYCC_DIR)])],
        compiler_directives=dict(
            language_level=3)),
    data_files=[
        (str(RTLIB_DEST_DIR/'lib'), [str(TCC_BUILD_DIR/'rtlib/libtcc1-32.a')])] +
        list(collect_files(TINYCC_DIR / 'win32/lib', RTLIB_DEST_DIR / 'lib', '*.def')) +
        list(collect_files(TINYCC_DIR / 'include', RTLIB_DEST_DIR / 'include', '*.h')) +
        list(collect_files(TINYCC_DIR / 'win32/include', RTLIB_DEST_DIR /'include/win32', '*.h'))
)
