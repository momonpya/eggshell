import Main

/-- The production entry dispatches only product commands. Research controllers
remain separate executables and do not initialize inside a hook process. -/
def main (arguments : List String) : IO UInt32 := sourceRouteEngine arguments

theorem product_entry_dispatch (arguments : List String) :
    main arguments = sourceRouteEngine arguments := rfl
