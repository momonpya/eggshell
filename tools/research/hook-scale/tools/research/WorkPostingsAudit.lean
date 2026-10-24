import Eggshell.WorkPostings
import Eggshell.Matcher
open Lean Eggshell Eggshell.Persistence.Store

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [path,output] := args | throw (IO.userError "WorkPostingsAudit DB OUTPUT")
  let source ← DB.PageMap.pin (.mk path)
  let some domain ← CandidateDomain.openShared? source |
    throw (IO.userError "ready source domain required")
  let started ← IO.monoMsNow
  let prepared ← WorkPostings.refresh source .user
  let some index ← WorkPostings.openShared? source domain | throw (IO.userError "prepared postings missing")
  let buildMs := (← IO.monoMsNow)-started
  let queries := ["", "kernel realtime clock monotonic scheduling elapsed timers",
    "source 0 1 9968", "no-such-quantum-xyz", "日本語 커널 café",
    "exec_command\n{\"cmd\":\"cat arbitrary.json\"}", "kernel kernel clock"]
  let mut records := []
  for query in queries do
    let surfaces := LogicalText.surfaceNames query
    let reference ← workSurfaceCandidates source surfaces
    let begin ← IO.monoMsNow
    let actual ← WorkPostings.candidates index surfaces
    let elapsed := (← IO.monoMsNow)-begin
    let expected := domain.data.rows.filter fun row =>
      (LogicalText.surfaceNames row.text).any surfaces.contains
    check (actual == reference && actual == expected.map (·.owner))
      "packed Work postings changed the complete original nomination order"
    records := Json.mkObj [("query",toJson query),("owners",toJson actual.length),
      ("elapsedMs",toJson elapsed)] :: records
  -- A batch is compared with the independently invoked original point reader,
  -- including words absent from the published dictionary.
  let terms := hashDistinct ((domain.data.rows.take 128).flatMap fun row =>
    (LogicalText.logical row.text).units.map (·.text)) ++ ["absent-term-for-frequency-audit"]
  let batch ← frequencies source terms
  for term in terms do
    check (batch.contains term && batch.getD term 0 == (← frequency source term))
      "batched frequencies differ from original point reads"
  let folder ← WorkPostings.directory source .user
  let payload ← IO.FS.readBinFile (folder / "postings")
  let manifest ← IO.FS.readBinFile (folder / "ready.json")
  try
    FileSystem.atomicExistingBytes (folder / "postings") (payload ++ "damage".toUTF8)
    check ((← try WorkPostings.open? source domain .user catch _ => pure none).isNone)
      "corrupted Work postings accepted"
    FileSystem.atomicExistingBytes (folder / "postings") payload
    let stale ← IO.ofExcept (Json.parse ((String.fromUTF8? manifest).getD "") >>= fromJson? (α := WorkPostings.Manifest))
    FileSystem.atomicExistingBytes (folder / "ready.json")
      (toJson ({stale with domain := "different-domain"} : WorkPostings.Manifest)).compress.toUTF8
    check ((← WorkPostings.open? source domain .user).isNone) "foreign domain stamp accepted"
  finally
    FileSystem.atomicExistingBytes (folder / "postings") payload
    FileSystem.atomicExistingBytes (folder / "ready.json") manifest
  check ((← WorkPostings.refresh source .user).mode == "warm") "unchanged postings rebuilt"
  check ((← DB.PageMap.pin (.mk path)).head == source.head) "audit changed source publication"
  let result := Json.mkObj [("rows",toJson domain.data.rows.length),
    ("prepareAndOpenMs",toJson buildMs),("prepared",toJson prepared),("queries",toJson records.reverse),
    ("frequencyTerms",toJson terms.length),("completeOrderedPostingsEqual",toJson true),
    ("corruptionAndForeignDomainRejected",toJson true),("idempotentWarm",toJson true),
    ("sourceUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (.mk output) result.pretty
  IO.println result.compress
