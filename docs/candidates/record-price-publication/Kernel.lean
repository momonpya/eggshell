
namespace OriginalRecordPrice

/-- Exact rendered payload costs include LinearNodes' one separator. No
original bytes, character arrays, rendered strings or JSON tree are retained. -/
structure Cost where
  characters : Nat
  bytes : Nat
  deriving BEq,ToJson,FromJson

def Cost.ofText (text : String) : Cost := ⟨text.length+1,text.utf8ByteSize+1⟩

structure Stored where
  span : OriginalStructure.Span
  normal : Cost
  compact : Cost
  deriving BEq

/-- One compact coordinate/price tuple, rather than repeated field names
for every record in an immutable page. -/
instance : ToJson Stored where
  toJson value := toJson (value.span.first,value.span.limit,value.span.decoded,
    value.normal.characters,value.normal.bytes,value.compact.characters,value.compact.bytes)

instance : FromJson Stored where
  fromJson? value := do
    let (first,last,decoded,nc,nb,cc,cb) ←
      fromJson? (α := Nat × Nat × Bool × Nat × Nat × Nat × Nat) value
    return ⟨⟨first,last,decoded⟩,⟨nc,nb⟩,⟨cc,cb⟩⟩

def fragment (original : IndexedCharacters source) (span : OriginalStructure.Span) : DeliveryFragment :=
  {first := span.first
   original := original.slice span.first (span.limit-span.first)
   decoded := span.decoded}

def prepare (original : IndexedCharacters source) (span : OriginalStructure.Span) : Stored :=
  let value := fragment original span
  ⟨span,Cost.ofText (value.render false),Cost.ofText (value.render true)⟩

def Stored.cost (stored : Stored) (compact : Bool) : Cost :=
  if compact then stored.compact else stored.normal

/-- Structural read bounds reject corrupt metadata before it can enter a
shared view. Content identity and the page digest are checked by that view. -/
def Stored.bounded (stored : Stored) : Bool :=
  [stored.normal,stored.compact].all fun cost =>
    0 < cost.characters && cost.characters ≤ 16384 &&
    cost.characters ≤ cost.bytes && cost.bytes ≤ 65536

theorem prepared_span_exact (original : IndexedCharacters source) (span : OriginalStructure.Span) :
    (prepare original span).span = span := rfl

theorem prepared_cost_exact (original : IndexedCharacters source) (span : OriginalStructure.Span)
    (compact : Bool) :
    (prepare original span).cost compact = Cost.ofText ((fragment original span).render compact) := by
  cases compact <;> rfl

theorem prepared_characters_exact (original : IndexedCharacters source) (span : OriginalStructure.Span)
    (compact : Bool) :
    ((prepare original span).cost compact).characters =
      ((fragment original span).render compact).length+1 := by
  rw [prepared_cost_exact]
  rfl

theorem prepared_bytes_exact (original : IndexedCharacters source) (span : OriginalStructure.Span)
    (compact : Bool) :
    ((prepare original span).cost compact).bytes =
      ((fragment original span).render compact).utf8ByteSize+1 := by
  rw [prepared_cost_exact]
  rfl

end OriginalRecordPrice
