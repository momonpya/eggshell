require 'json'
require 'digest'

path=File.expand_path('../../../docs/candidates/projection-cursor-review.json',__dir__)
r=JSON.parse(File.read(path))
%w[adopted productRuntimeChanged inclusiveTokenComparison qualityQualification requiredHistoryRecallQualification
   millionWindowQualification heldoutHundredInquiryQualification sharedConcurrentQualification
   prePostScaleQualification sourceSegmentCacheRetired safeFloatPruningClaimed newPythonImplementation].each do |key|
  abort "unqualified claim: #{key}" unless r.fetch(key)==false
end
%w[answeringModelCalls newSeedCalls sourceEmbeddingCalls].each{|key|abort "unexpected model cost: #{key}" unless r.fetch(key)==0}
bindings=%w[sources frozenInputs linkedInputs evidence guards].flat_map{|key|r.fetch(key)}+
  [r.fetch('runtime'),r.fetch('payload'),r.fetch('native').fetch('summary'),
   r.fetch('directComparison').fetch('reference'),r.fetch('directComparison').fetch('candidate')]
bindings=bindings.uniq{|file|file.fetch('path')}
bindings.each do |file|
  p=file.fetch('path')
  abort "missing or changed evidence: #{p}" unless File.file?(p)&&File.size(p)==file.fetch('bytes')&&
    Digest::SHA256.file(p).hexdigest==file.fetch('sha256')
end
r.fetch('sources').each do |file|
  p=File.join(__dir__,file.fetch('relative'))
  abort "checkpoint differs: #{p}" unless Digest::SHA256.file(p).hexdigest==file.fetch('sha256')
end
abort 'staged runtime differs' unless r.fetch('runtime').fetch('sha256')==r.fetch('payload').fetch('sha256')
guards=r.fetch('guards').map{|file|[File.basename(file.fetch('path')),JSON.parse(File.read(file.fetch('path')))]}.to_h
abort 'owned processes remain' unless guards.values.all?{|g|g.fetch('state')=='finished'&&g.fetch('ownedPids').empty?}
r.fetch('finalGuards').each do |name|
  g=guards.fetch(name+'.guard.json')
  abort "failed final guard: #{name}" unless g.fetch('exitCode')==0&&!g.fetch('guardTriggered')
end
abort 'aggregate RSS claim differs' unless r.fetch('maximumAggregateRssKiB')==guards.values.map{|g|g.fetch('sampledPeakRssKiB')}.max&&
  r.fetch('maximumAggregateRssKiB')<=3670016
f=r.fetch('fixture')
%w[frameBytesEqual oldPinPreserved changedOwnerRejected corruptionRejected truncationRejected
   duplicateVectorDirectoriesAbsent coldDoesNotPrepare].each{|key|abort "fixture failed: #{key}" unless f.fetch(key)}
abort 'fixture dimensions differ' unless f.values_at('comparedRows','updatedRows','wideBytes','wideChunks','selectedRows','residentHits')==[66,67,32768,8,1,1]
abort 'tiny cache exceeded its allowance' unless f.fetch('tinyCacheBytes')<=32
s=r.fetch('scale')
abort 'complete original-row audit absent' unless s.values_at('rows','allOriginalBitsAndCoverageEqual','duplicateVectorDirectoriesAbsent')==[99969,true,true]
w=r.fetch('warm');repeat=r.fetch('repeatWarm')
abort 'initial source preparation failed' unless w.fetch('requested')==0&&w.fetch('after').values_at('missing','invalid')==[0,0]&&
  w.fetch('projections').values_at('rows','bytes','produced','writtenBytes')==[99969,307104768,0,0]
abort 'repeat warm enumerated unchanged inputs' unless repeat.values_at('scope','planReason','requested')==['publication-delta','source-unchanged',0]&&
  repeat.fetch('projections').values_at('requested','produced','writtenBytes')==[0,0,0]&&
  repeat.fetch('partition').values_at('mode','writtenBytes')==['warm',0]
root=File.dirname(r.fetch('runtime').fetch('path'))
modules=JSON.parse(File.read(root+'/runtime-modules.json'))
abort 'obsolete vector layout still linked' unless (modules&%w[Eggshell.VectorBlocks Eggshell.VectorRoute ClusterBlocks]).empty?
semantic=JSON.parse(File.read(root+'/plan.json')).fetch('semantic')
%w[routing blocks clustered].each{|name|abort "duplicate vector layout: #{name}" if File.exist?(semantic+'/'+name)}
bytes=r.fetch('vectorPageBytes')
abort 'vector page totals differ' unless bytes.fetch('candidate').values.sum==bytes.fetch('candidateTotal')&&
  bytes.fetch('baseline').values.sum==bytes.fetch('baselineTotal')&&bytes.fetch('candidateTotal')<bytes.fetch('baselineTotal')
n=r.fetch('native');actual=JSON.parse(File.read(n.fetch('summary').fetch('path')))
abort 'native cohort incomplete' unless n.fetch('pairs')==3&&n.fetch('semanticCompleted')==6&&actual.fetch('cases').size==6
actual.fetch('cases').each do |c|
  label="pair-#{c.fetch('pair')}-#{c.fetch('phase')}"
  out=File.binread(root+'/native-50000/'+label+'/stdout.json')
  body=File.binread(root+'/native-50000/'+label+'/body.txt')
  p=c.fetch('publication');published=p.fetch('published')
  abort "published/stdout mismatch: #{label}" unless published.fetch('output')==out&&published.fetch('bytes')==out.bytesize&&
    published.fetch('sha256')==Digest::SHA256.hexdigest(out)
  abort "body mismatch: #{label}" unless c.fetch('bodyBytes')==body.bytesize&&c.fetch('bodySha256')==Digest::SHA256.hexdigest(body)
  abort "native gate failed: #{label}" unless c.fetch('validStratum')&&c.fetch('replyComplete')&&c.fetch('exitCode')==0&&c.fetch('totalMs')<30000&&
    p.fetch('search').fetch('trace').values_at('semantic','warmRequests')==['completed',0]
  if c.fetch('phase')=='first'
    abort "missing original/ACK: #{label}" unless c.fetch('originalBody')&&body.bytesize>0&&p.fetch('ack')
  else
    abort "incorrect continued delivery: #{label}" unless body.empty?&&c.fetch('historyBefore')>0&&
      c.fetch('historyBefore')==c.fetch('acknowledgedHistory')
  end
end
n.fetch('comparisons').each do |c|
  abort 'native body changed' unless c.fetch('bodyEqual')&&c.fetch('candidateSha256')==c.fetch('referenceSha256')
  c.fetch('numerical').each do |counter|
    metric=counter.fetch('metrics')
    abort 'numerical model started' unless counter.fetch('status')=='completed'&&metric.fetch('encoder').values_at('sourceEncodeUs','queryEncodeUs','modelLoaded')==[0,0,false]
    abort 'retained vector payload exceeds allowance' unless metric.fetch('projectionRetainedBytes')<=r.fetch('rawCacheCapacity')
    abort 'continued row cache missed' if c.fetch('phase')=='continued'&&metric.fetch('projectionMisses')!=0
  end
end
d=r.fetch('directComparison')
abort 'complete same-candidate provider result changed' unless d.fetch('completeResponseEqual')&&d.fetch('referenceOwners')==4101&&
  JSON.parse(File.read(d.fetch('reference').fetch('path')))==JSON.parse(File.read(d.fetch('candidate').fetch('path')))
puts({evidenceBindings:bindings.size,originalRows:s.fetch('rows'),nativeCalls:6,semanticCompleted:6,
  repeatWarmMs:repeat.fetch('elapsedMs'),vectorPages:bytes.fetch('candidateTotal'),adopted:false,
  recordSha256:Digest::SHA256.file(path).hexdigest}.to_json)
