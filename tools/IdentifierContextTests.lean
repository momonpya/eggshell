import tools.IdentifierContext

open Eggshell Eggshell.Plugin

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def shared (left right : String) : Bool :=
  let terms := SearchRank.terms (identifierContext right)
  (SearchRank.terms (identifierContext left)).any terms.contains

def main : IO Unit := do
  for (query, source) in [
      ("-fsyntax-only", "options::OPT_fsyntax_only"),
      ("--target", "options::OPT_target"),
      ("-x", "options::OPT_x"),
      ("tool-chain", "getToolChain"),
      ("-fsyntax-only.", "options::OPT_fsyntax_only"),
      ("tool-chain.", "getToolChain"),
      ("http server", "HTTPServer")] do
    require (shared query source) "CLI/identifier boundaries lost a shared component"
  for text in ["plain words", "日本語の記憶", "café naïve", "clang/lib/Driver/Driver.cpp",
               "/usr/local/path-with-dashes", "filename.cpp", "filename.cpp."] do
    require (identifierContext text == text) "plain words or paths gained component noise"
  for text in ["options::OPT_fsyntax_only", "getToolChain"] do
    let expanded := identifierContext text
    require (expanded.startsWith text) "original data changed"
    require ((SearchRank.terms text).all (SearchRank.terms expanded).contains)
      "a complete original term was erased"
  require (!shared "-fsyntax-only" "unrelated_source_value")
    "unrelated identifiers gained a query match"
  IO.println "identifier-context: 17 cases passed"
