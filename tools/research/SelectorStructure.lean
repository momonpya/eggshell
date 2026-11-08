import tools.research.SelectorFixture
def main (args : List String) : IO Unit := do
  let [mode,project,fixture,output] := args | throw (IO.userError "SelectorStructure prepare|choose PROJECT FIXTURE OUTPUT")
  SelectorStructure.check (["prepare","choose"].contains mode) "unknown structure diagnostic condition"
  SelectorStructure.run (mode == "choose") (.mk project) (.mk fixture) (.mk output)
