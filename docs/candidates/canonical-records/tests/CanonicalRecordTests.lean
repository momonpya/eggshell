import Eggshell.CanonicalSourceRecords
open Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def file : File := ⟨"src/example",String.ofList (List.replicate 64 'a'),1000⟩
private def row (line : Nat) (code : String) (source : File := file) : StoredRow :=
  ⟨⟨source,line⟩,code,#[]⟩
private def check (test : Bool) (message : String) : IO Unit :=
  unless test do throw (IO.userError message)

def main : IO Unit := do
  let rows := #[row 10 "",row 11 "if (one ||",row 12 "    two) {",row 13 "  result;",row 14 "}",row 15 "",
    row 30 "unrelated",row 31 ""]
  let records := Records.prepare rows
  check (!records.isEmpty) "an observed bounded record was lost"
  let closed := Records.close rows records [⟨1,by decide⟩]
  let numbers := ((closed.map (·.key.line)).toList.eraseDups.mergeSort (· ≤ ·)).toArray
  check (numbers == #[11,12,13,14])
    "a ranked condition was separated from its recorded consequence"
  let isolated := Records.close rows records [⟨6,by decide⟩]
  check (isolated.map (·.key.line) == #[30]) "unbounded data was broadened"
  let different := #[row 10 "",row 11 "start",row 12 "" {file with fingerprint := String.ofList (List.replicate 64 'b')}]
  check (Records.prepare different).isEmpty "paragraph crossed a file fingerprint"
  let gap := #[row 10 "",row 11 "start",row 13 ""]
  check (Records.prepare gap).isEmpty "paragraph crossed an unobserved line"
  let long := #[row 10 "",row 11 (String.ofList (List.replicate 2048 'x')),row 12 ""]
  check (Records.prepare long).isEmpty "unbounded paragraph escaped the source-context limit"
  let beginning := #[row 1 "start",row 2 "end",row 3 ""]
  check ((Records.prepare beginning).length == 1) "observed file beginning was lost"
  check (Records.close rows records []).isEmpty "empty demand invented a source cue"
  let continuation := #[row 9 "    prior;",row 10 "  if (first ||",row 11 "      second) {",
    row 12 "    consequence;",row 13 "  } else {"]
  let records := Records.prepare continuation
  let actual := Records.close continuation records [⟨1,by decide⟩]
  let numbers := ((actual.map (·.key.line)).toList.eraseDups.mergeSort (· ≤ ·)).toArray
  check (numbers == #[10,11,12]) "indented condition lost its consequence or crossed its closing boundary"
  IO.println "Lean bounded original-record closure checks passed"
