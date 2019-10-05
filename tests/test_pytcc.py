import pytest
import pytcc


# class CFile:
#
#     def test_init_onDefines_mergesDefines(self):
#         tu = pytcc.TransUnit({'a': 1, 'b': 2}, c=3, d=4)
#         assert tu.defines == dict(a=1, b=2, c=3, d=4)
#
#     def test_


@pytest.fixture
def tcc():
    return pytcc.TCC()


def test_init_withParams_setsAttributes():
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

def test_run_onCCodeString_executesMain(tcc):
    link_unit = pytcc.CCodeString("int main(void) { return(123456); }")
    assert tcc.run(link_unit) == 123456

def test_run_onCCodeFile_loadsFile(tcc, tmpdir):
    filename = tmpdir.join('filename.c')
    filename.write("int main(void) { return(123456); }")
    assert tcc.run(pytcc.CCodeFile(str(filename))) == 123456

def test_run_onStr_loadsFile(tcc, tmpdir):
    filename = tmpdir.join('filename.c')
    filename.write("int main(void) { return(123456); }")
    assert tcc.run(str(filename)) == 123456

def test_run_onMultipleLinkUnits_combinesLinkUnits(tcc):
    link_unit1 = pytcc.CCodeString("extern int f(); int main() {return(f());}")
    link_unit2 = pytcc.CCodeString("int f() { return(4321); }")
    assert tcc.run(link_unit1, link_unit2) == 4321

def test_run_onDefines_compilesWithDefines(tcc):
    link_unit = pytcc.CCodeString("int main(void) { return(DEF1 + DEF2); }",
                                  {'DEF1': '12'}, DEF2=34)
    assert tcc.run(link_unit) == 12 + 34

def test_run_onEmptyDefine_setsDefineTo1(tcc):
    link_unit = pytcc.CCodeString("#if DEF!=1\n#error B\n#endif\n"
                                  "void main(void) {return;}",
                                  DEF=None)
    tcc.run(link_unit)

def test_run_onLinkUnitsWithDifferentDefines_compilesWithDifferentDefines(tcc):
    link_unit1 = pytcc.CCodeString("#ifdef A\n#error A defined\n#endif", B='1')
    link_unit2 = pytcc.CCodeString("#ifdef B\n#error B defined\n#endif", A='1')
    link_unit3 = pytcc.CCodeString("void main(void) { return; }")
    tcc.run(link_unit1, link_unit2, link_unit3)
