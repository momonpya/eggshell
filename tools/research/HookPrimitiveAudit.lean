module
import all Eggshell.HookCommand
import all Eggshell.Sha256
import Lean
open Lean Eggshell

/-- The former primitives are retained as specification, not runtime paths. -/
def formerDigit (value : UInt8) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value.toNat)
  else Char.ofNat ('a'.toNat + value.toNat - 10)
def formerHex (bytes : ByteArray) : String :=
  String.ofList <| bytes.toList.flatMap fun byte =>
    [formerDigit (byte.toNat / 16).toUInt8, formerDigit (byte.toNat % 16).toUInt8]
def formerDigest (input : ByteArray) : ByteArray := Id.run do
  let mut bytes := input.push 0x80
  let padding := (64 - ((bytes.size + 8) % 64)) % 64
  for _ in [0:padding] do bytes := bytes.push 0
  let bits := input.size.toUInt64 * 8
  for i in [0:8] do bytes := bytes.push ((bits >>> ((7-i)*8).toUInt64).toUInt8)
  let mut state : Array UInt32 := #[
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
  for block in [0:bytes.size/64] do state := Sha256.compress state bytes (block*64)
  let mut result := ByteArray.empty
  for word in state do
    for i in [0:4] do result := result.push ((word >>> ((3-i)*8).toUInt32).toUInt8)
  return result
theorem hex_exact (bytes : ByteArray) : Hex.encode bytes = formerHex bytes := rfl
theorem sha_digest_exact (bytes : ByteArray) : Sha256.digest bytes = formerDigest bytes := rfl
theorem sha_hex_exact (bytes : ByteArray) : Sha256.hex bytes = formerHex (formerDigest bytes) := rfl
theorem receipt_valid_exact (id : String) : ReceiptId.valid id =
    (id.length == 64 && id.toList.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))) := rfl
theorem receipt_generation_exact : ReceiptId.fresh =
    (do pure (formerHex (← IO.getRandomBytes 32))) := rfl
#print axioms hex_exact
#print axioms sha_digest_exact
#print axioms sha_hex_exact
#print axioms receipt_valid_exact
#print axioms receipt_generation_exact
#print axioms Plugin.Daemon.valid_hook_reply_is_preserved
#print axioms Plugin.Daemon.absent_hook_reply_is_incomplete
#print axioms Plugin.Daemon.invalid_hook_reply_is_incomplete
run_meta do
  let env ← getEnv
  let mut pending := [``Plugin.Daemon.Command.hookClient]
  let mut seen : NameSet := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let text := name.toString
    if ["Eggshell.FileSystem.","Eggshell.Paths.","Eggshell.Blake3.","Eggshell.Receipt.","Eggshell.Persistence.",
        "Eggshell.DB.","Eggshell.Plugin.Worker.","Eggshell.Plugin.Publication.","Eggshell.Numerical."].any
        (fun part => text.startsWith part) then throwError "Small supervisor still reaches excluded state or crypto: {name}"
    if let some declaration := env.find? name then
      if let some body := declaration.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Primitive supervisor: {seen.size} declarations; no storage, other digest algorithm, backend or model."
