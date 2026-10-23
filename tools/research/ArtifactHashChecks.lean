import tools.research.StudyAcquire
import tools.research.ResourceGuard

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [planPath,fixture,output] := args | throw (IO.userError "ArtifactHashChecks PLAN GUARD-FIXTURE NEW-DIRECTORY")
  let root := System.FilePath.mk output
  check (root.isAbsolute && !(← root.pathExists)) "new absolute hash-check directory required"
  IO.FS.createDir root
  let vectors := #[
    ("","e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc","ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")]
  for (text,expected) in vectors do
    let path := root / "nist"
    IO.FS.writeFile path text
    check ((← ArtifactHash.hex path) == expected && Sha256.hex text.toUTF8 == expected)
      "SHA-256 known-answer mismatch"
  let sizes := #[0,1,55,56,63,64,65,4095,4096,4097,8191,8192,8193]
  for size in sizes do
    let bytes := ByteArray.mk ((Array.range size).map fun index => (index%251).toUInt8)
    let path := root / "boundary"
    IO.FS.writeBinFile path bytes
    check ((← ArtifactHash.hex path) == Sha256.hex bytes) "page or SHA-256 padding boundary mismatch"
  let path := root / "pinned"
  IO.FS.writeFile path "abc"
  let handle ← FileSystem.openRead path.toString
  let before ← FileSystem.readVersion handle
  let replacement := root / "replacement"
  IO.FS.writeFile replacement "xyz"
  IO.FS.rename replacement path
  check ((← ArtifactHash.read handle before.bytes) == vectors[1]!.2) "pinned descriptor followed a replacement"
  let after ← FileSystem.readVersion handle
  let current ← FileSystem.readVersion (← FileSystem.openRead path.toString)
  check (!FileSystem.stableRead before after current before.bytes) "same-size replacement passed version checking"
  let rejected ← try
    StudyAdmission.verifyArtifact ⟨path.toString,vectors[1]!.2⟩
    pure false
  catch _ => pure true
  check rejected "changed artifact passed admission"
  let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← StudyAdmission.readJson planPath))
  let artifacts := #[plan.runtime,plan.runner,plan.cliWrapper,plan.nativeCli,plan.accountConfiguration,plan.prompt] ++
    plan.harness ++ plan.pluginFiles
  for artifact in artifacts do StudyAdmission.verifyArtifact artifact
  let stopped := root / "forced-stop"
  IO.FS.createDir stopped
  let record := stopped / "guard.json"
  let processes ← ResourceGuard.processes
  let some process := processes[(← IO.Process.getPID).toNat]? | throw (IO.userError "missing live test process")
  let code ← ResourceGuard.run {
    record := record.toString,cwd := root.toString,
    command := #[fixture,"tree",stopped.toString],ownedPrefixes := #[stopped.toString]
    limitRssKiB := process.rssKiB+32768,minFreeKiB := 524288}
  let result ← StudyAdmission.readJson record.toString
  check (code == 2 && (result.getObjValAs? Bool "guardTriggered").toOption == some true &&
    (result.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] &&
    (← (stopped / "grandchild.pid").pathExists))
    "resource stop did not report the actual cleaned-up process set"
  IO.FS.writeFile (root / "result.json") ((Json.mkObj [
    ("knownAnswerVectors",toJson vectors.size),("boundarySizes",toJson sizes),
    ("pinnedDescriptorReplacementRejected",toJson true),("sealedArtifactsChecked",toJson artifacts.size),
    ("forcedResourceStopClean",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")
