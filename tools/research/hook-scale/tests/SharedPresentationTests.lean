import Eggshell.SynapseUsage
import Eggshell.CanonicalSourcePacket
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Synapses.CanonicalSource

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let file : File := ⟨"src/data.cpp",Sha256.hex "original-file".toUTF8,100⟩
  let occurrence : Occurrence := ⟨"session","turn","use"⟩
  let original := "    21\t日本語 paired_value\n"
  let raw := (Json.mkObj [("output",toJson original)]).compress
  let decoded ← IO.ofExcept (layout raw)
  let some line := (textLines decoded.text)[0]? | throw (IO.userError "empty original fixture")
  let binding : Binding := ⟨"database","owner","work",decoded.offsets[line.first]!,decoded.offsets[line.limit]!⟩
  let read : Read := ⟨occurrence,⟨file,21,21⟩,binding,#[]⟩
  let doc : Document := ⟨"owner","work",some "arbitrary-tool-input",some raw,true,#[occurrence],#[file]⟩
  let row : StoredRow := ⟨⟨file,21⟩,"日本語 paired_value",#[⟨occurrence,binding⟩]⟩
  let packet := fun (row : StoredRow) =>
    let frame := Packet.fileFrame row.key.file #[row]
    Packet.wrapper ++ frame.leading ++ Packet.rowText row ++ frame.trailing ++ Packet.footer
  let body := packet row
  let shown := presented body #[doc] #[read]
  check (shown.ranges == #[read.source] && shown.coversBinding binding)
    "shared literal row was not recognized"
  check ((sharedPresented body #[doc] #[read]).size == 1) "original witness lost"
  let absent := fun body docs reads => (presented body docs reads).ranges.isEmpty
  check (absent (packet {row with code := "different"}) #[doc] #[read]) "changed code accepted"
  check (absent (packet {row with key := {row.key with file := {file with fingerprint := Sha256.hex "changed".toUTF8}}}) #[doc] #[read])
    "changed fingerprint accepted"
  check (absent (packet {row with origins := #[⟨occurrence,{binding with owner := "other"}⟩]}) #[doc] #[read])
    "foreign owner accepted"
  check (absent (packet {row with origins := #[⟨{occurrence with session := "other"},binding⟩]}) #[doc] #[read])
    "foreign occurrence accepted"
  check (absent body #[{doc with native := false}] #[read]) "non-native row accepted"
  check (absent body #[doc] #[{read with binding := {binding with first := binding.first+1}}])
    "wrong raw coordinate accepted"
  check (absent (body.replace Packet.footer "") #[doc] #[read]) "incomplete packet accepted"
  check (absent (body.replace "END SOURCE\n" "") #[doc] #[read]) "incomplete file frame accepted"
  check (absent ("SAVED SOURCE POSITIONS\n" ++ (toJson read.source).compress) #[doc] #[read])
    "location-only reference accepted"
  let secondOccurrence := {occurrence with session := "second"}
  let secondBinding := {binding with owner := "second-owner"}
  let secondRead := {read with occurrence := secondOccurrence,binding := secondBinding}
  let secondDoc := {doc with owner := "second-owner",occurrences := #[secondOccurrence]}
  let shared := packet {row with origins := row.origins.push ⟨secondOccurrence,secondBinding⟩}
  let shown := presented shared #[doc,secondDoc] #[read,secondRead]
  check (shown.bindings.size == 2 && shown.coversBinding binding && shown.coversBinding secondBinding)
    "shared payload discarded an original occurrence"
  let otherFile := {file with relative := "src/other.cpp",fingerprint := Sha256.hex "other-file".toUTF8}
  let otherRead := {secondRead with source := ⟨otherFile,21,21⟩}
  let otherDoc := {secondDoc with files := #[otherFile]}
  let otherRow := {row with key := ⟨otherFile,21⟩,origins := #[⟨secondOccurrence,secondBinding⟩]}
  let firstFrame := Packet.fileFrame file #[row]
  let secondFrame := Packet.fileFrame otherFile #[otherRow]
  let multiple := Packet.wrapper ++ firstFrame.leading ++ Packet.rowText row ++ firstFrame.trailing ++
    secondFrame.leading ++ Packet.rowText otherRow ++ secondFrame.trailing ++ Packet.footer
  let shown := presented multiple #[doc,otherDoc] #[read,otherRead]
  check (shown.ranges.contains read.source && shown.ranges.contains otherRead.source)
    "first file frame was lost while splitting consecutive sources"
  check (absent (body.replace "END SOURCE\n" "END SOURCE forged\n") #[doc] #[read])
    "invalid source terminator accepted"
  IO.println "shared presentation passed: original literal/scalar coordinates, provenance, changed payload/fingerprint/origin, incomplete frames, locations and shared occurrences"
