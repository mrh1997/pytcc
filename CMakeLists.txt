# This file works currently only with win32!!!!
# To make this file work a python environemnt has to be setup via "tox" first

cmake_minimum_required(VERSION 3.15)
project (pytcc C)


# to find correct python interpreter run cmake when venv is activated or
# VIRTUAL_ENV environment var is set to path of venv
find_package(Python3 COMPONENTS Interpreter Development)


set(TCC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tinycc)

set(RTLIB_DIR ${CMAKE_CURRENT_BINARY_DIR}/rtlib)

file(READ ${TCC_DIR}/VERSION TCC_UNSTRIPPED_VERSION)
string(STRIP ${TCC_UNSTRIPPED_VERSION} TCC_VERSION)


file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/utils/get_arch.c "\
    int main(void) { return sizeof(void*) * 8; }")
try_run(TARGET_ARCHITECTURE _
    ${CMAKE_CURRENT_BINARY_DIR}/utils
    ${CMAKE_CURRENT_BINARY_DIR}/utils/get_arch.c)
if (${TARGET_ARCHITECTURE} EQUAL 32)
    set(TARGET_ARCHITECTURE_NAME   I386)
else()
    set(TARGET_ARCHITECTURE_NAME   X86_64)
endif()


################################################################################
# TCC compiler as library

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/tcc-config/config.h "\
    #define ONE_SOURCE 0 \n\
    #define TCC_TARGET_${TARGET_ARCHITECTURE_NAME} \n\
    #define TCC_TARGET_PE \n\
    #define TCC_VERSION \"${TCC_VERSION}\" \n\
    #define TCC_LIBTCC1 \"libtcc1-${TARGET_ARCHITECTURE}.a\" \n")
if (${TARGET_ARCHITECTURE} EQUAL 32)
    set(CODE_GENERATOR_SRCS
        ${TCC_DIR}/i386-gen.c
        ${TCC_DIR}/i386-link.c
        ${TCC_DIR}/i386-asm.c)
else()
    set(CODE_GENERATOR_SRCS
        ${TCC_DIR}/x86_64-gen.c
        ${TCC_DIR}/x86_64-link.c
        ${TCC_DIR}/i386-asm.c)
endif()
add_library(libtcc STATIC
    ${TCC_DIR}/libtcc.c
    ${TCC_DIR}/tccpp.c
    ${TCC_DIR}/tccgen.c
    ${TCC_DIR}/tccelf.c
    ${TCC_DIR}/tccasm.c
    ${TCC_DIR}/tccrun.c
    ${TCC_DIR}/tccpe.c
    ${CODE_GENERATOR_SRCS})
target_include_directories(libtcc
    PUBLIC ${TCC_DIR}
    PUBLIC ${CMAKE_CURRENT_BINARY_DIR}/tcc-config)
set_target_properties(libtcc PROPERTIES
    PREFIX ""
    ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_BINARY_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_BINARY_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_CURRENT_BINARY_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_CURRENT_BINARY_DIR}")


################################################################################
# TCC compiler as executable

add_executable(tcc ${TCC_DIR}/tcc.c)
target_link_libraries(tcc PRIVATE libtcc)


################################################################################
# Runtime Library (libtcc1-xx.a)

if (${TARGET_ARCHITECTURE} EQUAL 32)
    set(HEAPMGR_SRCS
        ${TCC_DIR}/lib/alloca86.S
        ${TCC_DIR}/lib/alloca86-bt.S)
else()
    set(HEAPMGR_SRCS
        ${TCC_DIR}/lib/alloca86_64.S
        ${TCC_DIR}/lib/alloca86_64-bt.S)
endif()
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
    ${HEAPMGR_SRCS})

# compile C files to object files
file(MAKE_DIRECTORY ${RTLIB_DIR})
foreach(RTLIB_SRCFILE ${RTLIB_SRCFILES})
    get_filename_component(RTLIB_SRCFILE_NOEXT ${RTLIB_SRCFILE} NAME_WE)
    add_custom_command(
        OUTPUT ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o
        COMMAND tcc -c
                    -I${TCC_DIR}/include
                    -I${TCC_DIR}/win32/include
                    -I${TCC_DIR}/win32/include/winapi
                    -o ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o
                    ${RTLIB_SRCFILE}
        MAIN_DEPENDENCY ${RTLIB_SRCFILE}
        COMMENT "Compiling Runtime Library (${RTLIB_SRCFILE})")
    list(APPEND RTLIB_OBJFILES ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o)
endforeach()

# link all objects files to archive file
add_custom_target(
    runtime-lib ALL
    tcc -ar ${RTLIB_DIR}/libtcc1-${TARGET_ARCHITECTURE}.a ${RTLIB_OBJFILES}
    DEPENDS ${RTLIB_OBJFILES}
    BYPRODUCTS ${RTLIB_DIR}/libtcc1-${TARGET_ARCHITECTURE}.a
    COMMENT "Linking Runtime Library"
    SOURCES ${RTLIB_SRCFILES})


################################################################################
# pytcc extension for debugging C code

execute_process(
    COMMAND ${Python3_EXECUTABLE} -m cython --version
    RESULT_VARIABLE Cython_TEST_ERRCODE)
if (${Cython_TEST_ERRCODE} EQUAL 0)
    # Cython Preprocessor Run
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/pytcc.c
        MAIN_DEPENDENCY src/pytcc.pyx
        COMMAND ${Python3_EXECUTABLE} -m cython -3 src/pytcc.pyx)

    # Compile Python Extension
    Python3_add_library(pytcc MODULE EXCLUDE_FROM_ALL
        ${CMAKE_CURRENT_SOURCE_DIR}/src/pytcc.c)
    target_link_libraries(pytcc PRIVATE
        libtcc)
endif()
