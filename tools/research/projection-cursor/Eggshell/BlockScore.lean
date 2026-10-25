module
public import ProjectionCache
public import Eggshell.MiniLM

@[expose] public section
namespace Eggshell.BlockScore
open Lean DB

/-- A transient projection or a durable source hint. Neither carries Work,
freshness, original-observation or completed authority. -/
inductive Input where
  | indexed (owner : Sidecar.Owner) (window : String)
  | projected (hex : String)
  deriving ToJson, FromJson

structure Request where
  queries : Array String
  blockRows : Array Input
  deriving FromJson

def kernelSource : String := include_str "../runtime/block_score.py"
def implementation : String := Sha256.hex ((include_str "BlockScore.lean").toUTF8 ++
  kernelSource.toUTF8 ++ (include_str "../ProjectionCache.lean").toUTF8 ++ ProjectionCursor.implementation.toUTF8)
def maxFrameBytes : Nat := 16*1024*1024

structure Frame where
  raw : ByteArray
  queries : Nat
  rows : Nat
  width : Nat
  exact : raw.size = (queries+rows)*width*8
  bounded : raw.size ≤ maxFrameBytes
  coverage : Array (Option String)
  sourceReadMs : Nat
  projectionHits : Nat
  projectionMisses : Nat
  retainedBytes : Nat

/-- The bytes actually sent agree with the dimensions the numerical kernel reads. -/
theorem Frame.byte_count (frame : Frame) : frame.raw.size = (frame.queries+frame.rows)*frame.width*8 := frame.exact

def Frame.header (frame : Frame) : Json := Json.mkObj [
  ("queries",toJson frame.queries),("rows",toJson frame.rows),("width",toJson frame.width)]

def ready (model : String) (pages : IO.Ref PageMap.PageCache) (owner : Sidecar.Owner) : IO VectorMatrix.Ready := do
  let source ← owner.pin
  for storage in [.database,.user] do
    let root := (← Sidecar.locate source storage).semantic
    let encoder := Sha256.hex MiniLM.embeddingSource.toUTF8
    if let some matrix ← VectorMatrix.open? root model encoder then
      let matrix := {matrix with snapshot := {matrix.snapshot with cache := pages}}
      ProjectionCursor.checkExtent matrix.snapshot
      return matrix
  throw (IO.userError "original projections are pending explicit warm")

def prepare (model : String) (cache : ProjectionCache.Cache) (pages : IO.Ref PageMap.PageCache) (body : String)
    (deadline : Nat) (cancelled : IO Bool) : IO Frame := do
  unless body.utf8ByteSize ≤ 8*1024*1024 do throw (IO.userError "block-score request exceeds its bound")
  let request : Request ← IO.ofExcept (Json.parse body >>= fromJson?)
  unless 0 < request.queries.size && request.queries.size ≤ 256 &&
      0 < request.blockRows.size && request.blockRows.size ≤ 256 do
    throw (IO.userError "invalid block-score counts")
  let beforeHits ← cache.hits.get
  let beforeMisses ← cache.misses.get
  let started ← IO.monoMsNow
  let queries ← request.queries.mapM (IO.ofExcept ∘ VectorMatrix.decodeHex)
  let width := queries[0]!.size/8
  unless 0 < width && width ≤ 4096 && queries.all (·.size == width*8) do
    throw (IO.userError "query projection dimensions disagree")
  let mut known : Std.HashMap String (VectorMatrix.Ready × String) := {}
  let mut raw := queries.foldl (·++·) ByteArray.empty
  let mut coverage := #[]
  for input in request.blockRows do
    unless (← IO.monoMsNow) < deadline && !(← cancelled) do throw (IO.userError "block-score read expired")
    let (bytes,metadata) ← match input with
      | .projected hex => pure (← IO.ofExcept (VectorMatrix.decodeHex hex),none)
      | .indexed owner window => do
          let scope := (toJson owner).compress
          let (matrix,identity) ← match known[scope]? with
            | some pair => pure pair
            | none => do
                let matrix ← ready model pages owner
                let pair := (matrix,ProjectionCache.scope matrix)
                known := known.insert scope pair
                pure pair
          let row ← ProjectionCache.read matrix cache identity window
          pure (row.payload.bytes,some row.row.value.coverage)
    unless bytes.size == width*8 do throw (IO.userError "source projection dimensions disagree")
    raw := raw++bytes
    coverage := coverage.push metadata
  for (_,matrix,_) in known.toList do
    ProjectionCursor.checkExtent matrix.snapshot
  if exact : raw.size = (queries.size+request.blockRows.size)*width*8 then
    if bounded : raw.size ≤ maxFrameBytes then
      return ⟨raw,queries.size,request.blockRows.size,width,exact,bounded,coverage,
        (← IO.monoMsNow)-started,(← cache.hits.get)-beforeHits,(← cache.misses.get)-beforeMisses,
        (← cache.state.get).bytes⟩
    else throw (IO.userError "binary numerical frame exceeds its bound")
  else throw (IO.userError "binary numerical frame dimensions disagree")

end Eggshell.BlockScore
