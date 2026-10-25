require 'json'
require 'digest'
rpath=File.expand_path('../../../docs/candidates/canonical-delta-review.json',__dir__)
r=JSON.parse(File.read(rpath))
%w[adopted productRuntimeChanged inclusiveTokenComparison qualityQualification millionWindowQualification
 wholeMutationWarmIncrementalQualified heldoutHundredInquiryQualification sharedConcurrentQualification
 prePostScaleQualification mcpStoragePolicyQualified physicalCompactionQualified allCanonicalPayloadWorkDelta
 newPythonImplementation].each{|k|abort "unqualified claim #{k}" unless r.fetch(k)==false}
abort 'model accounting differs' unless r.values_at('answeringModelCalls','newSeedCalls','successfulLocalSourceEmbeddingWindows')==[0,0,1]
files=%w[sources runtimeSources linkedInputs frozenInputs modelFiles mutationState mutationBasisFiles evidence guards].flat_map{|k|r.fetch(k)}+
  [r.fetch('runtime'),r.fetch('payload'),r.fetch('parentRecord'),r.fetch('native').fetch('summary')]
files=files.uniq{|x|x.fetch('path')}
files.each do |x|
  p=x.fetch('path')
  abort "missing or changed #{p}" unless File.file?(p)&&File.size(p)==x.fetch('bytes')&&Digest::SHA256.file(p).hexdigest==x.fetch('sha256')
end
r.fetch('sources').each do |x|
  p=File.join(__dir__,x.fetch('relative'))
  abort "source checkpoint differs #{p}" unless File.file?(p)&&Digest::SHA256.file(p).hexdigest==x.fetch('sha256')
end
abort 'payload differs' unless r.fetch('runtime').fetch('sha256')==r.fetch('payload').fetch('sha256')
guards=r.fetch('guards').map{|f|[File.basename(f.fetch('path'),'.guard.json'),JSON.parse(File.read(f.fetch('path')))]}.to_h
abort 'guard missing or active' unless guards.size==11&&guards.values.all?{|g|g.fetch('state')=='finished'&&g.fetch('ownedPids').empty?}
r.fetch('finalGuards').each do |name|
  g=guards.fetch(name);abort "failed final guard #{name}" unless g.fetch('exitCode')==0&&!g.fetch('guardTriggered')
end
%w[build build-retry1].each{|n|abort 'compiler failure omitted' unless guards.fetch(n).fetch('exitCode')==1}
abort 'memory ceiling violated' unless r.fetch('maximumAggregateRssKiB')==guards.values.map{|g|g.fetch('sampledPeakRssKiB')}.max&&r.fetch('maximumAggregateRssKiB')<=3670016
r.fetch('fixture').each{|k,v|abort "fixture failed #{k}" unless k=='answeringModelCalls' ? v==0 : v==true}
m=r.fetch('mutationWarm');c=m.fetch('canonical')
abort 'canonical delta did not use original changed owner' unless c.values_at('mode','changedOwners','hydrated')==['publication-delta',1,1]
abort 'warm delta differs' unless m.values_at('scope','planReason','changedOwners','publications','requested','batches')==['publication-delta','verified-source-history',1,1,1,1]
abort 'original model/focus changed' unless m.fetch('after').fetch('encoderContract')==r.fetch('parentWholeWarm').fetch('after').fetch('encoderContract')&&m.fetch('after').fetch('focusContract')==r.fetch('parentWholeWarm').fetch('after').fetch('focusContract')
abort 'old population re-embedded' unless m.fetch('projections').values_at('produced','added','reused','requested','rows')==[1,1,1,2,99971]
abort 'routing retrained or scanned' unless m.fetch('partition').values_at('mode','points','projectionRows','trainingMs','touchedCells')==['publication-delta',50001,1,0,1]
abort 'lexical delta differs' unless m.fetch('lexical').values_at('added','removed','hydrated')==[1,0,1]
repeat=r.fetch('mutationRepeat')
abort 'repeat is not empty' unless repeat.values_at('planReason','requested','batches')==['source-unchanged',0,0]
abort 'repeat rehydrated originals' unless repeat.fetch('canonical').values_at('mode','changedOwners','hydrated')==['warm',0,0]
abort 'repeat appended projections/routing' unless repeat.fetch('projections').fetch('writtenBytes')==0&&repeat.fetch('partition').fetch('writtenBytes')==0
r.fetch('mutationInputs').fetch('files').each{|f|abort 'original mutation source changed' unless r.fetch('mutationState').include?(f)}
summary=JSON.parse(File.read(r.fetch('native').fetch('summary').fetch('path')))
abort 'native cohort missing' unless summary.fetch('pairs')==3&&summary.fetch('cases').size==6
root=File.dirname(r.fetch('runtime').fetch('path'))
summary.fetch('cases').each do |x|
  name="pair-#{x.fetch('pair')}-#{x.fetch('phase')}"
  body=File.binread(root+'/native-50000/'+name+'/body.txt')
  stdout=File.binread(root+'/native-50000/'+name+'/stdout.json')
  p=x.fetch('publication');pub=p.fetch('published')
  abort "native deadline/semantic failed #{name}" unless x.fetch('validStratum')&&x.fetch('replyComplete')&&x.fetch('exitCode')==0&&x.fetch('totalMs')<30000&&p.fetch('search').fetch('trace').values_at('semantic','warmRequests')==['completed',0]
  abort "stdout mismatch #{name}" unless pub.fetch('output')==stdout&&pub.fetch('sha256')==Digest::SHA256.hexdigest(stdout)
  abort "body mismatch #{name}" unless x.fetch('bodyBytes')==body.bytesize&&x.fetch('bodySha256')==Digest::SHA256.hexdigest(body)
  abort 'initial history missing' if x.fetch('phase')=='first'&&(!x.fetch('originalBody')||!p.fetch('ack'))
  abort 'continued history mismatch' if x.fetch('phase')=='continued'&&(!body.empty?||x.fetch('historyBefore')!=x.fetch('acknowledgedHistory'))
end
abort 'parent body changed' unless r.fetch('native').fetch('comparisons').size==6&&r.fetch('native').fetch('comparisons').all?{|x|x.fetch('bodyEqual')}
cleanup=JSON.parse(File.read(root+'/completed-mutation-cleanup.json'))
abort 'trial cache archived or retained' unless cleanup.fetch('archivesCreated')==0&&cleanup.fetch('removed').all?{|x|!File.exist?(x.fetch('path'))}
puts({evidenceBindings:files.size,canonicalDeltaMs:c.fetch('elapsedMs'),wholeWarmMs:m.fetch('elapsedMs'),
 nativeSemanticCompleted:6,maximumAggregateRssKiB:r.fetch('maximumAggregateRssKiB'),adopted:false,
 recordSha256:Digest::SHA256.file(rpath).hexdigest}.to_json)
