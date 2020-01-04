import pytest
import pytcc
import ctypes as ct
import subprocess
import platform
import os
from pathlib import Path


@pytest.fixture
def tcc():
    return pytcc.TCC()


class TestCompileError:

    exc = pytcc.CompileError('dir/subdir/name.c:123: error: text and more text')

    def test_filename(self):
        assert self.exc.filename == 'dir/subdir/name.c'

    def test_lineno(self):
        assert self.exc.lineno == 123

    def test_type(self):
        assert self.exc.type == 'error'

    def test_text(self):
        assert self.exc.text == 'text and more text'


class TestTcc:

    SIMPLE_LINK_UNIT = pytcc.CCode('int main(void) { return 1; }')

    def run(self, tcc, *link_units, args=()):
        bin = tcc.build_to_mem(*link_units)
        return bin.run(*args)

    def test_init_withParams_setsAttributes(self):
        tcc = pytcc.TCC('opt1', 'opt2', options=['opt3'],
                        include_dirs=['incl_dir'],
                        sys_include_dirs=['sys_incl_dir'],
                        library_dirs=['lib_dir'],
                        defines=dict(A='1'), B='2')
        assert tcc.options == ['opt1', 'opt2', 'opt3']
        assert tcc.defines == dict(A='1', B='2')
        assert tcc.include_dirs == ['incl_dir']
        assert tcc.sys_include_dirs == ['sys_incl_dir']
        assert tcc.library_dirs == ['lib_dir']

    def test_buildToMem_onCCode_executesMain(self, tcc):
        link_unit = pytcc.CCode("int main(void) { return(123456); }")
        assert self.run(tcc, link_unit) == 123456

    def test_buildToMem_onCFile_loadsFile(self, tcc, tmpdir):
        filename = tmpdir.join('filename.c')
        filename.write("int main(void) { return(123456); }")
        assert self.run(tcc, pytcc.CFile(str(filename))) == 123456

    def test_buildToMem_onStr_loadsFile(self, tcc, tmpdir):
        filename = tmpdir.join('filename.c')
        filename.write("int main(void) { return(123456); }")
        assert self.run(tcc, str(filename)) == 123456

    def test_buildToMem_onMultipleLinkUnits_combinesLinkUnits(self, tcc):
        link_unit1 = pytcc.CCode("extern int f(); int main() {return(f());}")
        link_unit2 = pytcc.CCode("int f() { return(4321); }")
        assert self.run(tcc, link_unit1, link_unit2) == 4321

    def test_buildToMem_returnsOpenedAndNotRelocatInMemBinary(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode(''))
        assert not binary.closed
        assert not binary.relocated

    def test_buildToMem_onEagerIsTrue_returnsOpenedAndRelocatInMemBinary(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode(''), eager=True)
        assert not binary.closed
        assert binary.relocated

    def test_buildToMem_onDefines_compilesWithDefines(self, tcc):
        link_unit = pytcc.CCode("int main(void) { return(DEF1 + DEF2); }",
                                {'DEF1': '12'}, DEF2=34)
        assert self.run(tcc, link_unit) == 12 + 34

    def test_buildToMem_onEmptyDefine_setsDefineTo1(self, tcc):
        link_unit = pytcc.CCode('#if DEF!=1\n#error B\n#endif\n',
                                DEF=None)
        tcc.build_to_mem(link_unit)

    def test_buildToMem_onLinkUnitsWithDifferentDefines_compilesWithDifferentDefines(self, tcc):
        link_unit1 = pytcc.CCode("#ifdef A\n#error A defined\n#endif", B='1')
        link_unit2 = pytcc.CCode("#ifdef B\n#error B defined\n#endif", A='1')
        tcc.build_to_mem(link_unit1, link_unit2)

    def test_buildToMem_onTccDefine_compilesWithDefines(self):
        tcc = pytcc.TCC(defines={'DEF1': '12'}, DEF2=34)
        link_unit = pytcc.CCode("int main(void) { return(DEF1 + DEF2); }")
        assert self.run(tcc, link_unit) == 12 + 34

    def test_buildToMem_onLinkUnitDefineOverwritesTccDefine_restoresTccDefineAfterLinkUnit(self):
        tcc = pytcc.TCC(DEF=1)
        link_unit1 = pytcc.CCode("#if DEF!=2\n#error inv. DEF\n#endif", DEF=2)
        link_unit2 = pytcc.CCode("#if DEF!=1\n#error inv. DEF\n#endif")
        tcc.build_to_mem(link_unit1, link_unit2)

    def test_buildToMem_onTccIncludeDir_ok(self, tmpdir):
        tcc = pytcc.TCC(include_dirs=[str(tmpdir)])
        tmpdir.join('incl.h').write('#define DEF  123')
        link_unit = pytcc.CCode('#include "incl.h"\n'
                                'int main(void) { return(DEF); }')
        assert self.run(tcc, link_unit) == 123

    def test_buildToMem_onTccSysIncludeDir_ok(self, tmpdir):
        tcc = pytcc.TCC(sys_include_dirs=[str(tmpdir)])
        tmpdir.join('incl.h').write('#define DEF  123')
        link_unit = pytcc.CCode('#include "incl.h"\n'
                                'int main(void) { return(DEF); }')
        assert self.run(tcc, link_unit) == 123

    def test_buildToMem_onOptions_ok(self):
        tcc = pytcc.TCC('-Werror')
        link_unit = pytcc.CCode('#define REDEF 1\n'
                                '#define REDEF 2\n')    # causes warning
        with pytest.raises(pytcc.CompileError):
            tcc.build_to_mem(link_unit)

    def test_buildToMem_onError_passesErrorInCompileErrorExc(self, tcc):
        link_unit = pytcc.CCode("#error ERRORMSG")
        with pytest.raises(pytcc.CompileError, match="ERRORMSG"):
            tcc.build_to_mem(link_unit)

    def test_buildToMem_returnsOpenedBinaryWithNoWarnings(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int var;'))
        assert not binary.closed
        assert binary.warnings == []

    def test_buildToMem_onWarnings_storesWarningsInBinaryMsgs(self, tcc):
        link_unit = pytcc.CCode('#define REDEF 1\n'
                                '#define REDEF 2\n'    # causes warning
                                '#define REDEF 3\n')   # causes warning
        binary = tcc.build_to_mem(link_unit)
        assert len(binary.warnings) == 2 and 'REDEF' in binary.warnings[0]

    def test_buildToExe_createsExecutableFile(self, tcc, tmp_path):
        if platform.system() == 'Windows':
            filename = tmp_path / 'program.exe'
        else:
            filename = tmp_path / 'program'
        link_unit = pytcc.CCode('int main(void) { return 123; }')
        tcc.build_to_exe(filename, link_unit)
        assert subprocess.call(str(filename)) == 123

    def test_buildToExe_addsExeSuffixToReturnedFilename(self, tcc, tmp_path):
        exe_binary = tcc.build_to_exe(tmp_path/'program', self.SIMPLE_LINK_UNIT)
        assert exe_binary.filename.suffix == '.exe'

    def test_buildToExe_makesReturnedFilenameAbsolute(self, tcc, tmp_path):
        original_path = Path.cwd()
        os.chdir(tmp_path)
        try:
            exe_binary = tcc.build_to_exe('program', self.SIMPLE_LINK_UNIT)
        finally:
            os.chdir(original_path)
        assert exe_binary.filename.parent == tmp_path

    def test_buildToExe_withAutoAddSuffixSetToFalse_doesNotAddExeSuffix(self, tcc, tmp_path):
        exe_binary = tcc.build_to_exe(tmp_path/'program', self.SIMPLE_LINK_UNIT,
                                      auto_add_suffix=False)
        assert exe_binary.filename.suffix == ''

    def test_buildToLib_createsDynamicLibraryFile(self, tcc, tmp_path):
        if platform.system() == 'Windows':
            filename = tmp_path / 'library.dll'
        elif platform.system() == 'Darwin':
            filename = tmp_path / 'program.dylib'
        else:
            filename = tmp_path / 'program.so'
        link_unit = pytcc.CCode('__attribute__((dllexport)) int func(void);\n'
                                'int func(void) { return 123; }')
        tcc.build_to_lib(filename, link_unit)
        dll = ct.CDLL(str(filename))
        assert dll.func() == 123

    def test_buildToLib_onDynamicOption_exportsAllSymbols(self, tmp_path):
        filename = tmp_path / 'library.dll'
        link_unit = pytcc.CCode('int func(void) { return 123; }')
        tcc = pytcc.TCC('-rdynamic')
        tcc.build_to_lib(filename, link_unit)
        dll = ct.CDLL(str(filename))
        assert dll.func() == 123

    def test_buildToLib_addsDllSuffixToReturnedFilename(self, tcc, tmp_path):
        dll_binary = tcc.build_to_lib(tmp_path/'library', pytcc.CCode(''))
        assert dll_binary.filename.suffix == '.dll'

    def test_buildToLib_makesReturnedFilenameAbsolute(self, tcc, tmp_path):
        original_path = Path.cwd()
        os.chdir(tmp_path)
        try:
            dll_binary = tcc.build_to_lib(tmp_path/'library', pytcc.CCode(''))
        finally:
            os.chdir(original_path)
        assert dll_binary.filename.parent == tmp_path

    def test_buildToLib_withAutoAddSuffixSetToFalse_doesNotAddSuffix(self, tcc, tmp_path):
        exe_binary = tcc.build_to_lib(tmp_path/'library', pytcc.CCode(''),
                                      auto_add_suffix=False)
        assert exe_binary.filename.suffix == ''


class TestInMemBinary:

    def test_contains_onExistingSymbol_returnsTrue(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int var;'))
        assert 'var' in binary

    def test_contains_onNonExistingSymbol_returnsFalse(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int var;'))
        assert 'non_existing_var' not in binary

    def test_getitem_onExistingSymbol_returnsAddress(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int var = 1234;'))
        var_obj = ct.c_int.from_address(binary['var'])
        assert var_obj.value == 1234

    def test_getitem_onNonExistingSymbol_raisesKeyError(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int var;'))
        with pytest.raises(KeyError):
            _ = binary['non_existing_var']

    def test_getitem_onFunc_returnsCallableCFunc(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int func(int a, int b) '
                                              '{return (a+b);}'))
        func_t = ct.CFUNCTYPE(ct.c_int, ct.c_int, ct.c_int)
        func_obj = func_t(binary['func'])
        assert func_obj(123, 456) == 123 + 456

    def test_getItem_onClosedBinary_raisesValueError(self, tcc):
        binary = tcc.build_to_mem(pytcc.CCode('int var;'))
        binary.close()
        with pytest.raises(ValueError):
            _ = binary['var']

    def test_contextMgr_closesAtContextEnd(self, tcc):
        with tcc.build_to_mem() as binary:
            assert not binary.closed
        assert binary.closed
