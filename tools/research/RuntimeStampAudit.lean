module
import all Eggshell.PublicationWire
meta import Lean

/- The runtime stamp must be literal data, with no hashing or source-array construction. -/
run_meta do
  let info ← Lean.getConstInfo ``Eggshell.Plugin.Publication.implementation
  let some (.lit (.strVal value)) := info.value? |
    throwError "publication implementation still executes runtime code"
  unless value.length == 64 && value.toList.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')) do
    throwError "publication implementation is not a complete hexadecimal digest"
  Lean.logInfo m!"Publication implementation is a literal 64-character digest; no runtime dependencies."
