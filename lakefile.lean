import Lake

open Lake DSL

package eggshell where
  leanOptions := #[⟨`warningAsError, true⟩]

target storageSyncObject pkg : System.FilePath := do
  let src ← inputFile (pkg.dir / "Eggshell" / "Storage" / "sync.c") true
  buildO (pkg.buildDir / "storage-sync.o") src #[] #["-fPIC", "-I", (← getLeanIncludeDir).toString] "cc"

extern_lib storage_sync pkg := do
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "storage_sync") #[← storageSyncObject.fetch]

-- Lean embeds this boundary in MiniLM. Track its bytes so a normal incremental
-- build cannot silently keep an older numerical implementation.
target embeddingSource pkg : System.FilePath :=
  inputFile (pkg.dir / "runtime" / "embedding.py") true

lean_lib Eggshell where
  extraDepTargets := #[`embeddingSource]

lean_lib PageDBTestSupport where
  roots := #[`tests.PageDBTests, `tests.FullSearchOracle, `tests.SearchMemo, `tests.CorpusCache,
    `tests.SourceEvidenceTests, `tests.SourceObservationTests, `tests.EqualityDependencyTests,
    `tests.DatabaseIndexTests, `tests.WarmTests, `tests.SemanticDeadlineTests, `tests.ReadOnlyCacheTests,
    `tests.KernelFixtures, `tests.MatcherFixtures, `tests.Blake3Fixtures, `tests.ProofBoundaryAudit,
    `tests.MemoReplayTests]

@[default_target]
lean_exe eggshell where
  root := `Main

lean_exe eggshell_tests where
  root := `TestMain

lean_exe eggshell_package where
  root := `tools.Package

lean_exe search_tests where
  root := `tests.SearchTests

lean_exe setup_package_tests where
  root := `tests.SetupPackageTests

lean_exe lifecycle_tests where
  root := `tests.LifecycleTests

lean_exe equality_dependency_tests where
  root := `tests.EqualityDependencyMain

lean_exe eggshell_render where
  root := `tools.Render

lean_exe semantic_latency where
  root := `tools.SemanticLatency

lean_exe proof_fixture_tests where
  root := `tests.ProofFixtureMain

lean_exe memo_replay_tests where
  root := `tests.MemoReplayMain

lean_exe synapse_tests where
  root := `tests.SynapseTests

lean_exe synapse_extraction_tests where
  root := `tests.SynapseExtractionTests

lean_exe synapse_extract where
  root := `tools.SynapseExtract

lean_exe synapse_replay where
  root := `tools.SynapseReplay
