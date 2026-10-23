import tools.research.ResourceGuard

open Eggshell.Research.ResourceGuard

private def process (pid parent : Nat) (command : Array String := #[])
    (identity := "birth-a") (state := "S") : Process :=
  ⟨pid,parent,1024,state,identity,command⟩

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

#eval show IO Unit from do
  let rows := ({} : Std.HashMap Nat Process).insert 1 (process 1 0)
    |>.insert 10 (process 10 1 #["/bin/sh","--owned-prefix","/study"])
    |>.insert 11 (process 11 10)
    |>.insert 20 (process 20 11)
    |>.insert 21 (process 21 20)
    |>.insert 30 (process 30 1 #["/study/runtime"])
    |>.insert 31 (process 31 30)
    |>.insert 40 (process 40 1 #["/other/runtime"])
    |>.insert 41 (process 41 1 #[] "birth-a" "Z")
    |>.insert 42 (process 42 1 #[] "birth-new")
  let excluded := ancestors rows 11
  let known := ({} : Std.HashMap Nat String).insert 41 "birth-a" |>.insert 42 "birth-old"
  let selected := (owned rows excluded 20 known #["/study"]).map (·.process.pid)
    |>.qsort (· < ·)
  check (selected == #[20,21,30,31]) "ownership, parent exclusion, zombies, or PID birth identity regressed"
  check ((parseProcess " 20 11 123 S Fri Oct 23 12:34:56 2026 /bin/sleep 3").map
    (fun row => (row.pid,row.identity,row.command)) == some (20,"Fri Oct 23 12:34:56 2026",#["/bin/sleep","3"]))
    "ps field parsing regressed"
  check ((parseProcess "broken").isNone && (parseProcess "-1 2 3 S Fri Oct 23 12:34:56 2026 x").isNone)
    "malformed process rows were admitted"
  IO.println "ResourceGuard ownership checks passed"
