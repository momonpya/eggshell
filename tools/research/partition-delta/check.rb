require 'json'
require 'digest'

path=File.expand_path('../../../docs/candidates/partition-delta-review.json',__dir__)
r=JSON.parse(File.read(path))
%w[adopted productRuntimeChanged inclusiveTokenComparison qualityQualification requiredHistoryRecallQualification
   millionWindowQualification heldoutHundredInquiryQualification sharedConcurrentQualification prePostScaleQualification
   sourceSegmentCacheRetired safeFloatPruningClaimed newPythonImplementation wholeMutationWarmMeasured].each do |key|
  abort "unqualified claim: #{key}" unless r.fetch(key)==false
end
abort 'unexpected answering or seed model' unless r.values_at('answeringModelCalls','newSeedCalls')==[0,0]
abort 'local encoding accounting differs' unless r.values_at('successfulLocalSourceEmbeddingWindows','finalLocalSourceEmbeddingWindows')==[2,1]
bindings=%w[sources frozenInputs modelFiles mutationFiles linkedInputs evidence guards].flat_map{|k|r.fetch(k)}+
  [r.fetch('runtime'),r.fetch('payload'),r.fetch('native').fetch('summary'),r.fetch('directComparison').fetch('reference'),r.fetch('directComparison').fetch('candidate')]
bindings=bindings.uniq{|file|file.fetch('path')}
bindings.each do |file|
  p=file.fetch('path')
  abort "missing/changed evidence: #{p}" unless File.file?(p)&&File.size(p)==file.fetch('bytes')&&Digest::SHA256.file(p).hexdigest==file.fetch('sha256')
end
r.fetch('sources').each do |file|
  p=File.join(__dir__,file.fetch('relative'))
  abort "checkpoint differs: #{p}" unless Digest::SHA256.file(p).hexdigest==file.fetch('sha256')
end
abort 'runtime/payload mismatch' unless r.fetch('runtime').fetch('sha256')==r.fetch('payload').fetch('sha256')
guards=r.fetch('guards').map{|f|[File.basename(f.fetch('path')),JSON.parse(File.read(f.fetch('path')))]}.to_h
abort 'owned work remains' unless guards.values.all?{|g|g.fetch('state')=='finished'&&g.fetch('ownedPids').empty?}
r.fetch('finalGuards').each do |name|
  g=guards.fetch(name+'.guard.json')
  abort "failed final guard #{name}" unless g.fetch('exitCode')==0&&!g.fetch('guardTriggered')
end
abort 'RSS claim differs' unless r.fetch('maximumAggregateRssKiB')==guards.values.map{|g|g.fetch('sampledPeakRssKiB')}.max&&r.fetch('maximumAggregateRssKiB')<=3670016
f=r.fetch('fixture')
%w[sharedReferenceRetained lastReferenceRemoved coordinateReused geometryFrozen oldPinPreserved independentCensus].each{|k|abort "fixture failed #{k}" unless f.fetch(k)}
abort 'small delta scanned the matrix' unless f.fetch('addition').values_at('mode','projectionRows','trainingMs','addedKeys')==['publication-delta',1,0,1]
abort 'dead rows escaped physical budget' unless f.fetch('boundedRows')==2
abort 'focus row entered discovery' unless f.fetch('focusOnly').values_at('projectionRows','changedOwners')==[0,0]
abort 'empty source kept members' unless f.fetch('empty').fetch('points')==0
a=r.fetch('atomic');abort 'partial publication accepted' unless a.values_at('partialPublicationRejected','oldPinPreserved','foreignSourceRebuilt','pendingEditsBeforeFailure')==[true,true,true,2]
p=r.fetch('retention');abort 'projection replacement accepted' unless p.fetch('append').fetch('preserved')&&!p.fetch('replacement').fetch('preserved')&&p.fetch('rebuilt').fetch('mode')=='rebuilt'
m=r.fetch('mutation');delta=m.fetch('prepared')
abort 'large mutation was not a one-row delta' unless delta.values_at('mode','points','projectionRows','trainingMs','changedOwners','addedKeys','touchedCells')==['publication-delta',50001,1,0,1,1,1]
abort 'metadata budget exceeded' unless delta.fetch('retainedMetadataProbes')<=4096
abort 'large mutation read a complete matrix' unless m.fetch('projectionReadBytes')<1024*1024
abort 'membership/geometry/pin changed' unless m.values_at('membershipMatchesIndependentDelta','geometryFrozen','oldPinPreserved','sourceEmbeddingWindows','wholeWarmMeasured')==[true,true,true,1,false]
abort 'repeat update wrote data' unless m.fetch('repeat').values_at('mode','projectionRows','writtenBytes')==['warm',0,0]
r.fetch('retainedPrefixes').each do |prefix|
  digest=Digest::SHA256.new;remaining=prefix.fetch('prefixBytes')
  File.open(prefix.fetch('path'),'rb') do |io|
    while remaining>0
      bytes=io.read([1048576,remaining].min);abort 'short retained prefix' unless bytes
      remaining-=bytes.bytesize;digest.update(bytes)
    end
  end
  abort 'old source/projection prefix changed' unless digest.hexdigest==prefix.fetch('sha256')
end
n=r.fetch('native');native=JSON.parse(File.read(n.fetch('summary').fetch('path')))
abort 'native cohort incomplete' unless n.fetch('pairs')==3&&n.fetch('semanticCompleted')==6&&native.fetch('cases').size==6
root=File.dirname(r.fetch('runtime').fetch('path'))
native.fetch('cases').each do |c|
  label="pair-#{c.fetch('pair')}-#{c.fetch('phase')}"
  stdout=File.binread(root+'/native-retention-50000/'+label+'/stdout.json')
  body=File.binread(root+'/native-retention-50000/'+label+'/body.txt')
  p=c.fetch('publication');pub=p.fetch('published')
  abort "stdout/publication mismatch #{label}" unless pub.fetch('output')==stdout&&pub.fetch('sha256')==Digest::SHA256.hexdigest(stdout)
  abort "body mismatch #{label}" unless c.fetch('bodySha256')==Digest::SHA256.hexdigest(body)&&c.fetch('bodyBytes')==body.bytesize
  abort "native semantic/deadline failed #{label}" unless c.fetch('validStratum')&&c.fetch('replyComplete')&&c.fetch('exitCode')==0&&c.fetch('totalMs')<30000&&p.fetch('search').fetch('trace').values_at('semantic','warmRequests')==['completed',0]
  abort 'missing original ACK' if c.fetch('phase')=='first'&&(!c.fetch('originalBody')||!p.fetch('ack'))
  abort 'incorrect continued delivery' if c.fetch('phase')=='continued'&&(!body.empty?||c.fetch('historyBefore')!=c.fetch('acknowledgedHistory'))
end
n.fetch('comparisons').each{|c|abort 'parent body changed' unless c.fetch('bodyEqual')&&c.fetch('candidateSha256')==c.fetch('referenceSha256')}
n.fetch('counters').each do |c|
  c.fetch('routing').each{|x|abort 'posting row budget escaped' unless x.fetch('postingRows')<=x.fetch('postingAllowance')}
end
d=r.fetch('directComparison');abort 'same-candidate provider result changed' unless d.fetch('completeResponseEqual')&&d.fetch('owners')==4101&&JSON.parse(File.read(d.fetch('reference').fetch('path')))==JSON.parse(File.read(d.fetch('candidate').fetch('path')))
cleanup=r.fetch('cleanup')
abort 'archive created' unless cleanup.fetch('executables').fetch('archivesCreated')==0&&cleanup.fetch('final').fetch('archivesCreated')==0
(cleanup.fetch('executables').fetch('removed')+cleanup.fetch('final').fetch('removed')).each{|file|abort "retired path remains #{file['path']}" if File.exist?(file.fetch('path'))||File.symlink?(file.fetch('path'))}
puts({evidenceBindings:bindings.size,mutationMs:delta.fetch('elapsedMs'),projectionRows:delta.fetch('projectionRows'),metadataProbes:delta.fetch('retainedMetadataProbes'),nativeSemanticCompleted:6,adopted:false,recordSha256:Digest::SHA256.file(path).hexdigest}.to_json)
