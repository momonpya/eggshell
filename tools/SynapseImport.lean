import Eggshell.SynapseImport

open Lean Eggshell Eggshell.Synapses

def main (args : List String) : IO Unit := do
  let mode :: database :: output :: recordings := args |
    throw (IO.userError "SynapseImport plan|apply DB REPORT RPC...")
  unless mode == "plan" || mode == "apply" do throw (IO.userError "expected plan or apply")
  unless !recordings.isEmpty do throw (IO.userError "frozen actual RPC recordings are required")
  let source ← DB.PageMap.pin (.mk database)
  let report ← Import.plan source (recordings.toArray.map System.FilePath.mk)
  IO.FS.writeFile (.mk output) (toJson report).compress
  let updated ← if mode == "apply" then Provenance.publish source report.origins else pure source
  let indexed ← if mode == "apply" then some <$> Build.refresh updated .database else pure none
  IO.println (Json.mkObj [("report", toJson report), ("head", toJson updated.head), ("indexed", toJson indexed)]).compress
