module
public import Eggshell.PluginHooks
public import Lean
@[expose] public section
open Eggshell Eggshell.Plugin Lean

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Deliberately independent executable specification; do not call the
compiler-substituted production declaration in this timing reference. -/
@[noinline] def referenceStep (keys : List String) (key : String) : List String :=
  match SourceEvidence.deliveryScope? key with
  | none => (keys ++ [key]).eraseDups
  | some scope =>
      (keys.filter (fun old => SourceEvidence.deliveryScope? old != some scope) ++ [key]).eraseDups

def main (args : List String) : IO Unit := do
  let [source,destination] := args | throw (IO.userError "DeliveryLedgerTests KEYS OUTPUT")
  let examples : List (List String × List String × List String) := [
    ([],[],[]),
    (["c:row","c:row"],[],["c:row","c:row"]),
    (["c:row","c:row"],["d:checkpoint","c:row"],["c:row","d:checkpoint"]),
    (["s:one:yes","d:checkpoint","s:two:no"],["s:one:no","c:row","s:one:yes"],
      ["d:checkpoint","s:two:no","c:row","s:one:yes"]),
    (["s::bad","s:one:","s:too:many:parts"],["s::bad","s:one:yes"],
      ["s::bad","s:one:","s:too:many:parts","s:one:yes"])]
  for (initial,added,expected) in examples do
    check (added.foldl referenceStep initial == expected) "reference fixture"
    check (added.foldl replaceSourceStatusFast initial == expected) "ordered status replacement"
  let bytes ← IO.FS.readBinFile (.mk source)
  let some text := String.fromUTF8? bytes | throw (IO.userError "input encoding")
  let keys ← IO.ofExcept (Json.parse text >>= fromJson? (α := List String))
  let started ← IO.monoMsNow
  let reference := keys.foldl referenceStep []
  let referenceMs := (← IO.monoMsNow) - started
  let started ← IO.monoMsNow
  let actual := keys.foldl replaceSourceStatusFast []
  let actualMs := (← IO.monoMsNow) - started
  check (actual == reference) "actual ledger differs from reference"
  check (actual == (addDeliveredGraphs ({profile := "work"} : ThreadState) keys).deliveredGraphs)
    "production delivery ledger differs"
  let result := Json.mkObj [("keys",toJson keys.length),("sameOrderedKeys",toJson true),
    ("inputSha256",toJson (Sha256.hex bytes)),("referenceMs",toJson referenceMs),
    ("actualMs",toJson actualMs),("cases",toJson examples.length)]
  IO.FS.writeFile (.mk destination) (result.compress ++ "\n")
  IO.println result.compress
