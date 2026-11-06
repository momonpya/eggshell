/-- Authorization consults immutable registration values after the registry
snapshot has been handed off. No mutable registry capability is accepted. -/
def resolveSource (sources : Array ReadSource) (secret database identity : String) : Except String ReadSource :=
  match sources.find? (fun source => source.database == database && source.scope == identity) with
  | none => .error "unknown prepared source scope"
  | some source => if source.capability == secret then .ok source
      else .error "unauthorized prepared source projection"

theorem resolveSource_present (sources : Array ReadSource) (secret database identity : String)
    (source : ReadSource)
    (found : sources.find? (fun source => source.database == database && source.scope == identity) = some source)
    (authorized : source.capability == secret) :
    resolveSource sources secret database identity = .ok source := by
  simp [resolveSource,found,authorized]

theorem resolveSource_foreign (sources : Array ReadSource) (secret database identity : String)
    (source : ReadSource)
    (found : sources.find? (fun source => source.database == database && source.scope == identity) = some source)
    (unauthorized : (source.capability == secret) = false) :
    resolveSource sources secret database identity = .error "unauthorized prepared source projection" := by
  simp [resolveSource,found,unauthorized]

theorem resolveSource_missing (sources : Array ReadSource) (secret database identity : String)
    (missing : sources.find? (fun source => source.database == database && source.scope == identity) = none) :
    resolveSource sources secret database identity = .error "unknown prepared source scope" := by
  simp [resolveSource,missing]

def scopedSource (server : Server) (secret : String) (payload : Json) : IO ReadSource := do
  let database ← IO.ofExcept (payload.getObjValAs? String "database")
  let identity ← IO.ofExcept (payload.getObjValAs? String "scope")
  let sources ← server.sources.atomically get
  IO.ofExcept (resolveSource sources secret database identity)

theorem scopedSource_snapshot_boundary (server : Server) (secret : String) (payload : Json) :
    scopedSource server secret payload = (do
      let database ← IO.ofExcept (payload.getObjValAs? String "database")
      let identity ← IO.ofExcept (payload.getObjValAs? String "scope")
      let sources ← server.sources.atomically get
      IO.ofExcept (resolveSource sources secret database identity)) := rfl
