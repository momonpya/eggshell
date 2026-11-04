module
import all Eggshell.SearchProvider
import all Eggshell.Numerical
import Lean
open Lean

run_meta do
  for (caller,required,forbidden) in [
      (``Eggshell.SearchProvider.encoder,#[``Eggshell.Numerical.openClient],#[``IO.Process.spawn]),
      (``Eggshell.SearchProvider.exchange,#[``Eggshell.Numerical.Client.request],#[]),
      (``Eggshell.SearchProvider.stopEncoder,#[``Eggshell.Numerical.Client.close],#[]),
      (``Eggshell.Numerical.Client.request,
        #[``Eggshell.Numerical.sharedKind,``Eggshell.Numerical.requestBody,
          ``Eggshell.Plugin.Daemon.exchange,``Eggshell.Numerical.spawnKernel],#[]),
      (``Eggshell.Numerical.Client.close,#[``Eggshell.Numerical.stopKernel,``Eggshell.Numerical.release],#[]),
      (``Eggshell.Numerical.proxy,#[``Eggshell.Numerical.Client.request,``Eggshell.Numerical.Client.close],#[])] do
    let env ← getEnv
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing native numerical implementation: {caller}"
    let some body := declaration.value? | throwError "missing numerical body: {caller}"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
    for dependency in forbidden do
      if body.getUsedConstants.contains dependency then throwError "{caller} regained {dependency}"

#print axioms Eggshell.Numerical.shared_kind_requires_encode_or_blocks
#print axioms Eggshell.Numerical.cache_only_is_not_shared
#print axioms Eggshell.Numerical.close_is_not_a_shared_request
#print axioms Eggshell.Numerical.terminated_request_unchanged
