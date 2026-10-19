import os
from pathlib import Path

import itsdangerous


def test_the_evaluator_imports_the_actual_candidate():
    source = Path(os.environ["EGGSHELL_PILOT_SOURCE"]).resolve() / "src"
    assert Path(itsdangerous.__file__).resolve().is_relative_to(source)
