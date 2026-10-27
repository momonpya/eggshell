import Eggshell.MetadataBytes
import tools.research.ArtifactHash
open Lean Eggshell DB

private def require (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)
private def pattern (size : Nat) : ByteArray := Id.run do
  let mut result := ByteArray.empty
  for index in [:size] do result := result.push (UInt8.ofNat (index % 251))
  return result
private def put (source : PageMap.Snapshot) (name : String) (bytes : ByteArray)
    (immutable : Bool := false) : IO (PageMap.Snapshot × Bool × Nat) := do
  let value ← IO.ofExcept (MetadataBytes.checked bytes)
  let ((changed,maximum),_,_) ← PageMap.withWriter source fun writer => do
    let changed ← MetadataBytes.put writer name value immutable
    require (← writer.onlyDerived.get) "metadata wrote outside the derived namespace"
    let mut maximum := 0
    for row in (← writer.pending.get).toList do
      maximum := max maximum (PageMap.encode (.leaf [row])).size
    require (maximum ≤ 8192) "metadata leaked a large value into an index row"
    return (changed,maximum)
  return (← PageMap.pin source.directory,changed,maximum)
private def bytes (source : PageMap.Snapshot) (name : String) : IO ByteArray := do
  let some value ← MetadataBytes.get? source name | throw (IO.userError "missing metadata")
  return value.bytes

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "NEW-OUTPUT")
  let directory := System.FilePath.mk output
  require (directory.isAbsolute && !(← directory.pathExists)) "preserve existing storage checks"
  IO.FS.createDirAll directory
  let mut source ← PageMap.create (directory / "source.egg") "metadata-checks"
  let mut maximum := 0
  let sizes := #[0,1,4095,4096,4097,8191,8192,8193,65537,262144]
  for size in sizes do
    let name := s!"memo:boundary:{size}"
    let input := pattern size
    let (next,changed,bound) ← put source name input
    require changed "a new payload was not published"
    require ((← bytes next name) == input) "payload readback lost bytes at a boundary"
    maximum := max maximum bound
    source := next
  let large := pattern 16385
  let (pinned,_,_) ← put source "memo:header" large
  let (small,_,_) ← put pinned "memo:header" (pattern 3)
  require ((← bytes pinned "memo:header") == large && (← bytes small "memo:header") == pattern 3)
    "rewriting a header invalidated a pinned reader"
  for index in [1:5] do
    require ((← small.get (PageMap.payloadChunkKey (MetadataBytes.payloadKey "memo:header") index)).isNone)
      "shrinking metadata retained an obsolete descriptor"
  source := small
  let (stable,_,_) ← put source "memo:immutable" (pattern 513) true
  let (same,changed,_) ← put stable "memo:immutable" (pattern 513) true
  require (!changed && same.head == stable.head) "identical metadata replay changed the published head"
  let conflict ← try
    let _ ← put same "memo:immutable" (pattern 514) true
    pure false
    catch _ => pure true
  require (conflict && (← PageMap.pin same.directory).head == same.head) "conflicting immutable metadata was published"
  require (match MetadataBytes.checked (pattern 262145) with
    | .error _ => true
    | .ok _ => false) "oversized metadata bypassed its bound"
  let foreign ← try
    let _ ← put same "member:3" (pattern 1)
    pure false
    catch _ => pure true
  require foreign "metadata accepted an authority key"
  let (first,_,_) ← put same "memo:名前" (pattern 5000)
  let (second,_,_) ← put first "memo:名前:0" (pattern 6000)
  require ((← bytes second "memo:名前") == pattern 5000 &&
    (← bytes second "memo:名前:0") == pattern 6000) "logical names collided with chunk suffixes"
  let unusual := MetadataBytes.payloadKey "memo:名前"
  let (second,_,_) ← put second unusual (pattern 6001)
  require ((← bytes second "memo:名前") == pattern 5000 &&
    (← bytes second unusual) == pattern 6001) "a physical-looking logical name damaged another slot"
  let descriptor := PageMap.payloadChunkKey (MetadataBytes.payloadKey "memo:header") 0
  let some encoded ← second.get descriptor | throw (IO.userError "missing corruption probe")
  let blob ← IO.ofExcept (PageMap.decodeBlob encoded)
  let (_,_,_) ← PageMap.withWriter second fun writer =>
    writer.put descriptor (some (PageMap.blobCodec.encode
      {blob with checksum := String.ofList (List.replicate 64 '0')}).toByteArray)
  let corrupt ← PageMap.pin second.directory
  let rejected ← try
    let _ ← bytes corrupt "memo:header"
    pure false
    catch _ => pure true
  require (rejected && (← bytes second "memo:header") == pattern 3) "corruption was accepted or changed an old reader"
  let physical := MetadataBytes.payloadKey "memo:header"
  let (_,_,_) ← PageMap.withWriter corrupt fun writer =>
    writer.put physical (some (DB.Wire.natural.encode 1000000000000).toByteArray)
  let impossible ← PageMap.pin corrupt.directory
  let boundedRead ← try
    let _ ← bytes impossible "memo:header"
    pure false
    catch error => pure (error.toString.contains "read bound")
  require boundedRead "untrusted size was not rejected before allocating the body"
  let result := Json.mkObj [("sizes",toJson sizes),("maximumEncodedSingletonBytes",toJson maximum),
    ("byteExactRoundtrips",toJson true),("pinnedReadersRetained",toJson true),
    ("obsoleteDescriptorsRemoved",toJson true),("immutableReplayIdempotent",toJson true),
    ("conflictingWriteRejected",toJson conflict),("authorityKeyRejected",toJson foreign),
    ("logicalNamesRemainDistinct",toJson true),("corruptionRejected",toJson rejected),
    ("readBoundCheckedBeforeAllocation",toJson boundedRead),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (directory / "result.json") (result.compress ++ "\n")
  IO.println result.compress
