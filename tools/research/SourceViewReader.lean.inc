def metadataCapacity : Nat := 64*1024*1024
def fileCapacity : Nat := 16*1024*1024

/-- These are service-wide caches keyed by the immutable project publication.
No chat, query, capability, score or original body is a cache value. -/
abbrev MetadataCache := SharedMetadataCache.Cache PreparedSourceView.OwnerReady metadataCapacity
abbrev FileCache := SharedMetadataCache.Cache PreparedSourceView.FileReady fileCapacity

def Loaded.withMetadata (loaded : Loaded) (owner : String) (deadline : Nat)
    (use : PreparedSourceView.OwnerReady → IO α) : IO α := do
  let original ← loaded.recipes.get (Recipe.name owner)
  let descriptor ← loaded.recipes.get (PreparedSourceView.ownerName owner)
  if original.isSome && descriptor.isNone then
    throw (IO.userError "original has no published selection metadata")
  let bytes ← IO.ofExcept (PreparedOwnerArena.payloadBytes descriptor)
  let key := (toJson (loaded.identity,"owner",owner)).compress
  loaded.views.withReady key (PreparedOwnerArena.charge bytes) deadline (do
    match original with
    | none =>
      unless descriptor.isNone do throw (IO.userError "orphan selection metadata")
      let empty : Recipe.Stored := ⟨#[],[]⟩
      let layout ← IO.ofExcept (Recipe.check empty.rows empty.records)
      IO.ofExcept (PreparedSourceView.decodeOwner loaded.metadata.source.identity owner
        (PreparedSourceView.ownerStored owner empty layout))
    | some _ => PreparedSourceView.readOwner loaded.recipes loaded.metadata.source.identity owner) use

def Loaded.withFile (loaded : Loaded) (file : File) (deadline : Nat)
    (use : PreparedSourceView.FileReady → IO α) : IO α := do
  let name := PreparedSourceView.fileName file
  let descriptor ← loaded.recipes.get name
  unless descriptor.isSome do throw (IO.userError "original file header is not published")
  let bytes ← IO.ofExcept (PageMap.payloadSize descriptor)
  let key := (toJson (loaded.identity,"file",file)).compress
  loaded.files.withReady key (PreparedOwnerArena.charge bytes) deadline
    (PreparedSourceView.readFile loaded.recipes file) use
