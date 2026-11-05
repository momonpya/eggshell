import Main
import Eggshell.ContractAudit
open Lean Eggshell
#print axioms Numerical.ready_foreign_scope_rejected
#print axioms Numerical.ready_foreign_generation_rejected
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def verifyReady (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve preceding readiness check"
  IO.FS.createDirAll root
  let endpoint : Plugin.Daemon.Endpoint := ⟨"fixture-generation",0,1,"fixture-secret","fixture-generation"⟩
  let generation := "fixture-generation"
  let file := root/"endpoint.json"
  let original ← Numerical.readyEndpoints.get
  try
    Numerical.readyEndpoints.set #[]
    Numerical.rememberReady root.toString generation endpoint
    check ((← Numerical.readyEndpoint? root.toString generation).isSome) "authenticated metadata not retained"
    check ((← Numerical.readyEndpoint? (root/"foreign").toString generation).isNone) "foreign scope accepted"
    check ((← Numerical.readyEndpoint? root.toString "foreign-generation").isNone) "foreign generation accepted"
    IO.FS.writeFile file (toJson endpoint).compress
    check ((← Numerical.publishedReady? root generation).isSome) "exact publication rejected"
    let replacement := {endpoint with secret := "replacement-secret",port := 2}
    IO.FS.writeFile file (toJson replacement).compress
    check ((← Numerical.publishedReady? root generation).isNone && (← Numerical.readyEndpoint? root.toString generation).isNone)
      "replaced publication retained stale hint"
    Numerical.rememberReady root.toString generation replacement
    Numerical.forgetReadyEndpoint endpoint
    check ((← Numerical.publishedReady? root generation).isSome) "old failure invalidated new endpoint"
    IO.FS.removeFile file
    check ((← Numerical.publishedReady? root generation).isNone && (← Numerical.readyEndpoint? root.toString generation).isNone)
      "retired publication retained stale hint"
    for index in [:40] do Numerical.rememberReady s!"scope-{index}" generation endpoint
    check ((← Numerical.readyEndpoints.get).size == 32) "metadata bound exceeded"
    Numerical.forgetReadyScope "scope-39" generation
    check ((← Numerical.readyEndpoint? "scope-39" generation).isNone && (← Numerical.readyEndpoint? "scope-38" generation).isSome)
      "scope retirement affected peer"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("foreignScopeRejected",toJson true),
      ("foreignGenerationRejected",toJson true),("exactPublishedIdentityRequired",toJson true),
      ("remoteRetirementInvalidatesHint",toJson true),("oldFailurePreservesReplacement",toJson true),
      ("metadataBound",toJson (32 : Nat)),("scopeRetirementPreservesPeer",toJson true),
      ("syntheticMetadataNotAuthenticationTest",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("adopted",toJson false)]).pretty
  finally Numerical.readyEndpoints.set original
def main (args : List String) : IO UInt32 := do
  let [root] := args | throw (IO.userError "readiness check root required")
  verifyReady (.mk root)
  return 0
