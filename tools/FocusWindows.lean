module

public import Eggshell.Sha256

@[expose] public section
namespace Eggshell.Plugin

/-- The original saved window slot stays unchanged. Only its Work prefix
is removed from the numerical evidence view, using character coordinates. -/
def evidenceWindowStart (workChars index : Nat) : Nat :=
  workChars + 1 - index * 384

def evidenceWindowText (workChars index : Nat) (window : String) : String :=
  (window.drop (evidenceWindowStart workChars index)).copy

/-- Warm readiness includes the actual view implementation, not a manually
numbered format. Cache entries themselves remain keyed by their actual text. -/
def focusWindowContract : String :=
  Sha256.hex (include_str "FocusWindows.lean").toUTF8

end Eggshell.Plugin
