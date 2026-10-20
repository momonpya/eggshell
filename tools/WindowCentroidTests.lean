import tools.WindowCentroid

open Eggshell.WindowCentroid

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  check ((weights 126 126 16 1).toOption == some #[126]) "context boundary"
  check ((weights 127 126 16 2).toOption == some #[126, 1]) "one-token tail must have one-token weight"
  check ((weights 237 126 16 3).toOption == some #[126, 110, 1]) "overlap must not duplicate source mass"
  check ((weights 0 126 16 1).toOption == some #[1]) "empty encoder input"
  check ((weights 127 126 16 1).toOption.isNone) "truncated coverage must be rejected"
  let first := pack #[1.0, 0.0]
  let tail := pack #[0.0, 1.0]
  check ((project #[first] 20 126 16).toOption == some first) "single-segment bits changed"
  let pooled ← IO.ofExcept (project #[first, tail] 127 126 16 >>= unpack)
  let expected := Float.sqrt (126.0 * 126.0 + 1.0)
  check ((pooled[0]! - 126.0 / expected).abs < 0.000001 &&
    (pooled[1]! - 1.0 / expected).abs < 0.000001) "independent two-vector centroid"
  check (0.0 < pooled[1]! && pooled[1]! < 0.01)
    "tail evidence must participate without a max-score promotion"
  let repeated ← IO.ofExcept (project #[first, first, first] 237 126 16 >>= unpack)
  check (repeated == #[1.0, 0.0]) "repeated direction gained segment-count weight"
  check ((project #[first, pack #[0.0]] 127 126 16).toOption.isNone) "mixed dimensions"
  check ((unpack "000000000000f07f").toOption.isNone) "infinite coordinate"
  check ((unpack "not-hex").toOption.isNone) "invalid packed representation"
  IO.println "Window centroid checks passed; no retrieval-quality or token claim"
