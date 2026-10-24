import Eggshell.Warm

open Lean Eggshell

def main (args : List String) : IO Unit := do
  let [path,binary] := args | throw (IO.userError "EmptyMatrixWarmCheck NEW-DB CANDIDATE")
  let path := System.FilePath.mk path
  if ← path.pathExists then throw (IO.userError "keep prior empty-warm check")
  let source ← DB.PageMap.create path (Persistence.valueToJson (.text "empty matrix warm")).compress
  let command := [binary,"search-provider"]
  let first ← Warm.run source command false
  let target ← Plugin.registerIndexTarget source command false
  unless first.after.windows == 0 && first.requested == 0 && !(← Warm.required target source) do
    throw (IO.userError "empty publication repeated numerical maintenance")
  let repeated ← Warm.run source command false
  unless repeated.after.windows == 0 && repeated.requested == 0 && !(← Warm.required target source) do
    throw (IO.userError "repeated empty warm did not settle")
  IO.println (Json.mkObj [("emptyPublicationSettles",toJson true),
    ("sourceEncodings",toJson (first.requested + repeated.requested)),
    ("firstMs",toJson first.elapsedMs),("repeatMs",toJson repeated.elapsedMs),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
