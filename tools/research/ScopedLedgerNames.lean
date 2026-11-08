module
public import Eggshell.DeliveryLedger
public import Std.Data.DHashMap.Basic
@[expose] public section

namespace Eggshell.Research.ScopedLedgerNames
open Synapses DeliveryLedger

abbrev RowScope := String × Subject
abbrev RowMemo := Std.DHashMap RowScope fun scope =>
  {text : String // text = subjectBase scope.1 scope.2}
abbrev BindingScope := String × (String × String)
abbrev BindingMemo := Std.DHashMap BindingScope fun scope =>
  {text : String // text = bindingBase scope.1 scope.2.1 scope.2.2}

/-- The table belongs to one confirmation. Stored prefixes carry their exact
scope in the type; a hit has no hash computation, IO or shared ownership. -/
def row (memo : RowMemo) (value : Row) :
    {text : String // text = rowKey value} × RowMemo :=
  let scope := (value.database,value.source.subject)
  match memo.get? scope with
  | some base => (⟨base.val ++ key value.source,by rw [base.property]; rfl⟩,memo)
  | none =>
    let base : {text : String // text = subjectBase scope.1 scope.2} := ⟨subjectBase scope.1 scope.2,rfl⟩
    (⟨base.val ++ key value.source,rfl⟩,memo.insert scope base)

def binding (memo : BindingMemo) (value : Binding) :
    {text : String // text = bindingKey value} × BindingMemo :=
  let scope := (value.database,(value.owner,value.work))
  match memo.get? scope with
  | some base => (⟨base.val ++ key (value.first,value.limit),by rw [base.property]; rfl⟩,memo)
  | none =>
    let base : {text : String // text = bindingBase scope.1 scope.2.1 scope.2.2} :=
      ⟨bindingBase scope.1 scope.2.1 scope.2.2,rfl⟩
    (⟨base.val ++ key (value.first,value.limit),rfl⟩,memo.insert scope base)

theorem row_exact (memo : RowMemo) (value : Row) : (row memo value).1.val = rowKey value :=
  (row memo value).1.property

theorem binding_exact (memo : BindingMemo) (value : Binding) :
    (binding memo value).1.val = bindingKey value := (binding memo value).1.property

end Eggshell.Research.ScopedLedgerNames
