  let sources := prepared.filterMap fun source => do
    let reference ← source.canonical
    let ids := owners.filterMap fun owner =>
      if owner.database == source.source.head.identity then
        some (Persistence.selectionKey owner.original.relation) else none
    if ids.isEmpty then none else some (reference,ids)
  if !sources.isEmpty && plan.canonicalFailure.isEmpty then
    let mut acquired : Option Plugin.Publication.Client.SourceBatch := none
    try
      let batch ← Plugin.Publication.Client.sourcePalettes sources deadline
      acquired := some batch
      let mut shells := plan.shells
      let mut reads := plan.metadataReads
      for ((reference,_),index) in sources.zipIdx do
        let some descriptors := batch.palette.owners[index]? |
          throw (IO.userError "original metadata lost its project view")
        let some reuse := batch.palette.reuse[index]? |
          throw (IO.userError "original metadata lost its prepared reuse status")
        plan := {plan with canonicalReuse := plan.canonicalReuse.push (reference.access.database,reference.access.reuse,reuse)}
        for (owner,descriptor) in descriptors do
          if descriptor.rows.isEmpty then continue
          let some shell := PreparedPlanMetadata.describe owner descriptor |
            throw (IO.userError "invalid original row metadata")
          let some originalReads := PreparedPlanMetadata.reads descriptor |
            throw (IO.userError "invalid original read metadata")
          let shell := match shells[owner]? with
            | none => shell
            | some prior => PreparedPlanMetadata.combine #[prior,shell]
          shells := shells.insert owner shell
          reads := reads ++ originalReads
      plan := {plan with batch := some batch,shells,metadataReads := reads}
    catch _ =>
      if let some batch := acquired then
        try batch.release ((← IO.monoMsNow)+1000) catch _ => pure ()
      plan := {plan with canonicalFailure := plan.canonicalFailure.push ("shared-view","metadata-unavailable")}
