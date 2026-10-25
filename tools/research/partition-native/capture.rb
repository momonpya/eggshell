require 'json'
require 'digest'
require 'shellwords'

root = File.expand_path(__dir__)
final = root + '/inline-hash'
def json(path); JSON.parse(File.read(path)); end
def binding(path); {path:path,bytes:File.size(path),sha256:Digest::SHA256.file(path).hexdigest}; end
def same_file!(file)
  actual = binding(file.fetch('path'))
  abort "changed frozen input: #{file.fetch('path')}" unless actual[:bytes] == file.fetch('bytes') &&
    actual[:sha256] == file.fetch('sha256')
  actual
end
plan = json(root + '/native-plan.json')
finalPlan = json(final + '/native-plan.json')
guards = (Dir.glob(root + '/*.guard.json') + Dir.glob(final + '/*.guard.json')).sort.map { |p| [p,json(p)] }
abort 'owned work still active' unless guards.all? { |_,g|
  g.fetch('state') == 'finished' && g.fetch('ownedPids').empty? }
%w[build-neutral fixture-neutral payload native].each do |name|
  g = json(root + '/' + name + '.guard.json')
  abort "failed final #{name}" unless g.fetch('exitCode') == 0 && !g.fetch('guardTriggered')
end
%w[build payload direct native].each do |name|
  g = json(final + '/' + name + '.guard.json')
  abort "failed final hash #{name}" unless g.fetch('exitCode') == 0 && !g.fetch('guardTriggered')
end
fixture = json(root + '/fixture-neutral/result.json')
abort 'fixture incomplete' unless fixture.values_at('originalKeys','updatedKeys','budgetCases','modelCalls') == [65,66,256,0] &&
  %w[coldDoesNotPrepare unchangedNoWrite neutralPublicationReused changedOriginalUnavailable
     oldPinnedPreserved foreignDbRejected originalTieOrder zeroAllowanceNoRead].all? { |k| fixture.fetch(k) }
native = json(final + '/native-50000/summary.json')
baseline = json(root + '/native-50000/summary.json')
abort 'different runtime or source' unless native.fetch('runtimeSha256') == finalPlan.fetch('runtimeSha256') &&
  native.fetch('pairs') == plan.fetch('pairs') && native.fetch('answeringModelCalls') == 0
source = native.fetch('source')
abort 'baseline source mismatch' unless baseline.fetch('source') == source
originals = plan.fetch('sourceFiles').map { |f| same_file!(f) }
numerical = plan.fetch('originalNumericalFiles').map { |f| same_file!(f) }
plan.fetch('sources').each { |f| same_file!(f) }
same_file!(plan.fetch('runtime'))
same_file!(plan.fetch('settings'))
abort 'different staged runtime' unless binding(final + '/prefix/libexec/eggshell')[:sha256] == native.fetch('runtimeSha256')
abort 'hash expression changed' unless File.read(final + '/checkout/Eggshell/Blake3.lean').gsub('@[inline] ','') ==
  File.read(root + '/checkout/Eggshell/Blake3.lean')
abort 'complete provider result changed' unless json(root + '/direct.stdout.json') == json(final + '/direct.stdout.json')

warm = json(root + '/native-50000/private-warm.stdout.json').fetch('databases').fetch(0)
repeat = json(root + '/native-50000/repeat-warm.stdout.json').fetch('databases').fetch(0)
[warm,repeat].each do |w|
  abort 'new source embeddings or missing coverage' unless w.fetch('requested') == 0 &&
    w.fetch('after').values_at('missing','invalid') == [0,0] &&
    w.fetch('projections').values_at('produced','writtenBytes') == [0,0] &&
    w.fetch('routing').fetch('writtenBytes') == 0 && w.fetch('blocks').fetch('writtenBytes') == 0
end
abort 'learned partition was not prepared exactly once' unless warm.fetch('partition').fetch('mode') == 'prepared' &&
  repeat.fetch('partition').values_at('mode','writtenBytes') == ['warm',0]

cases = native.fetch('cases')
abort 'missing native strata' unless cases.map { |c| [c.fetch('pair'),c.fetch('phase')] } ==
  (0...plan.fetch('pairs')).flat_map { |i| [[i,'first'],[i,'continued']] }
summaries = cases.map do |c|
  abort 'native hook incomplete, wrong stratum, or past deadline' unless c.fetch('totalMs') < plan.fetch('deadlineMs') &&
    c.fetch('exitCode') == 0 && c.fetch('replyComplete') && c.fetch('validStratum') &&
    c.fetch('question') == plan.fetch('queries').fetch(c.fetch('pair'))
  completed = c.fetch('search').fetch('trace').fetch('semantic') == 'completed'
  label = "pair-#{c.fetch('pair')}-#{c.fetch('phase')}"
  body = File.binread(final + '/native-50000/' + label + '/body.txt')
  stdout = File.binread(final + '/native-50000/' + label + '/stdout.json')
  abort 'actual body differs from receipt' unless body.bytesize == c.fetch('bodyBytes') &&
    Digest::SHA256.hexdigest(body) == c.fetch('bodySha256')
  published = c.fetch('publication').fetch('published')
  ack = c.fetch('publication').fetch('ack')
  abort 'stdout mismatch' unless published.fetch('output') == stdout &&
    published.fetch('bytes') == stdout.bytesize && published.fetch('sha256') == Digest::SHA256.hexdigest(stdout)
  if c.fetch('phase') == 'first'
    abort 'offered original body was not acknowledged' unless ack.fetch('data').fetch('rpcCompleted') &&
      ack.fetch('data').fetch('offerAccepted')
    abort 'new chat did not receive original evidence' unless c.fetch('historyBefore') == 0 &&
      c.fetch('originalBody') && body.include?('ORIGINAL_CLOCK_BODY_') && c.fetch('acknowledgedHistory') > 0
  else
    earlier = cases.find { |x| x.fetch('pair') == c.fetch('pair') && x.fetch('phase') == 'first' }
    abort 'confirmed history was ignored' unless body.empty? && ack.nil? && c.fetch('historyBefore') > 0 &&
      c.fetch('historyBefore') == earlier.fetch('acknowledgedHistory') &&
      c.fetch('acknowledgedHistory') == c.fetch('historyBefore')
  end
  stages = c.fetch('publication').fetch('stages')
  stages.each do |stage|
    path = c.fetch('publication').fetch('path') + '/' + stage.fetch('name')
    abort 'stage bytes changed' unless File.size(path) == stage.fetch('bytes').to_i &&
      Digest::SHA256.file(path).hexdigest == stage.fetch('sha256')
  end
  entries = stages.map { |s| s.fetch('record') }
  routed = entries.select { |s| s.fetch('stage').start_with?('keyed-partition-') }.map { |s| s.fetch('data') }
  coverage = entries.find { |s| s.fetch('stage') == 'keyed-coverage' }&.fetch('data')
  abort 'unrecorded approximate recommendation' unless routed.size == 1 &&
    (completed ? coverage&.size == 1 : coverage.nil?)
  route = routed.fetch(0)
  covered = coverage&.fetch(0)
  abort 'foreign or unbounded recommendation domain' unless route.fetch('source') == source &&
    route.fetch('basis').fetch('source') == source && route.fetch('basis').fetch('rows') == 50000 &&
    route.fetch('totalCells') == 512 && route.fetch('keys') == 4096 && route.fetch('keyAllowance') == 4096 &&
    route.fetch('unseenVectorKeys') == 50000-route.fetch('keys') && !route.fetch('safeFloatPruning')
  if completed
    abort 'lost scored coverage' unless covered.fetch('approximate') && covered.fetch('routeKeys') == route.fetch('keys') &&
    covered.fetch('routeCells') == route.fetch('cells') && covered.fetch('unseenVectorKeys') == route.fetch('unseenVectorKeys') &&
    covered.fetch('physicalRows') <= plan.fetch('globalPhysicalRowBudget')
  else
    abort 'missing timeout/fallback evidence' unless c.fetch('search').fetch('trace').values_at('semantic','route') == ['timedOut','lexical']
  end
  c.reject { |k,_| %w[publication lastOfferedSearch].include?(k) }.merge(
    'publicationPath'=>c.fetch('publication').fetch('path'),'route'=>route,'coverage'=>covered,'semanticCompleted'=>completed)
end
shutdowns = (0...plan.fetch('pairs')).map do |i|
  path = final + "/native-50000/pair-#{i}-shutdown.json"
  stop = json(path)
  abort 'owned manager did not stop' unless stop.values_at('acknowledged','daemonExitCode','endpointRemoved','phase') ==
    [true,0,true,'stopped']
  binding(path)
end
sources = plan.fetch('sources').map do |f|
  relative = f.fetch('path').delete_prefix(root + '/checkout/')
  binding(f.fetch('path')).merge(relative:relative)
end
sources << binding(final + '/checkout/Eggshell/Blake3.lean').merge(relative:'inline-hash/Eggshell/Blake3.lean')
evidence = Dir.glob(root + '/*.{rb,json,log,txt,rsp}').reject { |p| %w[review.json review.check.json].include?(File.basename(p)) } +
  Dir.glob(final + '/*.{rb,json,log,txt,rsp}').reject { |p| %w[review.json review.check.json].include?(File.basename(p)) } +
  Dir.glob(root + '/native-50000/**/*').select { |p| File.file?(p) } +
  Dir.glob(final + '/native-50000/**/*').select { |p| File.file?(p) } + [root + '/fixture-neutral/result.json']
linked = Shellwords.split(File.read(final + '/runtime.rsp')).select { |p| File.file?(p) }.uniq.map { |p| binding(p) }
directStats = [root,final].map do |directory|
  request = json(directory + '/direct.request.json')
  receipt = '/Users/ovm/.codex/experiments/eggshell/block-score-20261025/scale-data-50000/receipts/' + request.fetch('receipt')
  paths = Dir.glob(receipt + '/*.json').sort
  evidence.concat(paths)
  numericalPath = paths.find { |p| File.basename(p).start_with?('numerical-') }
  state = json(numericalPath).fetch('data')
  abort 'direct provider did not finish every source row' unless state.fetch('status') == 'completed' &&
    state.fetch('counters').fetch('scoredWindows') == 4132
  {path:numericalPath,record:state}
end
record = {
  candidate:'learned-partition-through-native-hooks',parentCommit:'00f02af',adopted:false,
  productRuntimeChanged:false,inclusiveTokenComparison:false,qualityQualification:false,
  requiredHistoryRecallQualification:false,millionWindowQualification:false,safeFloatPruningClaimed:false,
  answeringModelCalls:0,newSeedCalls:0,sourceEmbeddingCalls:0,newPythonImplementation:false,
  plan:plan,finalPlan:finalPlan,source:source,fixture:fixture,warm:warm,repeatWarm:repeat,
  preparationReuse:json(final + '/native-50000/preparation-reuse.json'),
  nativeSemanticQualification:summaries.all? { |c| c.fetch('semanticCompleted') },
  native:{pairs:plan.fetch('pairs'),cases:summaries,shutdowns:shutdowns,
    semanticCompleted:summaries.count { |c| c.fetch('semanticCompleted') }},
  beforeInline:baseline.fetch('cases').map { |c| c.reject { |k,_| %w[publication lastOfferedSearch].include?(k) } },
  directComparison:{allRankedWindowsRelatedAndCoverageEqual:true,owners:json(final + '/direct.stdout.json').fetch('ranked').length,
    reference:binding(root + '/direct.stdout.json'),candidate:binding(final + '/direct.stdout.json')},
  directNumerical:directStats,
  profileScope:'2-second numerical-daemon stack sample; no whole-run percentage or profiled latency claim',
  sourceOrdering:'Original DB ordinal and original within-owner window position determine score ties; source ID stays scoped, identities/windows are preserved by ordinary Lean Perm proofs.',
  recommendation:'Learned 512-cell eligible discovery index, global 4096 original-key budget, followed by unchanged binary64-to-float32 per-row numerical scoring. This budget is the former native ceiling 128*32, not the 3125-key E component experiment.',
  authority:'Complete structural/e-class authority lookup and existing synapses/freshness are unchanged; no nominated key can issue Union or completed.',
  proofs:['Eggshell.PartitionBuild.share_le_total','Eggshell.VectorPartition.training_preserves_samples',
    'Eggshell.VectorPartition.node_roundtrip','Eggshell.KeyedProtocol.scoped_choice_in_original_array',
    'Eggshell.KeyedSearchProvider.canonical_windows_preserved','Eggshell.KeyedSearchProvider.canonical_original_identities'],
  sources:sources,originalFiles:originals,originalNumericalFiles:numerical,
  runtime:binding(final + '/eggshell'),payload:binding(final + '/prefix/libexec/eggshell'),linkedInputs:linked,
  generated:(Dir.glob(root + '/*.{c,o,rsp}') + Dir.glob(final + '/*.{c,o,rsp}')).sort.map { |p| binding(p) },
  evidence:evidence.uniq.sort.map { |p| binding(p) },
  guards:guards.map { |p,g| binding(p).merge(exitCode:g.fetch('exitCode'),guardTriggered:g.fetch('guardTriggered'),peakRssKiB:g.fetch('sampledPeakRssKiB')) },
  maximumAggregateRssKiB:guards.map { |_,g| g.fetch('sampledPeakRssKiB') }.max,
  limitRssKiB:3670016,userCeilingRssKiB:4194304,archivesCreated:0,
  failures:['Initial source symlinks were copied before Lean compilation and artifact symlinks were unlinked to avoid modifying the parent.',
    'Build failures in public-module visibility, namespace, quota proof, Coverage construction and permutation proof were fixed; all failed logs/guards remain.',
    'First fixture lacked its vector-directory parent; next wrote an authoritative key while claiming an empty source delta. The fixture now uses the actual reserved memo namespace and retained publication journal.',
    'One unrun intermediate binary was deleted before final ordering changes; the native plan freezes only the successful final runtime.',
    'Initial integrated native cohort delivered lexical text but all 6 semantic searches timed out; the strict semantic gate failed and its message remains in capture-attempt.log.',
    'Inlining existing Lean hash definitions preserves their expressions and the complete direct provider response, but the final first call still times out: 5/6 semantic completion is not qualified.'],
  limitations:['Synthetic clock DB and three prompt pairs, not independent LLVM topic tasks or p99 qualification.',
    'Final first native call still times out; semantic readiness is not stable and the complete native gate is failed.',
    'Approximate recommendation remains incomplete; unseen rows and partial cells are explicit, with no float32 bound or certified stopping.',
    'Metadata and legacy physical matrix/axis/block basis are still full-rebuild maintenance; no incremental learned partition, storage compaction or million-window claim.',
    'Small fixture checks scoped sources and global budgets, not live multi-DB shared concurrency.',
    'No token, quality or required-code holdout evaluation; strict matched topic 1/2/3 both laps and multiple repetitions remain before adoption.']
}
abort 'aggregate memory ceiling exceeded' unless record.fetch(:maximumAggregateRssKiB) <= 3670016
File.write(root + '/review.json',JSON.pretty_generate(record) + "\n")
puts JSON.generate({calls:summaries.length,firstMs:summaries.select { |c| c['phase']=='first' }.map { |c| c['totalMs'] },
  continuedMs:summaries.select { |c| c['phase']=='continued' }.map { |c| c['totalMs'] },
  maximumAggregateRssKiB:record[:maximumAggregateRssKiB],adopted:false})
