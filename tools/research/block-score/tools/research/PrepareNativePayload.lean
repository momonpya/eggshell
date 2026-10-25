import Eggshell.Install

open Eggshell

/-- Stage the product payload in an explicit research prefix, without registering
a marketplace or changing the user's configured plugin. -/
def main (args : List String) : IO UInt32 := do
  let [binary,installPath] := args | throw (IO.userError "BINARY ABSOLUTE-PREFIX required")
  let root := System.FilePath.mk installPath
  unless root.isAbsolute do throw (IO.userError "absolute research prefix required")
  let layout := Install.Layout.at root
  if ← layout.executable.pathExists then throw (IO.userError "keep the existing staged runtime")
  Install.copyExecutable (.mk binary) layout.executable
  IO.FS.createDirAll (layout.plugin / ".codex-plugin")
  IO.FS.createDirAll (layout.plugin / "hooks")
  IO.FS.writeFile (layout.plugin / Install.ownerMarkerName) Install.ownerMarkerContents
  IO.FS.writeFile (layout.plugin / ".codex-plugin/plugin.json") Install.pluginManifest
  IO.FS.writeFile (layout.plugin / "hooks/hooks.json") Install.hooksManifest
  Install.writeExecutable layout.launcher Install.commandLauncher
  for name in ["egg","eggshelld"] do
    Install.writeExecutable (layout.plugin / "bin" / name) (Install.pluginLauncher root)
  IO.println s!"staged isolated native payload: {root}"
  return 0
