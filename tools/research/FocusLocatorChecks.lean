import Main
import Eggshell.ContractAudit
open Lean Eggshell
namespace Eggshell.Research.FocusLocatorChecks
#print axioms SearchRank.Corpus.orderLocators_members
#print axioms SearchRank.Corpus.orderLocators_without_locators
#print axioms SearchRank.preferLiteralMatches_order
def check (accepted : Bool) (message : String) : IO Unit := unless accepted do throw (IO.userError message)
structure Row where
  owner : Nat
  positions : List Nat
  deriving BEq,ToJson
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous focus checks"
  IO.FS.createDirAll root
  let texts := ["common support head tail text", "mcp://team/case-17 case-17 original observation",
    "src/Driver.cpp identifier original source", "kernel-6.8 plain report", "커널 분석 original",
    "проект/ядро.cpp original", "設定.conf 原文", "café.txt original"]
  let corpus := SearchRank.Corpus.build texts
  let queries := ["support facts", "case-17.", "src/Driver.cpp", "kernel-6.8", "커널 분석",
    "проект/ядро.cpp", "設定.conf", "café.txt", "not-present-913", "case-17 and src/Driver.cpp"]
  let mut compared := 0
  for query in queries do
    for shift in [:texts.length] do
      for reverse in [false,true] do
        let indices := (List.range texts.length).drop shift ++ (List.range texts.length).take shift
        let indices := if reverse then indices.reverse else indices
        let rows := indices.map fun owner => ({owner,positions := [owner+3,owner+1,owner+7]} : Row)
        let named := (SearchRank.terms query).filter SearchRank.literalTerm
        let addressed := fun row : Row => (corpus.documents[row.owner]?).any fun terms => named.any terms.contains
        let expected := rows.filter addressed ++ rows.filter (fun row => !addressed row)
        let observed := corpus.orderLocators query (·.owner) rows
        check (observed == expected) "focus locator order differs from complete stable partition"
        check (observed.filter addressed == rows.filter addressed &&
          observed.filter (fun row => !addressed row) == rows.filter (fun row => !addressed row)) "focus changed lane order or window positions"
        check (observed.length == rows.length && rows.all observed.contains) "focus dropped or invented an owner"
        if named.isEmpty then check (observed == rows) "plain-language focus order changed"
        compared := compared+1
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("cases",toJson compared),
    ("ownerMembershipExact",toJson true),("positionsAndLaneOrderExact",toJson true),
    ("noLocatorOrderUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end Eggshell.Research.FocusLocatorChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["focus-locator-checks",root] => Eggshell.Research.FocusLocatorChecks.run (.mk root); return 0
  | ["front-traffic-audit",source] =>
      let reply ← IO.Process.output {
        cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
        args := #["front-traffic-audit",source]}
      IO.print reply.stdout
      IO.eprint reply.stderr
      return reply.exitCode
  | other => sourceRouteEngine other
