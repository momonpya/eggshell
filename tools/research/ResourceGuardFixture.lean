import Init.System.IO

/-- A bounded native fixture. Its allocation stays live while its child runs. -/
@[noinline] private def retain (bytes : ByteArray) : IO Unit :=
  IO.println (bytes.size + (bytes[0]?.getD 0).toNat)

def main (args : List String) : IO UInt32 := do
  match args with
  | ["leaf",record] =>
      IO.FS.writeFile (.mk record) (toString (← IO.Process.getPID))
      let bytes ← IO.getRandomBytes (48 * 1024 * 1024)
      IO.sleep 15000
      retain bytes
      return 0
  | ["tree",directory] =>
      IO.FS.writeFile (.mk (directory ++ "/parent.pid")) (toString (← IO.Process.getPID))
      let child ← IO.Process.spawn {
        cmd := (← IO.appPath).toString, args := #["leaf",directory ++ "/grandchild.pid"]
        stdin := .null, stdout := .null, stderr := .inherit}
      let bytes ← IO.getRandomBytes (8 * 1024 * 1024)
      let result ← child.wait
      retain bytes
      return result
  | _ => return 1
