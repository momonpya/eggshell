require 'json'
require 'digest'

path=File.expand_path('../../../docs/candidates/source-stream-review.json',__dir__)
r=JSON.parse(File.read(path))
%w[adopted productRuntimeChanged inclusiveTokenComparison qualityQualification requiredHistoryRecallQualification
   millionWindowQualification heldoutHundredInquiryQualification sharedConcurrentQualification prePostScaleQualification
   sourceSegmentCacheRetired safeFloatPruningClaimed newPythonImplementation wholeMutationWarmIncrementalQualified].each do |key|
  abort "unqualified claim: #{key}" unless r.fetch(key)==false
end
abort 'model accounting differs' unless r.values_at('answeringModelCalls','newSeedCalls','successfulLocalSourceEmbeddingWindows')==[0,0,1]
bindings=%w[sources runtimeSources linkedInputs frozenInputs modelFiles mutationState evidence guards].flat_map{|k|r.fetch(k)}+
  [r.fetch('runtime'),r.fetch('payload'),r.fetch('parentRecord'),r.fetch('native').fetch('summary'),r.fetch('direct').fetch('reference'),r.fetch('direct').fetch('candidate')]
bindings=bindings.uniq{|x|x.fetch('path')}
bindings.each do |file|
  p=file.fetch('path')
  abort "missing/changed evidence: #{p}" unless File.file?(p)&&File.size(p)==file.fetch('bytes')&&Digest::SHA256.file(p).hexdigest==file.fetch('sha256')
end
r.fetch('sources').each do |file|
  p=File.join(__dir__,file.fetch('relative'))
  abort "source checkpoint differs: #{p}" unless File.file?(p)&&Digest::SHA256.file(p).hexdigest==file.fetch('sha256')
end
abort 'payload differs' unless r.fetch('runtime').fetch('sha256')==r.fetch('payload').fetch('sha256')
abort 'retired domain remains imported' unless (r.fetch('runtimeModules')&%w[Eggshell.CandidateDomain Eggshell.WorkPostings]).empty?
guards=r.fetch('guards').map{|x|[File.basename(x.fetch('path'),'.guard.json'),JSON.parse(File.read(x.fetch('path')))]}.to_h
abort 'guard remains running' unless guards.size==19&&guards.values.all?{|x|x.fetch('state')=='finished'&&x.fetch('ownedPids').empty?}
r.fetch('finalGuards').each{|n|x=guards.fetch(n);abort "final guard failed: #{n}" unless x.fetch('exitCode')==0&&!x.fetch('guardTriggered')}
abort 'RSS exceeds agreed boundary' unless r.fetch('maximumAggregateRssKiB')==guards.values.map{|x|x.fetch('sampledPeakRssKiB')}.max&&r.fetch('maximumAggregateRssKiB')<=3670016
abort 'disk failure omitted' unless guards.fetch('mutation-first').values_at('exitCode','guardTriggered','reason')==[137,true,'disk-space']
f=r.fetch('fixture')
abort 'sample checks incomplete' unless f.fetch('sampleSortTakeChecks')==10
%w[sourceOrderEqual warmPlanEqual sharedReferencesEqual incompleteRejected oldPinPreserved].each{|k|abort "fixture failed: #{k}" unless f.fetch(k)}
s=r.fetch('scale');p=s.fetch('prepared')
abort 'scale domain differs' unless s.values_at('owners','originalWindows','projectionMetadataRows','sampleRows','comparedRecords')==[49969,50000,99969,16384,51535]
%w[sampleEqual originalReferencesEqual allPartitionRecordsEqual].each{|k|abort "scale comparison failed: #{k}" unless s.fetch(k)&&r.fetch('finalScale').fetch(k)}
abort 'sample residency unbounded' unless p.fetch('peakSampleRows')==16384&&p.fetch('projectionRows')==66384
zero_warm=lambda do |w|
  abort 'warm is not unchanged' unless w.values_at('scope','planReason','changedOwners','requested','batches')==['publication-delta','source-unchanged',0,0,0]
  abort 'retired domain still emitted' if w.key?('domain')
  abort 'unchanged warm rewrote projections' unless w.fetch('projections').values_at('produced','added','writtenBytes')==[0,0,0]
  abort 'unchanged warm rewrote model' unless w.fetch('partition').values_at('mode','projectionRows','writtenBytes')==['warm',0,0]
end
zero_warm.call(r.fetch('repeatWarm'));zero_warm.call(r.fetch('mutationRepeat'))
m=r.fetch('mutationWarm')
abort 'whole warm scope differs' unless m.values_at('scope','planReason','changedOwners','publications','requested')==['publication-delta','verified-source-history',1,1,1]
abort 'whole warm qualifier hides remaining latency' unless r.fetch('wholeMutationWarmMeasured')&&m.fetch('elapsedMs')>30000
abort 'whole warm re-encoded old population' unless m.fetch('projections').values_at('produced','added','reused','requested','rows')==[1,1,1,2,99971]
abort 'delta model scanned/retrained' unless m.fetch('partition').values_at('mode','points','projectionRows','trainingMs','touchedCells')==['publication-delta',50001,1,0,1]
abort 'delta owner/lexical coverage differs' unless m.fetch('windowOwners').values_at('mode','changedOwners','added')==['publication-delta',1,1]&&m.fetch('lexical').values_at('added','removed','hydrated')==[1,0,1]
r.fetch('mutationInputs').fetch('files').each do |before|
  after=r.fetch('mutationState').find{|x|x.fetch('path')==before.fetch('path')}
  abort 'source mutation warm wrote the original DB' unless after==before
end
n=r.fetch('native');actual=JSON.parse(File.read(n.fetch('summary').fetch('path')))
abort 'native cohort incomplete' unless n.values_at('pairs','semanticCompleted')==[3,6]&&actual.fetch('cases').size==6
root=File.dirname(r.fetch('runtime').fetch('path'))
actual.fetch('cases').each do |c|
  name="pair-#{c.fetch('pair')}-#{c.fetch('phase')}"
  stdout=File.binread(root+'/native-50000/'+name+'/stdout.json');body=File.binread(root+'/native-50000/'+name+'/body.txt')
  p=c.fetch('publication');pub=p.fetch('published')
  abort "stdout/ACK mismatch #{name}" unless pub.fetch('output')==stdout&&pub.fetch('sha256')==Digest::SHA256.hexdigest(stdout)
  abort "body mismatch #{name}" unless c.fetch('bodyBytes')==body.bytesize&&c.fetch('bodySha256')==Digest::SHA256.hexdigest(body)
  abort "native semantic/deadline failed #{name}" unless c.fetch('validStratum')&&c.fetch('replyComplete')&&c.fetch('exitCode')==0&&c.fetch('totalMs')<30000&&p.fetch('search').fetch('trace').values_at('semantic','warmRequests')==['completed',0]
  abort 'original body/ACK missing' if c.fetch('phase')=='first'&&(!c.fetch('originalBody')||!p.fetch('ack'))
  abort 'continued history differs' if c.fetch('phase')=='continued'&&(!body.empty?||c.fetch('historyBefore')!=c.fetch('acknowledgedHistory'))
end
abort 'parent body changed' unless n.fetch('comparisons').size==6&&n.fetch('comparisons').all?{|x|x.fetch('bodyEqual')}
d=r.fetch('direct');a=JSON.parse(File.read(d.fetch('candidate').fetch('path')))
abort 'complete same-candidate response changed' unless d.fetch('completeResponseEqual')&&a==JSON.parse(File.read(d.fetch('reference').fetch('path')))&&a.fetch('ranked').size==4101
r.fetch('cleanup').each_value do |cleanup|
  abort 'archive was created' unless cleanup.fetch('archivesCreated')==0
  cleanup.fetch('removed').each{|x|p=x.fetch('path');abort "retired artifact remains: #{p}" if File.exist?(p)||File.symlink?(p)}
end
puts({evidenceBindings:bindings.size,nativeSemanticCompleted:6,modelRecordsCompared:s.fetch('comparedRecords'),warmUnchangedMs:r.fetch('repeatWarm').fetch('elapsedMs'),wholeMutationWarmMs:m.fetch('elapsedMs'),adopted:false,recordSha256:Digest::SHA256.file(path).hexdigest}.to_json)
