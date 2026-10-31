def sourcePalette (reference : SourceReference) (owners : Array String) (deadline : Nat) :
    IO Synapses.OwnerPalette.Projection := do
  let access := reference.access
  let owners := (hashDistinct owners.toList).toArray
  let budget ← liveBudget deadline
  let response ← Stream.exchange reference.endpoint "source-palette" (Json.mkObj [
    ("database",toJson access.database),("scope",toJson access.scope),("source",toJson access.source),
    ("metadata",toJson access.metadata),("owners",toJson owners),("budgetMs",toJson budget)]) budget
  let result ← IO.ofExcept (Json.parse response >>= fromJson? (α := Synapses.OwnerPalette.Projection))
  unless result.identity == reference.identity && Synapses.digest result.lease && result.owners.map Prod.fst == owners &&
      result.owners.all (fun (owner,descriptor) => descriptor.inScope access.database owner) do
    throw (IO.userError "original palette changed its immutable scope or owner domain")
  return result

def releaseSourcePalette (reference : SourceReference) (lease : String) (deadline : Nat) : IO Unit := do
  if (← IO.monoMsNow) ≥ deadline then return
  let budget := min 1000 (← liveBudget deadline)
  let response ← Daemon.exchange reference.endpoint "source-release" (Json.mkObj [
    ("database",toJson reference.access.database),("scope",toJson reference.access.scope),
    ("lease",toJson lease),("budgetMs",toJson budget)]) (budget := budget)
  unless response == "true" do throw (IO.userError "original palette release was not acknowledged")

def withSourcePalette (reference : SourceReference) (owners : Array String) (deadline : Nat)
    (use : Synapses.OwnerPalette.Projection → IO α) : IO α := do
  let palette ← sourcePalette reference owners deadline
  try use palette
  finally releaseSourcePalette reference palette.lease deadline

def sourceFetch (reference : SourceReference) (palette : Synapses.OwnerPalette.Projection)
    (requests : Array Synapses.OwnerPalette.Fetch) (deadline : Nat) : IO Synapses.OwnerPalette.Reply := do
  let access := reference.access
  unless palette.identity == reference.identity do throw (IO.userError "original palette belongs to another view")
  let directory := Std.HashMap.ofArray palette.owners
  for request in requests do
    let some descriptor := directory[request.owner]? | throw (IO.userError "selected owner has no original palette")
    unless request.indices.all (· < descriptor.rows.size) do throw (IO.userError "selected original index is out of bounds")
  let budget ← liveBudget deadline
  let response ← Stream.exchange reference.endpoint "source-fetch" (Json.mkObj [
    ("database",toJson access.database),("scope",toJson access.scope),("source",toJson access.source),
    ("metadata",toJson access.metadata),("lease",toJson palette.lease),
    ("requests",toJson requests),("budgetMs",toJson budget)]) budget
  let result ← IO.ofExcept (Json.parse response >>= fromJson? (α := Synapses.OwnerPalette.Reply))
  unless result.identity == reference.identity &&
      result.parts.map (fun part => (part.owner,part.indices)) == requests.map (fun request => (request.owner,request.indices)) do
    throw (IO.userError "selected original reply changed its requested identities")
  for part in result.parts do
    let some descriptor := directory[part.owner]? | throw (IO.userError "selected original owner disappeared")
    unless part.rows.size == part.indices.size &&
        (part.indices.zip part.rows).all (fun (index,row) => descriptor.matches index row) do
      throw (IO.userError "selected original differs from its prepared coordinates or cost")
    let _ ← IO.ofExcept (Synapses.CanonicalSource.load access.database part.rows)
    pure ()
  return result
