module

public import Eggshell.SynapseExtraction
public import Eggshell.SourceEvidence
public import Lean.Data.Json.Parser

@[expose] public section

namespace Eggshell.Synapses.Extraction
open Lean

structure Layout where
  text : String
  original : String
  offsets : Array Nat

/-- Canonical JSON is checked once; coordinates name original scalar characters. -/
def layout (raw : String) : Except String Layout := do
  let projected ← if raw.startsWith "\"" then pure (some (raw, 0)) else
    match Json.parse raw with
    | .ok (.obj value) => do
      let json := Json.obj value
      unless json.compress == raw do throw "noncanonical native response"
      let outputs := (["output", "aggregatedOutput", "stdout"].filterMap fun key =>
        (json.getObjValAs? String key).toOption).eraseDups
      let [text] := outputs | throw "no unambiguous native text output"
      let fragment := (toJson text).compress
      let [before, _] := raw.splitOn fragment | throw "ambiguous native output position"
      pure (some (fragment, before.length))
    | .ok (.arr _) => throw "unsupported native output array"
    | _ => pure none
  let encoded := projected.isSome
  let fragment := projected.map (·.1) |>.getD raw
  let base := projected.map (·.2) |>.getD 0
  let text ← if encoded then Json.parse fragment >>= Json.getStr? else pure raw
  if encoded && (toJson text).compress != fragment then throw "noncanonical saved scalar"
  let mut offsets := #[]
  let mut position := base + if encoded then 1 else 0
  for char in text.toList do
    offsets := offsets.push position
    position := position + if encoded then (toJson (String.singleton char)).compress.length - 2 else 1
  offsets := offsets.push position
  unless position + (if encoded then 1 else 0) == base + fragment.length do throw "scalar layout mismatch"
  return ⟨text, raw, offsets⟩

structure TextLine where
  text : String
  first : Nat
  limit : Nat
  deriving Repr, BEq

def textLines (text : String) : Array TextLine := Id.run do
  let mut lines := #[]
  let mut position := 0
  for line in text.splitOn "\n" do
    let limit := min text.length (position + line.length + 1)
    if position < limit then lines := lines.push ⟨line, position, limit⟩
    position := limit
  return lines

/-- Terminal elision joins unrelated source fragments. Such a display row
has original observation bytes, but no complete file-line payload. -/
def outputElision (text : String) : Bool :=
  ["…", "..."].any fun delimiter =>
    ((text.splitOn delimiter).drop 1 |>.dropLast).any fun payload =>
      match (payload.trimAscii.toString.splitOn " ").filter (!·.isEmpty) with
      | [count,unit,"truncated"] => count.toNat?.any (0 < ·) &&
          ["tokens","chars","bytes","lines"].contains unit
      | _ => false

def numbered (text : String) : Option (Nat × String) := do
  if outputElision text then none else do
    let parts := text.splitOn "\t"
    let first ← parts.head?
    let number ← first.trimAscii.copy.toNat?
    if number == 0 || parts.length < 2 then none
    else some (number, "\t".intercalate parts.tail)

theorem elided_row_not_numbered (text : String) (elided : outputElision text = true) :
    numbered text = none := by
  simp [numbered,elided]

/-- Literal shell lexer; unsupported syntax stays unsupported and is never run. -/
def shellWords (text : String) : Except String (Array String) := do
  let mut words := #[]
  let mut token : Array Char := #[]
  let mut quote : Option Char := none
  let mut escaped := false
  for char in text.toList ++ [' '] do
    if escaped then
      token := token.push char
      escaped := false
    else if quote == some '\'' then
      if char == '\'' then quote := none else token := token.push char
    else if char == '\\' then escaped := true
    else if let some delimiter := quote then
      if char == delimiter then quote := none else token := token.push char
    else if char == '\'' || char == '"' then quote := some char
    else if char.isWhitespace || char == ';' || char == '|' then
      if !token.isEmpty then words := words.push (String.ofList token.toList)
      token := #[]
      if char == ';' || char == '|' || char == '\n' then words := words.push (String.singleton char)
    else token := token.push char
  if quote.isSome || escaped then throw "unfinished shell quote"
  return words

def unwrap (command : String) : String :=
  match shellWords command with
  | .ok words =>
    match words.toList with
    | [shell, flag, inner] =>
      if (["sh", "bash", "zsh"].contains (shell.splitOn "/" |>.getLast!)) &&
          (flag == "-c" || flag == "-lc") then inner else command
    | _ => command
  | .error _ => command

def workCommand (work : String) : Except String String := do
  let parts := work.splitOn "\n"
  unless 2 ≤ parts.length do throw "no native work command"
  let payload ← Json.parse ("\n".intercalate parts.tail)
  match payload.getObjValAs? String "command" with
  | .ok value => return unwrap value
  | .error _ => return unwrap (← payload.getObjValAs? String "cmd")

def fileMap (records : Array Json) : Except String (Array File) := do
  let mut candidates : Std.HashMap String (Std.HashSet File) := {}
  for record in records do
    if !(← record.getObjValAs? Bool "complete") then continue
    if !(← record.getObjValAs? (Array Json) "uris").isEmpty then continue
    for value in ← record.getObjValAs? (Array Json) "files" do
      let content ← value.getObjVal? "content"
      if content == .null then continue
      let file : File := ⟨← value.getObjValAs? String "relative",
        ← content.getObjValAs? String "root", ← content.getObjValAs? Nat "bytes"⟩
      if !file.valid then continue
      candidates := add candidates file.relative file
  return candidates.fold (fun result _ files =>
    if files.size == 1 then result ++ files.toArray else result) #[]

def parseBounds (text : String) : Option (Nat × Nat) := do
  let normalized := (text.replace "–" "-").replace "—" "-"
  let parts := normalized.splitOn "-"
  let first ← (← parts.head?).toNat?
  let last ← if parts.length == 1 then some first else if parts.length == 2 then
      ((parts[1]!).dropWhile (· == 'L')).toString.toNat? else none
  if 0 < first && first ≤ last then some (first, last) else none

def readPlans (command : String) (files : Array File) : Except String (Array Range) := do
  let some segments := SourceEvidence.sequenceSegments? command | throw "unsupported read sequence"
  let mut plans := #[]
  for segment in segments do
    let ["nl", "-ba", path, "|", "sed", "-n", program] := (← shellWords segment).toList |
      throw "unsupported literal read sequence"
    if path.toList.any (fun c => "$\x60*?{}".contains c) then throw "nonliteral read path"
    let candidates := files.filter (fun f => path == f.relative || path.endsWith ("/" ++ f.relative))
    unless candidates.size == 1 do throw "ambiguous read path"
    for statement in program.splitOn ";" do
      let statement := statement.trimAscii.toString
      unless statement.endsWith "p" do throw "unsupported read program"
      let bounds := ((statement.dropEnd 1).copy.replace "," "-")
      let some (first, last) := parseBounds bounds | throw "invalid read interval"
      plans := plans.push ⟨candidates[0]!, first, last⟩
  if plans.isEmpty then throw "no numbered read"
  return plans

structure Document where
  owner : String
  work : String
  workText : Option String
  source : Option String
  native : Bool
  occurrences : Array Occurrence
  files : Array File

def document (value : Json) : Except String Document := do
  return {
    owner := ← value.getObjValAs? String "owner"
    work := ← value.getObjValAs? String "workKey"
    workText := ← value.getObjValAs? (Option String) "work"
    source := ← value.getObjValAs? (Option String) "source"
    native := ← value.getObjValAs? Bool "native"
    occurrences := ← value.getObjValAs? (Array Occurrence) "occurrences"
    files := ← fileMap (← value.getObjValAs? (Array Json) "records") }

structure LocatedRead where
  read : Read
  rows : Array OutputRow
  originalRows : Array Read
  text : String

/-- Presence in a pinned source archive, without inventing an execution order. -/
def recordedRows (database : String) (doc : Document) : Except String (Array Read) := do
  let some raw := doc.source | throw "no original observation"
  let some work := doc.workText | throw "no original work"
  let some occurrence := doc.occurrences[0]? | throw "missing native occurrence identity"
  let plans ← readPlans (← workCommand work) doc.files
  let decoded ← layout raw
  let mut rows := #[]
  for line in textLines decoded.text do
    let some (number, _) := numbered line.text | continue
    let files := plans.foldl (fun files range =>
      if range.first ≤ number && number ≤ range.last then files.insert range.file else files)
      ({} : Std.HashSet File)
    if files.size != 1 then continue
    let source : Range := ⟨files.toArray[0]!, number, number⟩
    let binding : Binding := ⟨database, doc.owner, doc.work,
      decoded.offsets[line.first]!, decoded.offsets[line.limit]!⟩
    rows := rows.push ⟨occurrence, source, binding⟩
  return rows

def recordedReads (database : String) (doc : Document) : Except String (Array LocatedRead) := do
  let rows ← recordedRows database doc
  let mut chunks : Array LocatedRead := #[]
  for row in rows do
    if let some previous := chunks.back? then
      if previous.read.source.file == row.source.file &&
          previous.read.source.last + 1 == row.source.first &&
          previous.read.binding.limit == row.binding.first then
        let merged := {previous with
          read := {previous.read with
            source := {previous.read.source with last := row.source.last}
            binding := {previous.read.binding with limit := row.binding.limit}}
          originalRows := previous.originalRows.push row}
        chunks := chunks.pop.push merged
        continue
    chunks := chunks.push ⟨row, #[], #[row], ""⟩
  return chunks

def locateReads (database : String) (doc : Document) (trace : Trace) : Except String (Array LocatedRead) := do
  let some raw := doc.source | throw "no original observation"
  let some work := doc.workText | throw "no original work"
  let command ← workCommand work
  let plans ← readPlans command doc.files
  let decoded ← layout raw
  let original := (textLines decoded.text).filterMap fun line => do
    let (number, body) ← numbered line.text
    let files := plans.filter (fun range => range.first ≤ number && number ≤ range.last)
    let unique := files.foldl (fun files range => files.insert range.file) ({} : Std.HashSet File)
    if unique.size != 1 then none else
      some (line, number, body, unique.toArray[0]!)
  if original.isEmpty then throw "no unambiguous original numbered rows"
  let mut result := #[]
  for occurrence in doc.occurrences do
    let some start := trace.starts[occurrence]? | continue
    let some output := trace.finished[occurrence]? | continue
    if unwrap start.command != command then continue
    let actual := (textLines output).filterMap fun line => do
      let (number, body) ← numbered line.text
      some (line, number, body)
    if !original.all (fun (_, number, body, _) => actual.any (fun (_, n, b) => n == number && b == body)) then continue
    let mut chunks : Array LocatedRead := #[]
    for (line, number, body, file) in original do
      let source : Range := ⟨file, number, number⟩
      let first := decoded.offsets[line.first]!
      let limit := decoded.offsets[line.limit]!
      let binding : Binding := ⟨database, doc.owner, doc.work, first, limit⟩
      let rows := actual.filterMap fun (actualLine, n, b) =>
        if n == number && b == body then some (OutputRow.mk source actualLine.first actualLine.limit) else none
      let recorded : Read := ⟨occurrence, source, binding⟩
      let located : LocatedRead := ⟨recorded, rows, #[recorded], line.text⟩
      if let some previous := chunks.back? then
        if previous.read.source.file == file && previous.read.source.last + 1 == number &&
            previous.read.binding.limit == first then
          let merged : LocatedRead := {
            read := {previous.read with
              source := {previous.read.source with last := number}
              binding := {previous.read.binding with limit}}
            rows := previous.rows ++ rows
            originalRows := previous.originalRows.push recorded
            text := previous.text ++ "\n" ++ line.text }
          chunks := chunks.pop.push merged
          continue
      chunks := chunks.push located
    result := result ++ chunks
  if result.isEmpty then throw "saved observation has no exact matching completed call"
  return result

def hexDigit (char : Char) : Option Nat :=
  if '0' ≤ char && char ≤ '9' then some (char.toNat - '0'.toNat)
  else if 'a' ≤ char && char ≤ 'f' then some (char.toNat - 'a'.toNat + 10)
  else if 'A' ≤ char && char ≤ 'F' then some (char.toNat - 'A'.toNat + 10)
  else none

def percentDecode (text : String) : Option String := do
  let chars := text.toList.toArray
  let mut bytes := ByteArray.empty
  let mut position := 0
  while position < chars.size do
    let char := chars[position]!
    if char == '%' then
      let a ← chars[position+1]? >>= hexDigit
      let b ← chars[position+2]? >>= hexDigit
      bytes := bytes.push (UInt8.ofNat (16*a+b))
      position := position+3
    else
      bytes := bytes ++ (String.singleton char).toUTF8
      position := position+1
  String.fromUTF8? bytes

/-- Only declared paths and literal line intervals; destinations are never opened. -/
def citation (label destination : String) (files : Array File) : Option Range := do
  let destination ← percentDecode destination
  let destination := destination.trimAscii.copy |>.replace "<" "" |>.replace ">" ""
  let mut candidates := #[]
  for file in files do
    for separator in [":", "#L"] do
      let marker := file.relative ++ separator
      let parts := destination.splitOn marker
      if parts.length != 2 then continue
      let leading := parts[0]!
      if !leading.isEmpty && !leading.endsWith "/" then continue
      let some (first, last) := parseBounds parts[1]! | continue
      let filename := file.relative.splitOn "/" |>.getLast!
      let displayed := label.splitOn (filename ++ ":")
      let mut last := last
      if displayed.length == 2 then
        let bounds := String.ofList ((displayed[1]!).toList.takeWhile
          (fun c => c.isDigit || c == '-' || c == '–' || c == '—'))
        let (a, b) ← parseBounds bounds
        if a != first || (first != last && b != last) then return ← none
        last := b
      candidates := candidates.push (Range.mk file first last)
  if candidates.size == 1 then some candidates[0]! else none

def paragraphCitations (text : String) (files : Array File) : Array Range := Id.run do
  let mut result : Std.HashSet Range := {}
  for part in (text.splitOn "](").dropLast.zip ((text.splitOn "](").tail) do
    let some label := (part.1.splitOn "[").getLast? | continue
    let some destination := (part.2.splitOn ")").head? | continue
    if let some range := citation label destination files then result := result.insert range
  return result.toArray

def addAnswer (database : String) (doc : Document) (reads : Array LocatedRead) (graph : Graph) :
    Except String Graph := do
  let some raw := doc.source | throw "answer has no original scalar"
  let decoded ← layout raw
  let files := reads.foldl (fun files located => files.insert located.read.source.file) ({} : Std.HashSet File)
  let mut graph := graph
  let mut position := 0
  for paragraph in decoded.text.splitOn "\n\n" do
    let limit := position + paragraph.length
    if position < limit then
      let claim : Claim := ⟨database, doc.owner, decoded.offsets[position]!, decoded.offsets[limit]!⟩
      graph ← supportCitations graph claim (paragraphCitations paragraph files.toArray)
        (reads.map (·.read)) (reads.flatMap (·.originalRows))
    position := limit + 2
  return graph

end Eggshell.Synapses.Extraction
