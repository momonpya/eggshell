module
import all Eggshell.ContractAudit
import all Eggshell.Worker
public meta import Lean
open Lean Eggshell

run_meta do
  let env ← getEnv
  for (root,required) in #[
      (``Persistence.Store.Intern.root, ``SourceLexicalPolicy.record),
      (``Persistence.Store.removeRoot, ``SourceLexicalPolicy.require),
      (``KeyedSearchProvider.lexical, ``SourceLexical.posting),
      (``LexicalReads.strictLookup, ``SourceLexical.posting),
      (``LexicalReads.coarseQuery, ``SourceLexical.posting),
      (``Persistence.Store.Federated.retrievalLookup, ``SourceLexical.posting),
      (``Warm.runTarget, ``SourceLexical.status),
      (``Plugin.Worker.indexQueued, ``SourceLexical.status)] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let current :: rest := pending do
      pending := rest
      if seen.contains current then continue
      seen := seen.insert current
      if let some info := env.find? current then
        if let some body := info.value? then
          for dependency in body.getUsedConstants do
            if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    unless seen.contains required do throwError "ordinary entry does not reach source lexical path: {root} -> {required}"
    if seen.contains ``RetrievalResearch.Index.warm then throwError "ordinary entry still builds a duplicate lexical cache: {root}"
    logInfo m!"Ordinary source lexical entry is connected: {root} -> {required}"

public def main : IO Unit := IO.println "Source lexical integration and existing ContractAudit passed"
