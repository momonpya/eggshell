def sharedPageCapacity : Nat := 2*1024*65536

/-- Keep reader seeds in the same global allowance. The owner budget counts
the actual page extent, key bytes and a fixed per-entry charge. -/
def sharedGenerationBytes : Nat :=
  (sharedPageCapacity-(AdmissionLimits.publicImages+1)*AdmissionLimits.readerPageBytes)/2

def sharedPageCharge (key : SharedPageKey) (page : CachedPage) : Nat :=
  page.ref.bytes+512+key.1.utf8ByteSize+key.2.1.utf8ByteSize+
    key.2.2.1.utf8ByteSize+key.2.2.2.1.utf8ByteSize

theorem shared_page_charge_covers (key : SharedPageKey) (page : CachedPage) :
    page.ref.bytes ≤ sharedPageCharge key page := by unfold sharedPageCharge; omega

abbrev SharedPageCache := Eggshell.Research.WeighedCache.Cache
  SharedPageKey CachedPage sharedGenerationBytes sharedPageCharge

def SharedPageCache.capacity : Nat := sharedPageCapacity

def SharedPageCache.lookup (cache : SharedPageCache) (key : SharedPageKey) : Option CachedPage :=
  Eggshell.Research.WeighedCache.Cache.find? cache key

def SharedPageCache.find (cache : SharedPageCache) (key : SharedPageKey) (ref : Ref) : Option (Loaded ref) := do
  let cached ← cache.lookup key
  if same : cached.ref = ref then some (same ▸ cached.loaded) else none

def SharedPageCache.touch (cache : SharedPageCache) (key : SharedPageKey) (page : CachedPage) : SharedPageCache :=
  cache.insert key page

def SharedPageCache.retainedCharge (cache : SharedPageCache) : Nat :=
  Eggshell.Research.WeighedCache.weightOf sharedPageCharge cache.state.recent.slots+
    Eggshell.Research.WeighedCache.weightOf sharedPageCharge cache.state.previous.slots

theorem SharedPageCache.touch_bounded (cache : SharedPageCache) (key : SharedPageKey) (page : CachedPage) :
    (cache.touch key page).retainedCharge ≤ capacity := by
  have bounded := (cache.touch key page).retained_bounded
  change (cache.touch key page).retainedCharge ≤ 2*32505856 at bounded
  change _ ≤ 134217728
  omega

theorem SharedPageCache.reader_seed_budget (cache : SharedPageCache) :
    cache.retainedCharge+(AdmissionLimits.publicImages+1)*AdmissionLimits.readerPageBytes ≤ capacity := by
  have bounded := cache.retained_bounded
  change cache.retainedCharge ≤ 2*32505856 at bounded
  change _+69206016 ≤ 134217728
  omega

theorem SharedPageCache.touch_recent (cache : SharedPageCache) (key : SharedPageKey) (page : CachedPage)
    (fits : sharedPageCharge key page ≤ sharedGenerationBytes) :
    (cache.touch key page).lookup key = some page :=
  Eggshell.Research.WeighedCache.Cache.insert_find cache key page fits

theorem SharedPageCache.find_rejects (cache : SharedPageCache) (key : SharedPageKey)
    (ref : Ref) (cached : CachedPage) (located : cache.lookup key = some cached) (different : cached.ref ≠ ref) :
    cache.find key ref = none := by
  simp [find,located,different]

def SharedPageCache.generationEntries
    (generation : Eggshell.ByteBudgetCache.Generation SharedPageKey CachedPage sharedGenerationBytes) :
    Array (SharedPageKey × CachedPage) :=
  generation.index.toArray.filterMap fun (key,_) => (generation.find? key).map (key,·)

def SharedPageCache.entries (cache : SharedPageCache) : Array (SharedPageKey × CachedPage) :=
  (generationEntries cache.state.previous).filter
    (fun (key,_) => (cache.state.recent.find? key).isNone)++generationEntries cache.state.recent
