import tools.OwnedRows
import Lean.Data.Json

open Lean Eggshell

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

def main : IO UInt32 := do
  let mut checks := 0
  for count in [0, 1, 2, 8, 32, 257, 1024] do
    let original := (List.range count).map fun index => (index, index + 17)
    for rows in [original, original.reverse, original ++ original.reverse ++ [(0, 999), (2^60, 17)]] do
      let directory := FirstIndex.make Prod.fst rows
      let owned := OwnedRows.make rows
      for index in List.range (count + 2) ++ [2^60, 2^60 + 1] do
        check (directory.read index == rows.find? (·.1 == index)) "first-match index changed a value"
        check ((owned.get index).map Subtype.val == rows[index]?) "positional directory changed an original row"
        checks := checks + 2
    for failing in [0, 1, 7, 258] do
      let read : Nat → Except String (Option Nat) := fun index =>
        if index == failing then Except.error s!"rejected:{index}"
        else Except.ok (if index % 3 == 0 then none else some (index + 7))
      let items := List.range count
      let old : Except String (List Nat) := items.foldlM (fun values index => do
        match ← read index with
        | none => pure values
        | some value => pure (values ++ [value])) [123]
      let found : Except String (List Nat) := do let values ← items.filterMapM read; pure ([123] ++ values)
      let equal := match old, found with
        | .error first, .error second => first == second
        | .ok first, .ok second => first == second
        | _, _ => false
      check equal "collection changed order or first rejection"
      checks := checks + 1
  let rows := (List.range 50000).map fun index => (index, index + 1)
  let directory := FirstIndex.make Prod.fst rows
  for index in [0, 31, 49999, 50000, 2^60] do
    check (directory.read index == if index < 50000 then some (index, index + 1) else none)
      "large index changed a sparse/outside key"
  IO.println (Json.mkObj [("passed", toJson true), ("checks", toJson checks),
    ("largeDomain", toJson (50000 : Nat)), ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)]).compress
  pure 0
