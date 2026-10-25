require 'json'
require 'digest'
require 'shellwords'
root = File.expand_path(__dir__)
def json(path); JSON.parse(File.read(path)); end
def binding(path); {path:path,bytes:File.size(path),sha256:Digest::SHA256.file(path).hexdigest}; end
all_guards = Dir.glob(root+'/*.guard.json').sort.map { |p| [p,json(p)] }
abort 'live owned process remains' unless all_guards.all? { |_,g| g.fetch('state') == 'finished' && g.fetch('ownedPids').empty? }
final_names = %w[cleanup-build cleanup-relink compare-shared-0 compare-shared-1 compare-shared-2 payload-bounded native-configured]
final_names.each do |name|
  g = json(root+'/'+name+'.guard.json')
  abort "failed final guard: #{name}" unless g.fetch('exitCode') == 0 && !g.fetch('guardTriggered')
end
comparisons = (0...3).map { |i| json(root+"/compare-shared-#{i}/result.json") }
comparisons.each_with_index do |c,i|
  abort 'wrong frozen comparison or changed bits/order/coverage' unless c.fetch('repetition') == i && c.fetch('keys') == 3125 && c.fetch('allFloatBitsCoverageAndFullOrderEqual')
  abort 'source encoder unexpectedly started' unless c.fetch('firstStats').fetch('modelStarts') == 0 && c.fetch('repeatStats').fetch('modelStarts') == 0
  abort 'raw worker not reused' unless c.fetch('firstStats').fetch('rawStarts') == 1 && c.fetch('repeatStats').fetch('rawStarts') == 1 && c.fetch('firstStats').fetch('rawPid') == c.fetch('repeatStats').fetch('rawPid')
  abort 'resident blocks revalidated' unless c.fetch('residentBlockMisses') == 0 && c.fetch('residentBlockHits') == 3125
  abort 'numerical recovery fixture failed' unless c.fetch('synthetic').values.all?
  abort 'last owner not closed' unless json(root+"/compare-shared-#{i}/lifecycle.json").fetch('lastOwnerClosed')
end
abort 'different source matrix between repetitions' unless comparisons.map { |c| c.fetch('originalMatrix') }.uniq.size == 1
source_check = json(root+'/relocated-fixture-check.json')
originals = source_check.fetch('files').map do |f|
  actual = binding(f.fetch('path'))
  abort 'original source/lexical file changed' unless actual.fetch(:sha256) == f.fetch('sha256') && actual.fetch(:bytes) == f.fetch('bytes')
  actual
end
native = json(root+'/native-50000-configured/summary.json')
abort 'wrong native cohort' unless native.fetch('pairs') == 3 && native.fetch('answeringModelCalls') == 0 && native.fetch('cases').size == 6
abort 'staged runtime changed' unless binding(native.fetch('runtime')).fetch(:sha256) == native.fetch('runtimeSha256') && native.fetch('runtimeSha256') == binding(root+'/eggshell').fetch(:sha256)
native.fetch('cases').each do |c|
  abort 'native deadline/completion/stratum failed' unless c.fetch('exitCode') == 0 && c.fetch('replyComplete') && c.fetch('validStratum') && c.fetch('totalMs') < 30000
  trace = c.fetch('search').fetch('trace')
  abort 'semantic fallback or foreground repair' unless trace.fetch('semantic') == 'completed' && trace.fetch('route') == 'configured' && trace.fetch('warmRequests') == 0
  abort 'missing original body' if c.fetch('phase') == 'first' && !c.fetch('originalBody')
  abort 'continued response repeated original text' if c.fetch('phase') == 'continued' && c.fetch('bodyBytes') != 0
end
3.times do |i|
  shutdown = json(root+"/native-50000-configured/pair-#{i}-shutdown.json")
  abort 'native manager did not exit' unless shutdown.fetch('acknowledged') && shutdown.fetch('endpointRemoved') && shutdown.fetch('daemonExitCode') == 0
end
parent = root+'/references/native-parent'
body_comparisons = %w[first continued].map do |phase|
  a = binding(parent+'/pair-0-'+phase+'/body.txt')
  b = binding(root+'/native-50000-configured/pair-0-'+phase+'/body.txt')
  {phase:phase,reference:a,candidate:b,equal:a.fetch(:sha256)==b.fetch(:sha256) && a.fetch(:bytes)==b.fetch(:bytes)}
end
abort 'same-question native body changed' unless body_comparisons.all? { |c| c.fetch(:equal) }
sources = %w[Eggshell/BlockScore.lean Eggshell/Numerical.lean Eggshell/SearchProvider.lean Eggshell/Warm.lean Main.lean runtime/block_score.py tools/research/BlockScoreAudit.lean tools/research/NativeHookAudit.lean tools/research/PrepareNativePayload.lean].map { |p| binding(root+'/checkout/'+p).merge(relative:p) }
encoder = binding(root+'/checkout/runtime/embedding.py')
abort 'source encoder changed' unless encoder.fetch(:sha256) == '1417508ca8aee8ee45bff632925ff6a23447d0d1a766d1c7411b775bc10a83f4'
evidence = Dir.glob(root+'/*.{json,log,rb,txt}').reject { |p| %w[review.json review.check.json].include?(File.basename(p)) }
%w[compare-0 compare-shared-0 compare-shared-1 compare-shared-2 native-50000 native-50000-configured native-preparation references/native-parent].each do |d|
  evidence += Dir.glob(root+'/'+d+'/**/*').select { |p| File.file?(p) }
end
linked = Shellwords.split(File.read(root+'/runtime.rsp')).select { |p| File.file?(p) }.uniq.sort.map { |p| binding(p) }
record = {
  candidate:'daemon-owned-raw-block-scoring',parentCommit:'0954b689edf72d653f78e37c826337d17d9b79b8',adopted:false,productRuntimeChanged:false,
  answeringModelCalls:0,seedCalls:0,sourceEmbeddingCalls:0,queryEmbedding:'MiniLM only during native calls; no answering model',
  inclusiveTokenComparison:false,qualityQualification:false,requiredHistoryRecallQualification:false,millionWindowQualification:false,
  numericalBoundary:{originalEncoder:encoder,extensionOnly:'binary64 pipe frames into the original per-row float32 NumPy dot primitive; no storage, extraction, selection, or authority in Python'},
  sources:sources,plan:json(root+'/plan.json'),comparisons:comparisons,componentTimingCaveat:'OS cache not flushed. Repetition 1 overlapped with an independent read-only fixture checksum audit during its initial seconds; not a quiet timing replication.',
  failedInitialProbe:json(root+'/compare-0/result.json'),native:native,nativeBodyComparisons:body_comparisons,
  proofs:['Eggshell.BlockScore.Frame.byte_count'],originalFiles:originals,sourceFilesUnchanged:true,
  generated:Dir.glob(root+'/*.{c,o,rsp}').sort.map { |p| binding(p) },linkedInputs:linked,
  evidence:evidence.uniq.sort.map { |p| binding(p) },
  guards:all_guards.map { |p,g| binding(p).merge(exitCode:g.fetch('exitCode'),peakRssKiB:g.fetch('sampledPeakRssKiB'),guardTriggered:g.fetch('guardTriggered')) },
  maximumAggregateRssKiB:all_guards.map { |_,g| g.fetch('sampledPeakRssKiB') }.max,limitRssKiB:3670016,userCeilingRssKiB:4194304,
  failures:['first raw probe matched all bits/order but was slower because derived PageMap cache was reset every batch',
    'initial builds had layout/import/link errors; no stale executable is used as final evidence',
    'one shared-pages build child exited zero but minimum-free-disk guard rejected it; a later post-cleanup build passed',
    'first native payload helper used reserved Lean keyword prefix; second used too small a Lean memory setting; bounded single-worker run passed',
    'first native cohort omitted PLUGIN_ROOT for direct hook clients, causing lifecycle-generation mismatch and replacement; owned-teardown check failed and the guard recovered leftovers. Both clients and manager use the same product prefix in the final fresh cohort'],
  archivesCreated:false,
  limitations:['three component repetitions are not inclusive-token/quality/required-history evidence',
    'native synthetic first/continued cohorts are not LLVM topic 1/2/3, an MCP server, Pre/Post scale, or p99',
    'only native pair 0 has a saved same-question parent body comparison; old parent executable was deleted as requested',
    'point row-directory lookups remain; dense-block publication still rebuilds on basis changes',
    'axis router unchanged; data-dependent routing, safe score bounds, recommendation recall, and hybrid delivery remain unqualified',
    'normal federation still uses the earlier global catalogue; million-plus and shared parallel use unfinished']
}
File.write(root+'/review.json',JSON.pretty_generate(record)+"\n")
puts JSON.generate({sources:sources.size,componentRepetitions:comparisons.size,nativeCases:native.fetch('cases').size,peakRssKiB:record.fetch(:maximumAggregateRssKiB),adopted:false})
