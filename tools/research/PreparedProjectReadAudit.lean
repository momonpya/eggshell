module
import all Eggshell.ProjectReadSnapshot
import all Eggshell.ProjectRead
import all Eggshell.ProjectHookRead
import all Eggshell.PublicationService
import Lean
open Lean Eggshell Eggshell.Plugin
#print axioms ProjectReadSnapshot.bound_sources
#print axioms ProjectReadSnapshot.bound_count
#print axioms Publication.Read.advice_never_completes
#print axioms ProjectHookRead.restored_has_no_completion
theorem prepared_input_is_original (captured : ProjectReadSnapshot.Captured) :
    captured.input.source = captured.original.head := captured.inputBound.trans captured.originalBound.symm
theorem prepared_owner_is_original (captured : ProjectReadSnapshot.Captured) :
    captured.owner.captured.state.source.head = captured.original.head :=
  captured.ownerBound.trans captured.originalBound.symm
#print axioms prepared_input_is_original
#print axioms prepared_owner_is_original
run_meta do
  let env ← getEnv
  for (caller,required) in #[
      (``Publication.Service.run,``PreparationService.Pool.restoreDurable),
      (``PreparationService.Pool.restoreDurable,``PreparationService.Pool.notify),
      (``Publication.Gateway.pin,``Publication.Client.pinPreparedProject),
      (``Publication.Read.pin,``ProjectReadSnapshot.find?),
      (``Publication.Read.pin,``ProjectStore.closeCut),
      (``Publication.Read.query,``ProjectReadSnapshot.load),
      (``ProjectReadSnapshot.load,``OwnerViews.validate)] do
    let some decl := env.find? caller | throwError "Missing prepared-read caller: {caller}"
    let some body := decl.value? | throwError "Missing prepared-read body: {caller}"
    unless body.getUsedConstants.contains required do throwError "Prepared-read caller bypasses {required}: {caller}"
  let some query := env.find? ``Publication.Read.query | throwError "Missing prepared query"
  let some body := query.value? | throwError "Missing prepared query body"
  for forbidden in [``PreparedInputs.loadStored?,``OwnerViews.load?,``OwnerViews.prepareSource,``Warm.runTarget] do
    if body.getUsedConstants.contains forbidden then throwError "Prepared query reopens live names or prepares data: {forbidden}"
  let mut pending := [``ProjectReadSnapshot.find?,``ProjectReadSnapshot.load]
  let mut seen : NameSet := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    if #[``Warm.runTarget,``OwnerViews.prepareSource,``DB.PageMap.withWriter,``DB.PageMap.create,
        ``Persistence.Store.searchDocuments,``IO.FS.writeFile,``IO.FS.writeBinFile].contains name then
      throwError "Prepared metadata restoration reaches construction or original enumeration: {name}"
    if let some decl := env.find? name then
      if let some body := decl.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Prepared metadata path: {seen.size} declarations; no index construction, source enumeration or file writes."
