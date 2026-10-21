module

public import Eggshell.Blake3

@[expose] public section

namespace Eggshell.Blake3Fixtures

/-- Computational vectors are regression tests, not general hash theorems. -/
def run : IO Unit := do
  for (bytes, expected) in [
      (ByteArray.empty, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
      ("abc".toUTF8, "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85")] do
    unless Blake3.hex (Blake3.hash bytes) == expected do
      throw (IO.userError "BLAKE3 known-answer vector failed")
  IO.println "PASS BLAKE3 empty and abc vectors"

end Eggshell.Blake3Fixtures
