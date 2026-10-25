require 'json'
require 'digest'

path = File.expand_path('../../../docs/candidates/partition-native-review.json', __dir__)
r = JSON.parse(File.read(path))
abort 'candidate adopted without matched token/quality evidence' unless
  %w[adopted productRuntimeChanged inclusiveTokenComparison qualityQualification requiredHistoryRecallQualification
     millionWindowQualification safeFloatPruningClaimed newPythonImplementation].all? { |k| r.fetch(k) == false }
abort 'unexpected model calls' unless %w[answeringModelCalls newSeedCalls sourceEmbeddingCalls].all? { |k| r.fetch(k) == 0 }
abort 'failed semantic gate reported as qualified' unless r.fetch('nativeSemanticQualification') == false
bindings = %w[sources originalFiles originalNumericalFiles linkedInputs generated evidence guards].flat_map { |k| r.fetch(k) }
bindings += [r.fetch('runtime'),r.fetch('payload')]
bindings.uniq { |f| f.fetch('path') }.each do |f|
  p = f.fetch('path')
  abort "missing/changed evidence: #{p}" unless File.file?(p) && File.size(p) == f.fetch('bytes') &&
    Digest::SHA256.file(p).hexdigest == f.fetch('sha256')
end
r.fetch('sources').each do |f|
  p = File.join(__dir__, f.fetch('relative'))
  abort "checkpoint differs: #{p}" unless Digest::SHA256.file(p).hexdigest == f.fetch('sha256')
end
guards = r.fetch('guards').map { |f| [File.basename(f.fetch('path')),JSON.parse(File.read(f.fetch('path')))] }.to_h
%w[build-neutral fixture-neutral payload native].each do |name|
  g = guards.fetch(name + '.guard.json')
  abort "failed final guard: #{name}" unless g.fetch('state') == 'finished' && g.fetch('exitCode') == 0 &&
    !g.fetch('guardTriggered') && g.fetch('ownedPids').empty?
end
abort 'aggregate memory ceiling exceeded' unless r.fetch('maximumAggregateRssKiB') <= r.fetch('limitRssKiB') &&
  r.fetch('limitRssKiB') <= 3670016
abort 'different preparation and native source' unless r.fetch('warm').fetch('after').fetch('database').fetch('database') ==
  r.fetch('source').fetch('identity')
abort 'repeat warm wrote another learned index' unless r.fetch('repeatWarm').fetch('partition').values_at('mode','writtenBytes') == ['warm',0]
native = r.fetch('native')
abort 'wrong native repetitions' unless native.fetch('pairs') == 3 && native.fetch('cases').size == 6
abort 'negative integrated cohort disappeared' unless r.fetch('beforeInline').size == 6 &&
  r.fetch('beforeInline').all? { |c| c.fetch('search').fetch('trace').fetch('semantic') == 'timedOut' }
abort 'final incomplete stratum disappeared' unless native.fetch('semanticCompleted') == 5 &&
  native.fetch('cases').first.fetch('semanticCompleted') == false
native.fetch('cases').each do |c|
  abort 'native delivery incomplete or over deadline' unless c.fetch('totalMs') < 30000 && c.fetch('replyComplete') &&
    c.fetch('exitCode') == 0 && c.fetch('validStratum')
  route = c.fetch('route')
  abort 'lost scope, bound or incomplete-coverage signal' unless route.fetch('source') == r.fetch('source') &&
    route.values_at('keys','keyAllowance','unseenVectorKeys','totalCells') == [4096,4096,45904,512] &&
    route.fetch('safeFloatPruning') == false
  if c.fetch('semanticCompleted')
    abort 'scored coverage missing' unless c.fetch('coverage').fetch('approximate') &&
      c.fetch('search').fetch('trace').values_at('semantic','warmRequests') == ['completed',0]
  else
    abort 'timeout hidden' unless c.fetch('coverage').nil? &&
      c.fetch('search').fetch('trace').values_at('semantic','route') == ['timedOut','lexical']
  end
  expected = c.fetch('phase') == 'first' ?
    c.fetch('originalBody') && c.fetch('bodyBytes') > 0 && c.fetch('historyBefore') == 0 :
    c.fetch('bodyBytes') == 0 && c.fetch('historyBefore') > 0
  abort 'wrong delivery stratum' unless expected
end
compare = r.fetch('directComparison')
abort 'full provider result changed' unless compare.fetch('allRankedWindowsRelatedAndCoverageEqual') &&
  JSON.parse(File.read(compare.fetch('reference').fetch('path'))) == JSON.parse(File.read(compare.fetch('candidate').fetch('path')))
puts JSON.generate({evidenceBindings:bindings.map { |f| f.fetch('path') }.uniq.size,nativeCalls:6,
  semanticCompleted:5,nativeSemanticQualified:false,fixtureBudgetCases:r.fetch('fixture').fetch('budgetCases'),adopted:false,
  recordSha256:Digest::SHA256.file(path).hexdigest})
