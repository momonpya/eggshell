import tools.research.CompleteOriginal
open Lean Eggshell.Plugin Eggshell.Research
namespace Eggshell.Research.CompleteOriginalFixtures
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def verify : IO Unit := do
  let long := String.ofList (List.replicate 5000 'x')
  let samples := #["","plain arbitrary result","0","null","\"\"","\"\\u0041\"",
    (toJson "日本語\n한글\tκώδικας 🙂").compress,
    (Json.mkObj [("uri",toJson "mcp://resource/item"),("result",toJson #["alpha",long])]).compress,
    (toJson long).compress]
  for source in samples do
    let prepared ← IO.ofExcept (CompleteOriginal.prepare source)
    let raw := source.toList.toArray
    let reconstructed := "".intercalate (prepared.spans.toList.map fun span =>
      String.ofList (raw.extract span.first span.limit).toList)
    check (reconstructed == source) "whole original layout deleted or repeated characters"
    for span in prepared.spans do
      if span.decoded then
        let part := String.ofList (raw.extract span.first span.limit).toList
        let decoded ← IO.ofExcept (Json.parse ("\"" ++ part ++ "\"") >>= Json.getStr?)
        let encoded := (toJson decoded).compress.toList
        check (String.ofList (encoded.drop 1 |>.take (encoded.length-2)) == part)
          "decoded presentation cannot recreate original coordinates"
  check ((CompleteOriginal.check? 4 #[⟨0,1,false⟩,⟨2,4,false⟩]).isNone)
    "whole original layout accepted a gap"
  check ((CompleteOriginal.check? 4 #[⟨0,5,false⟩]).isNone)
    "whole original layout invented a source suffix"
end Eggshell.Research.CompleteOriginalFixtures
