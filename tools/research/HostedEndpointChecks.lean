import Eggshell.PublicationClient
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.HostedEndpointChecks
#print axioms Publication.Client.hosted_same_owner
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def refused (action : IO α) : IO Bool := do try let _ ← action; return false catch _ => return true
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous hosted endpoint check"
  IO.FS.createDirAll root
  let endpoint : Daemon.Endpoint := {
    session := "publisher",pid := (← IO.Process.getPID).toNat,port := 0,
    secret := String.ofList (List.replicate 64 '0'),generation := ← Publication.generation}
  check (← refused (Publication.Client.registerHosted {endpoint with pid := endpoint.pid+1}))
    "foreign process installed a hosted endpoint"
  check (← refused (Publication.Client.registerHosted {endpoint with generation := "foreign"}))
    "another implementation installed a hosted endpoint"
  Publication.Client.registerHosted endpoint
  let started ← IO.monoMsNow
  try
    check (← refused (Publication.Client.registerHosted endpoint)) "second owner replaced active hosted endpoint"
    check (← refused (Publication.Client.unregisterHosted {endpoint with secret := "foreign"}))
      "foreign token retired hosted endpoint"
    let tasks ← (List.range 80).toArray.mapM fun _ => IO.asTask (do
      for _ in [:128] do
        let found ← Publication.Client.resolve
        check (found.pid == endpoint.pid && found.port == 0 && found.secret == endpoint.secret &&
          found.generation == endpoint.generation) "hosted resolution changed immutable owner") .dedicated
    for task in tasks do IO.ofExcept (← IO.wait task)
  finally Publication.Client.unregisterHosted endpoint
  check ((← Publication.Client.hostedOwner.atomically get).isNone) "hosted owner was not retired"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("parallelClients",toJson (80 : Nat)),
    ("resolutionsPerClient",toJson (128 : Nat)),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("noListenerAtTestEndpoint",toJson true),("foreignProcessAndImplementationRejected",toJson true),
    ("duplicateOwnerAndForeignRetirementRejected",toJson true),("ownerRetired",toJson true),
    ("actualHookCapacityTested",toJson false),("adopted",toJson false)]).pretty
end Eggshell.Research.HostedEndpointChecks
