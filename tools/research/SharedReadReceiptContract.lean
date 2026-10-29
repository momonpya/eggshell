module
import all Eggshell.SynapseJournal
import all Eggshell.SynapseRecommend
public meta import Lean
open Lean Eggshell Eggshell.Synapses

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``SharedReadReceipt.collect,#[``SharedReadReceipt.tokens,``RangeReach.prepare,``RangeReach.Prepared.lookup?],
        #[``DB.PageMap.withWriter,``Journal.append,``Index.replace]),
      (``Journal.nativeFeedback,#[``Journal.presentationWithShared,``Journal.indexAt?,``Journal.completeKnowledge],
        #[``DB.PageMap.withWriter,``Journal.append,``Index.replace]),
      (``Journal.replay,#[``Journal.presentationWithShared,``Journal.indexAt?,``Journal.completeKnowledge],
        #[``DB.PageMap.withWriter,``Journal.append,``Index.replace,``UsageCache.publish]),
      (``UsageCache.open?,#[``DB.Sidecar.locate],
        #[``DB.PageMap.withWriter,``Journal.append,``DB.Sidecar.prepare]),
      (``UsageCache.publish,#[``DB.Sidecar.withIndexClaim,``Index.insert,``Routing.Store.finish],
        #[``Journal.append]),
      (``Journal.refresh,#[``UsageCache.ensure,``UsageCache.replayIdentity],#[]),
      (``Recommend.prepare,#[``UsageCache.open?],#[``UsageCache.publish])] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if seen.contains name then continue
      seen := seen.insert name
      let some declaration := environment.find? name | throwError "missing receipt boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless seen.contains name do throwError "{root} bypasses {name}"
    for name in forbidden do
      if seen.contains name then throwError "{root} reaches forbidden {name}"
    logInfo m!"Audited shared receipt boundary {root}"

public def main : IO Unit := IO.println "PASS shared receipt boundaries"
