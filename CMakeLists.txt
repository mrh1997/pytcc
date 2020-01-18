# This file works currently only with win32!!!!
# To make this file work a python environemnt has to be setup via "tox" first

cmake_minimum_required(VERSION 3.14)
project (PyTCC C)


set(TCC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tinycc)
set(RTLIB_DIR ${CMAKE_CURRENT_BINARY_DIR}/rtlib)


################################################################################
# TCC compiler as library

file(READ ${TCC_DIR}/VERSION TCC_VERSION)
string(STRIP ${TCC_VERSION} TCC_VERSION)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/config.h "/*dummy config file*/")
add_library(libtcc STATIC
    ${TCC_DIR}/libtcc.c
    ${TCC_DIR}/tccpp.c
    ${TCC_DIR}/tccgen.c
    ${TCC_DIR}/tccelf.c
    ${TCC_DIR}/tccasm.c
    ${TCC_DIR}/tccrun.c
    ${TCC_DIR}/tccpe.c
    ${TCC_DIR}/i386-gen.c
    ${TCC_DIR}/i386-link.c
    ${TCC_DIR}/i386-asm.c)
target_include_directories(libtcc
    PUBLIC ${CMAKE_CURRENT_BINARY_DIR})
target_compile_definitions(libtcc
    PUBLIC ONE_SOURCE=0
    PUBLIC TCC_TARGET_I386=
    PUBLIC TCC_TARGET_PE=
    PUBLIC TCC_VERSION="${TCC_VERSION}"
    PUBLIC TCC_LIBTCC1=\"libtcc1-32.a\")


################################################################################
# TCC compiler as executable

add_executable(tcc ${TCC_DIR}/tcc.c)
target_link_libraries(tcc PUBLIC libtcc)


################################################################################
# Runtime Library (libtcc1-xx.a)

set(RTLIB_SRCFILES
    ${TCC_DIR}/lib/libtcc1.c
    ${TCC_DIR}/win32/lib/crt1.c
    ${TCC_DIR}/win32/lib/crt1w.c
    ${TCC_DIR}/win32/lib/wincrt1.c
    ${TCC_DIR}/win32/lib/wincrt1w.c
    ${TCC_DIR}/win32/lib/dllcrt1.c
    ${TCC_DIR}/win32/lib/dllmain.c
    ${TCC_DIR}/win32/lib/chkstk.S
    ${TCC_DIR}/lib/bcheck.c
    ${TCC_DIR}/lib/alloca86.S
    ${TCC_DIR}/lib/alloca86-bt.S)
file(MAKE_DIRECTORY ${RTLIB_DIR})
foreach(RTLIB_SRCFILE ${RTLIB_SRCFILES})
    get_filename_component(RTLIB_SRCFILE_NOEXT ${RTLIB_SRCFILE} NAME_WE)
    add_custom_command(
        OUTPUT ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o
        COMMAND tcc -c
                    -I${TCC_DIR}/win32/include
                    -I${TCC_DIR}/win32/include/winapi
                    -o ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o
                    ${RTLIB_SRCFILE}
        MAIN_DEPENDENCY ${RTLIB_SRCFILE}
        COMMENT "Compiling Runtime Library (${RTLIB_SRCFILE})")
    list(APPEND RTLIB_OBJFILES ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o)
endforeach()
add_custom_command(
    OUTPUT ${RTLIB_DIR}/libtcc1-32.a
    COMMAND tcc -ar ${RTLIB_DIR}/libtcc1-32.a ${RTLIB_OBJFILES}
    DEPENDS ${RTLIB_OBJFILES}
    COMMENT "Linking Runtime Library")
add_custom_target(
    runtime-lib
    ALL DEPENDS ${RTLIB_DIR}/libtcc1-32.a
    SOURCES ${RTLIB_SRCFILES})


################################################################################
# pytcc extension

set(PYTHON_DIR ${CMAKE_CURRENT_SOURCE_DIR}/.tox/py36)
execute_process(
    COMMAND ${PYTHON_DIR}/Scripts/python -c
                        "import sys; print(sys.real_prefix, end='')"
    OUTPUT_VARIABLE REAL_PYTHON_DIR)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/pytcc/pytcc.c
    MAIN_DEPENDENCY pytcc/pytcc.pyx
    COMMAND ${PYTHON_DIR}/Scripts/cython -3
                        ${CMAKE_CURRENT_SOURCE_DIR}/pytcc/pytcc.pyx)

add_library(pytcc SHARED pytcc/pytcc.c)
target_include_directories(pytcc
    PUBLIC ${REAL_PYTHON_DIR}/include
    PRIVATE ${TCC_DIR})
target_link_directories(pytcc
    PUBLIC ${REAL_PYTHON_DIR}/libs)
target_link_libraries(pytcc
    PUBLIC python36
    PRIVATE libtcc)
set_target_properties(pytcc PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${PYTHON_DIR}/Lib/site-packages
    PREFIX ""
    SUFFIX ".cp36-win32.pyd")
