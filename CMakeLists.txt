# This file works currently only with win32!!!!
# To make this file work a python environemnt has to be setup via "tox" first

cmake_minimum_required(VERSION 3.14)
project (PyTCC C)

set(PYTHON_DIR ${CMAKE_CURRENT_SOURCE_DIR}/.tox/py36)
execute_process(
    COMMAND ${PYTHON_DIR}/Scripts/python -c "import sys; print(sys.real_prefix, end='')"
    OUTPUT_VARIABLE REAL_PYTHON_DIR)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/pytcc/pytcc.c
    MAIN_DEPENDENCY pytcc/pytcc.pyx
    COMMAND ${PYTHON_DIR}/Scripts/cython -3
                        ${CMAKE_CURRENT_SOURCE_DIR}/pytcc/pytcc.pyx)

add_library(pytcc SHARED
    pytcc/pytcc.c
    tinycc/tcc.c
    tinycc/libtcc.c
    tinycc/tccpp.c
    tinycc/tccgen.c
    tinycc/tccelf.c
    tinycc/tccasm.c
    tinycc/tccrun.c
    tinycc/i386-gen.c
    tinycc/i386-link.c
    tinycc/i386-asm.c)
add_compile_definitions(tcc
    "NDEBUG="
    ONE_SOURCE=0
    TCC_TARGET_I386=
    TCC_VERSION="1.2.3"
    TCC_LIBTCC1=\"libtcc1-32.a\")
target_include_directories(pytcc
    PUBLIC ${REAL_PYTHON_DIR}/include
    PRIVATE tinycc)
target_link_directories(pytcc
    PUBLIC ${REAL_PYTHON_DIR}/libs)
target_link_libraries(pytcc
    PUBLIC python36)
set_target_properties(pytcc PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${PYTHON_DIR}/Lib/site-packages
    PREFIX ""
    SUFFIX ".cp36-win32.pyd")
