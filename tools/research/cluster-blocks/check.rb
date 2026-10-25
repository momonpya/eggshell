require 'json'
require 'digest'

path=File.expand_path('../../../docs/candidates/cluster-blocks-review.json',__dir__)
r=JSON.parse(File.read(path))
abort 'candidate adopted without token/quality qualification' unless
  %w[adopted productRuntimeChanged inclusiveTokenComparison qualityQualification requiredHistoryRecallQualification
     millionWindowQualification safeFloatPruningClaimed newPythonImplementation].all?{|k|r.fetch(k)==false}
abort 'unexpected model calls' unless %w[answeringModelCalls newSeedCalls sourceEmbeddingCalls].all?{|k|r.fetch(k)==0}
bindings=%w[sources originalFiles generated linkedInputs evidence guards].flat_map{|k|r.fetch(k)}+[r.fetch('runtime'),r.fetch('payload')]
bindings += r.fetch('bodyComparisons').flat_map{|c|[c.fetch('reference'),c.fetch('candidate')]}
bindings += [r.fetch('directComparison').fetch('reference'),r.fetch('directComparison').fetch('candidate')]
bindings.uniq{|f|f.fetch('path')}.each do |f|
  p=f.fetch('path')
  abort "missing/changed evidence: #{p}" unless File.file?(p) && File.size(p)==f.fetch('bytes') &&
    Digest::SHA256.file(p).hexdigest==f.fetch('sha256')
end
r.fetch('sources').each do |f|
  p=File.join(__dir__,f.fetch('relative'))
  abort "checkpoint differs: #{p}" unless Digest::SHA256.file(p).hexdigest==f.fetch('sha256')
end
guards=r.fetch('guards').map{|f|[File.basename(f.fetch('path')),JSON.parse(File.read(f.fetch('path')))]}.to_h
%w[build-buffer build-audit fixture payload warm-first scale warm-repeat native direct].each do |name|
  g=guards.fetch(name+'.guard.json')
  abort "failed final guard: #{name}" unless g.fetch('state')=='finished' && g.fetch('exitCode')==0 &&
    !g.fetch('guardTriggered') && g.fetch('ownedPids').empty?
end
abort 'resource ceiling exceeded' unless r.fetch('maximumAggregateRssKiB')<=3670016 &&
  r.fetch('warm').fetch('clustered').fetch('peakBufferedBytes')<=67108864
abort 'complete bit audit missing' unless r.fetch('scale').values_at('rows','bytes','allOriginalBitsAndCoverageEqual')==
  [99969,307104768,true]
abort 'repeat warm rewrote physical data' unless r.fetch('repeatWarm').fetch('clustered').values_at('mode','writtenBytes')==['warm',0]
native=r.fetch('native')
abort 'native semantic/deadline gate not met' unless r.fetch('nativeSemanticQualification') &&
  native.fetch('pairs')==3 && native.fetch('cases').size==6 && native.fetch('semanticCompleted')==6
native.fetch('cases').each do |c|
  abort 'native reply or semantic gate failed' unless c.fetch('totalMs')<30000 && c.fetch('replyComplete') &&
    c.fetch('exitCode')==0 && c.fetch('validStratum') &&
    c.fetch('search').fetch('trace').values_at('semantic','warmRequests')==['completed',0]
end
comparison=r.fetch('directComparison')
abort 'complete provider result changed' unless comparison.fetch('allRankedWindowsRelatedAndCoverageEqual') &&
  JSON.parse(File.read(comparison.fetch('reference').fetch('path')))==JSON.parse(File.read(comparison.fetch('candidate').fetch('path')))
abort 'existing semantic body changed' unless r.fetch('bodyComparisons').size==2 &&
  r.fetch('bodyComparisons').all?{|c|c.fetch('equal') && c.fetch('reference').fetch('sha256')==c.fetch('candidate').fetch('sha256')}
puts({evidenceBindings:bindings.map{|f|f.fetch('path')}.uniq.size,comparedRows:99969,nativeCalls:6,
  semanticCompleted:6,adopted:false,recordSha256:Digest::SHA256.file(path).hexdigest}.to_json)
