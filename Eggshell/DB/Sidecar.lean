module

public import Eggshell.DB.PageMap

@[expose] public section

namespace Eggshell.DB

/-- Rebuildable data belongs to the DB incarnation, outside its page map.
Moving/copying the DB retains it; removing the DB removes it with the owner. -/
structure Sidecar where
  database : String
  directory : System.FilePath
  semantic : System.FilePath
  indexes : System.FilePath

def Sidecar.ofSnapshot (snapshot : PageMap.Snapshot) : Sidecar :=
  let directory := snapshot.directory / "derived" / snapshot.head.identity
  { database := snapshot.head.identity, directory,
    semantic := directory / "semantic", indexes := directory / "indexes" }

end Eggshell.DB
