import pytest
import pytcc

def test_init_withParams_ok():
    pytcc.TCC(dict(MACRO='1'), ['incl_dir'], ['sys_incl_dir'])

