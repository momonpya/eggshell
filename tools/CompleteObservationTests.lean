import Eggshell.Handoff

open Eggshell Eggshell.Plugin

private def observation (name source text : String) (lines : List Nat) : CompleteFileObservation :=
  {owner := .text name, source := source, lines := lines
   slice := {keys := [name], text, members := [], visibleKeys := []}}

def main : IO Unit := do
  unless observationLineHints "  350\tguard\n  371:compile\nplain\n123 no delimiter\n350\tguard" == [350, 371] do
    throw (IO.userError "Only original numbered stdout may contribute line hints")
  let long := String.ofList (List.replicate 60 'x')
  let scopeA := observation "a" "fingerprint-a" "guard\nexception\nconsequence" [350, 371, 392]
  let duplicate := observation "duplicate" "fingerprint-a" "guard" [350, 371]
  let distinct := observation "distinct" "fingerprint-b" "other-state" [350, 371]
  let tooLarge := observation "too-large" "fingerprint-a" long (List.range 12)
  let source := [tooLarge, scopeA, duplicate, distinct]
  let cost := fun (items : List TransportSlice) =>
    let text := "|".intercalate (items.map (·.text))
    (text.length, text.utf8ByteSize)
  let some picked := fitCompleteFileObservations 40 40 cost [] source |
    throw (IO.userError "Empty framed packet should fit")
  unless picked.val.map (·.val.owner) == [.text "a", .text "distinct"] do
    throw (IO.userError "Oversized observations must not spend coverage; duplicate source hints must not crowd another state")
  unless (picked.val.head?.map (·.val.slice.text)) == some scopeA.slice.text do
    throw (IO.userError "A complete observation lost its condition or consequence")
  let multibyte := observation "unicode" "state" "かな" [1]
  let some bytes := fitCompleteFileObservations 10 5 cost [] [multibyte] |
    throw (IO.userError "Empty Unicode packet should fit")
  unless bytes.val.isEmpty do
    throw (IO.userError "Character allowance cannot override the byte ceiling")
  IO.println "4 complete-observation checks passed"
