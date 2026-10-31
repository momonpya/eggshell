structure SourceBatch where
  endpoint : Daemon.Endpoint
  requests : Array Synapses.SourceViewBatch.Request
  palette : Synapses.SourceViewBatch.Palette

def sourcePalettes (sources : Array (SourceReference × Array String)) (deadline : Nat) : IO SourceBatch := do
  let some first := sources[0]? | throw (IO.userError "original batch has no readable sources")
  unless sources.all (fun (source,_) => source.endpoint.pid == first.1.endpoint.pid &&
      source.endpoint.port == first.1.endpoint.port && source.endpoint.generation == first.1.endpoint.generation) do
    throw (IO.userError "original views require one shared data-side service")
  let requests := sources.map fun (source,owners) =>
    ({access := source.access,owners := (hashDistinct owners.toList).toArray} : Synapses.SourceViewBatch.Request)
  let budget ← liveBudget deadline
  let response ← Stream.exchange first.1.endpoint "source-palettes" (Json.mkObj [
    ("sources",toJson requests),("budgetMs",toJson budget)]) budget
  let palette ← IO.ofExcept (Json.parse response >>= fromJson? (α := Synapses.SourceViewBatch.Palette))
  unless palette.identities == requests.map (·.access.identity) && Synapses.digest palette.lease &&
      palette.owners.size == requests.size && palette.reuse.size == requests.size do
    throw (IO.userError "original batch changed its pinned source views")
  for index in [:requests.size] do
    let some request := requests[index]? | throw (IO.userError "original batch source disappeared")
    let some owners := palette.owners[index]? | throw (IO.userError "original batch owner domain disappeared")
    unless owners.map Prod.fst == request.owners &&
        owners.all (fun (owner,descriptor) => descriptor.inScope request.access.database owner) do
      throw (IO.userError "original batch changed its owner metadata or read scope")
  return ⟨first.1.endpoint,requests,palette⟩

def SourceBatch.release (batch : SourceBatch) (deadline : Nat) : IO Unit := do
  if (← IO.monoMsNow) ≥ deadline then return
  let budget := min 1000 (← liveBudget deadline)
  let response ← Daemon.exchange batch.endpoint "source-release-many" (Json.mkObj [
    ("sources",toJson batch.requests),("lease",toJson batch.palette.lease),("budgetMs",toJson budget)]) (budget := budget)
  unless response == "true" do throw (IO.userError "original batch release was not acknowledged")

def SourceBatch.select (batch : SourceBatch) (query : Json) (deadline : Nat) : IO Json := do
  let budget ← liveBudget deadline
  let response ← Stream.exchange batch.endpoint "source-plan" (Json.mkObj [
    ("sources",toJson batch.requests),("lease",toJson batch.palette.lease),
    ("selector",query),("budgetMs",toJson budget)]) budget
  let result ← IO.ofExcept (Json.parse response)
  unless result.getObjValD "identities" == toJson batch.palette.identities &&
      result.getObjValD "lease" == toJson batch.palette.lease do
    throw (IO.userError "original selection changed its pinned source views")
  return result.getObjValD "choice"

def SourceBatch.fetch (batch : SourceBatch) (requests : Array Synapses.SourceViewBatch.Fetch)
    (deadline : Nat) : IO (Array Synapses.CanonicalSource.StoredRow) := do
  for part in requests do
    let some owners := batch.palette.owners[part.source]? | throw (IO.userError "selected source has no original view")
    let directory := Std.HashMap.ofArray owners
    for request in part.requests do
      let some descriptor := directory[request.owner]? | throw (IO.userError "selected owner has no original metadata")
      unless request.indices.all (· < descriptor.rows.size) do throw (IO.userError "selected original row is outside its view")
  let budget ← liveBudget deadline
  let response ← Stream.exchange batch.endpoint "source-fetch-many" (Json.mkObj [
    ("sources",toJson batch.requests),("lease",toJson batch.palette.lease),
    ("requests",toJson requests),("budgetMs",toJson budget)]) budget
  let result ← IO.ofExcept (Json.parse response >>= fromJson? (α := Synapses.SourceViewBatch.Reply))
  unless result.identities == batch.palette.identities && result.parts.map Prod.fst == requests.map (·.source) do
    throw (IO.userError "selected originals changed their pinned source views")
  let mut rows := #[]
  for ((source,reply),request) in result.parts.zip requests do
    let some access := batch.requests[source]? | throw (IO.userError "selected original source disappeared")
    let some owners := batch.palette.owners[source]? | throw (IO.userError "selected original owner domain disappeared")
    unless reply.identity == access.access.identity &&
        reply.parts.map (fun part => (part.owner,part.indices)) == request.requests.map (fun part => (part.owner,part.indices)) do
      throw (IO.userError "selected original changed its requested identity or order")
    let directory := Std.HashMap.ofArray owners
    for part in reply.parts do
      let some descriptor := directory[part.owner]? | throw (IO.userError "selected original owner disappeared")
      unless part.rows.size == part.indices.size &&
          (part.indices.zip part.rows).all (fun (index,row) => descriptor.matches index row) do
        throw (IO.userError "selected original differs from its immutable metadata")
      let _ ← IO.ofExcept (Synapses.CanonicalSource.load access.access.database part.rows)
      rows := rows ++ part.rows
  IO.ofExcept (Synapses.CanonicalSource.Delivery.merge rows)
