cmake_minimum_required(VERSION 3.15)
project (pytcc C)


# to find correct python interpreter run cmake when venv is activated or
# VIRTUAL_ENV environment var is set to path of venv
find_package(Python3 COMPONENTS Interpreter Development)

find_package (Threads)


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
if (WIN32)
    list (APPEND CODE_GENERATOR_SRCS   ${TCC_DIR}/tccpe.c)
endif()
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/tcc-config/config.h)
add_library(libtcc STATIC
    ${TCC_DIR}/libtcc.c
    ${TCC_DIR}/tccpp.c
    ${TCC_DIR}/tccgen.c
    ${TCC_DIR}/tccelf.c
    ${TCC_DIR}/tccasm.c
    ${TCC_DIR}/tccrun.c
    ${CODE_GENERATOR_SRCS})
target_compile_definitions(libtcc
    PRIVATE ONE_SOURCE=0
    PUBLIC "TCC_TARGET_${TARGET_ARCHITECTURE_NAME}="
    PUBLIC TCC_LIBTCC1=\"libtcc1-${TARGET_ARCHITECTURE}.a\"
    PRIVATE CONFIG_TCCDIR=\".\")
target_compile_definitions(libtcc PUBLIC
    TCC_VERSION=\"${TCC_VERSION}\")
if(WIN32)
    target_compile_definitions(libtcc PUBLIC
        "TCC_TARGET_PE=")
elseif (UNIX)
    target_compile_definitions(libtcc PUBLIC
        "CONFIG_USE_LIBGCC="
        CONFIG_TRIPLET=\"x86_64-linux-gnu\")
    target_link_libraries(libtcc PRIVATE
        dl ${CMAKE_THREAD_LIBS_INIT})
endif()
target_include_directories(libtcc
    PUBLIC ${TCC_DIR}
    PUBLIC ${CMAKE_CURRENT_BINARY_DIR}/tcc-config)
set_target_properties(libtcc PROPERTIES
    PREFIX ""
    POSITION_INDEPENDENT_CODE ON
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

set(RTLIB_SRCFILES
    ${TCC_DIR}/lib/libtcc1.c
    ${TCC_DIR}/lib/bcheck.c)
if (${TARGET_ARCHITECTURE} EQUAL 32)
    list (APPEND RTLIB_SRCFILES
        ${TCC_DIR}/lib/alloca86.S
        ${TCC_DIR}/lib/alloca86-bt.S)
elseif (${TARGET_ARCHITECTURE} EQUAL 64)
    list (APPEND RTLIB_SRCFILES
        ${TCC_DIR}/lib/alloca86_64.S
        ${TCC_DIR}/lib/alloca86_64-bt.S)
endif()
set (TCC_INCLUDE_DIRS -I${TCC_DIR}/include)
if (WIN32)
    list (APPEND RTLIB_SRCFILES
        ${TCC_DIR}/win32/lib/crt1.c
        ${TCC_DIR}/win32/lib/crt1w.c
        ${TCC_DIR}/win32/lib/wincrt1.c
        ${TCC_DIR}/win32/lib/wincrt1w.c
        ${TCC_DIR}/win32/lib/dllcrt1.c
        ${TCC_DIR}/win32/lib/dllmain.c
        ${TCC_DIR}/win32/lib/chkstk.S)
    list (APPEND TCC_INCLUDE_DIRS
            -I${TCC_DIR}/win32/include -I${TCC_DIR}/win32/include/winapi)
endif()

# compile C files to object files
file(MAKE_DIRECTORY ${RTLIB_DIR})
foreach(RTLIB_SRCFILE ${RTLIB_SRCFILES})
    get_filename_component(RTLIB_SRCFILE_NOEXT ${RTLIB_SRCFILE} NAME_WE)
    add_custom_command(
        OUTPUT ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o
        COMMAND tcc ${TCC_INCLUDE_DIRS}
                    -L ${RTLIB_DIR}
                    -c ${RTLIB_SRCFILE}
                    -o ${RTLIB_DIR}/${RTLIB_SRCFILE_NOEXT}.o
        MAIN_DEPENDENCY ${RTLIB_SRCFILE}
        VERBATIM
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
        MAIN_DEPENDENCY ${CMAKE_CURRENT_SOURCE_DIR}/src/pytcc.pyx
        OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/src/pytcc.c
        COMMAND ${Python3_EXECUTABLE} -m cython -3
                       ${CMAKE_CURRENT_SOURCE_DIR}/src/pytcc.pyx)

    # Compile Python Extension
    Python3_add_library(pytcc MODULE EXCLUDE_FROM_ALL
        ${CMAKE_CURRENT_SOURCE_DIR}/src/pytcc.c)
    target_link_libraries(pytcc PRIVATE
        libtcc)
endif()
