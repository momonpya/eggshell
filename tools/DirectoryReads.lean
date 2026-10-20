module

public import Eggshell.FileSystem

@[expose] public section
namespace Eggshell

/-- One request's directory objects, including failures. A later request
opens a fresh view; a local write invalidates its own directory entry. -/
structure DirectoryReads where
  directories : IO.Ref (Std.HashMap String (Except IO.Error FileSystem.ReadDirectory))

def DirectoryReads.new : IO DirectoryReads := do
  pure ⟨← IO.mkRef {}⟩

def DirectoryReads.open (reads : DirectoryReads) (path : System.FilePath) : IO FileSystem.ReadHandle := do
  let root := (path.parent.getD ".").toString
  let opened ← match (← reads.directories.get)[root]? with
    | some opened => pure opened
    | none => do
        let opened ← try pure (.ok (← FileSystem.openReadDirectory root))
          catch error => pure (.error error)
        reads.directories.modify (·.insert root opened)
        pure opened
  match opened with
  | .error error => throw error
  | .ok directory => FileSystem.openReadAt directory (path.fileName.getD "")

def DirectoryReads.invalidate (reads : DirectoryReads) (path : System.FilePath) : IO Unit :=
  reads.directories.modify (·.erase (path.parent.getD ".").toString)

end Eggshell
