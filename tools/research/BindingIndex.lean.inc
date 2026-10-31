def bindingCodec : Wire.Codec StoredBinding :=
  BindingValueCodec.entry.iso (fun value => (value.fact,value.read))
    (fun (fact,read) => ⟨fact,read⟩) (by intro value; cases value; rfl)

theorem binding_codec_roundtrip (value : StoredBinding) (tail : List UInt8) :
    bindingCodec.decode (bindingCodec.encode value ++ tail) = .ok (value,tail) :=
  bindingCodec.roundtrip value tail

def bindingBytes (stored : StoredBinding) : IO ByteArray := do
  let bytes := (bindingCodec.encode stored).toByteArray
  unless bytes.size ≤ 32768 do throw (IO.userError "published binding exceeds its metadata bound")
  return bytes

def decodeBinding (bytes : ByteArray) : IO StoredBinding := do
  unless bytes.size ≤ 32768 do throw (IO.userError "stored binding exceeds its metadata bound")
  let (stored,tail) ← IO.ofExcept (bindingCodec.decode bytes.toList)
  unless tail.isEmpty && (bindingCodec.encode stored).toByteArray == bytes do
    throw (IO.userError "noncanonical binary binding")
  return stored

def prepareBinding (writer : PageMap.Writer) (fact : Fact) : IO Unit := do
  if let some read := bindingCandidate? fact then
    unless read.valid do throw (IO.userError "invalid published original binding")
    let stored : StoredBinding := ⟨contentKey fact,read⟩
    let _ ← putImmutable writer (bindingName read.source stored.fact) (← bindingBytes stored)
