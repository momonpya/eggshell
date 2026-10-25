require 'json'
require 'digest'
require 'shellwords'

root=File.expand_path(__dir__)
parent='/Users/ovm/.codex/experiments/eggshell/partition-native-20261025'
def json(p);JSON.parse(File.read(p));end
def bind(p);{path:p,bytes:File.size(p),sha256:Digest::SHA256.file(p).hexdigest};end
def unchanged!(f)
  a=bind(f.fetch('path'))
  abort "frozen input changed: #{f.fetch('path')}" unless a[:bytes]==f.fetch('bytes') && a[:sha256]==f.fetch('sha256')
  a
end
plan=json(root+'/plan.json')
guards=Dir.glob(root+'/*.guard.json').sort.map{|p|[p,json(p)]}
abort 'owned work remains live' unless guards.all?{|_,g|g.fetch('state')=='finished' && g.fetch('ownedPids').empty?}
%w[build-buffer build-audit fixture payload warm-first scale warm-repeat native direct].each do |name|
  g=json(root+'/'+name+'.guard.json')
  abort "failed final guard: #{name}" unless g.fetch('exitCode')==0 && !g.fetch('guardTriggered')
end
inputs=%w[sourceFiles originalNumericalFiles originalBlockFiles].flat_map{|k|plan.fetch(k)}.map{|f|unchanged!(f)}
plan.fetch('sources').each{|f|unchanged!(f)}
unchanged!(plan.fetch('runtime'))
abort 'staged runtime differs' unless bind(root+'/prefix/libexec/eggshell')[:sha256]==plan.fetch('runtime').fetch('sha256')
fixture=json(root+'/fixture/result.json')
abort 'small lifecycle fixture failed' unless fixture.values_at('comparedRows','updatedRows','modelCalls')==[67,68,0] &&
  %w[coldDoesNotPrepare idempotent projectionOnlyPreserved modelCellsPreserved changedMatrixRejected oldPinnedPreserved corruptionRejected].all?{|k|fixture.fetch(k)} &&
  fixture.fetch('first').fetch('peakBufferedBytes')<=plan.fetch('bufferCapacityBytes') &&
  fixture.fetch('repeated').values_at('mode','writtenBytes')==['warm',0]
scale=json(root+'/scale/result.json')
abort 'complete original-column audit failed' unless scale.values_at('rows','bytes','allOriginalBitsAndCoverageEqual','modelCalls')==
  [99969,99969*3072,true,0]
warm=json(root+'/preparation/private-warm.stdout.json').fetch('databases').fetch(0)
repeat=json(root+'/preparation/repeat-warm.stdout.json').fetch('databases').fetch(0)
[warm,repeat].each do |w|
  abort 'source embeddings or old data were regenerated' unless w.fetch('requested')==0 &&
    w.fetch('after').values_at('missing','invalid')==[0,0] &&
    w.fetch('projections').values_at('produced','writtenBytes')==[0,0] &&
    %w[routing blocks partition].all?{|k|w.fetch(k).fetch('writtenBytes')==0}
end
abort 'clustered data not prepared exactly once' unless warm.fetch('clustered').fetch('mode')=='prepared' &&
  warm.fetch('clustered').fetch('peakBufferedBytes')<=plan.fetch('bufferCapacityBytes') &&
  repeat.fetch('clustered').values_at('mode','writtenBytes')==['warm',0]
native=json(root+'/native-50000/summary.json')
abort 'different native source/runtime' unless native.fetch('source')==scale.fetch('source') &&
  native.fetch('runtimeSha256')==plan.fetch('runtime').fetch('sha256') && native.fetch('answeringModelCalls')==0
cases=native.fetch('cases')
abort 'wrong native cohort' unless native.fetch('pairs')==3 && cases.map{|c|[c.fetch('pair'),c.fetch('phase')]}==
  (0...3).flat_map{|i|[[i,'first'],[i,'continued']]}
evidence=[]
cases=cases.map do |c|
  abort 'native reply, stratum or deadline failed' unless c.fetch('exitCode')==0 && c.fetch('replyComplete') &&
    c.fetch('validStratum') && c.fetch('totalMs')<plan.fetch('deadlineMs') &&
    c.fetch('question')==plan.fetch('queries').fetch(c.fetch('pair'))
  label="pair-#{c.fetch('pair')}-#{c.fetch('phase')}"
  body=File.binread(root+'/native-50000/'+label+'/body.txt')
  stdout=File.binread(root+'/native-50000/'+label+'/stdout.json')
  publication=c.fetch('publication')
  published=publication.fetch('published')
  abort 'actual stdout/body do not match publication' unless published.fetch('output')==stdout &&
    published.fetch('bytes')==stdout.bytesize && published.fetch('sha256')==Digest::SHA256.hexdigest(stdout) &&
    c.fetch('bodyBytes')==body.bytesize && c.fetch('bodySha256')==Digest::SHA256.hexdigest(body)
  if c.fetch('phase')=='first'
    ack=publication.fetch('ack').fetch('data')
    abort 'original evidence not acknowledged' unless c.fetch('historyBefore')==0 && c.fetch('originalBody') &&
      body.include?('ORIGINAL_CLOCK_BODY_') && ack.fetch('rpcCompleted') && ack.fetch('offerAccepted')
  else
    previous=native.fetch('cases').find{|x|x.fetch('pair')==c.fetch('pair') && x.fetch('phase')=='first'}
    abort 'confirmed history was redelivered or lost' unless body.empty? && publication.fetch('ack').nil? &&
      c.fetch('historyBefore')==previous.fetch('acknowledgedHistory') && c.fetch('historyBefore')>0 &&
      c.fetch('acknowledgedHistory')==c.fetch('historyBefore')
  end
  stages=publication.fetch('stages')
  stages.each do |s|
    path=publication.fetch('path')+'/'+s.fetch('name')
    abort 'receipt stage changed' unless File.size(path)==s.fetch('bytes').to_i &&
      Digest::SHA256.file(path).hexdigest==s.fetch('sha256')
    evidence<<path
  end
  records=stages.map{|s|s.fetch('record')}
  numerical=records.select{|s|s.fetch('stage').start_with?('numerical-')}.map{|s|s.fetch('data')}
  routes=records.select{|s|s.fetch('stage').start_with?('keyed-partition-')}.map{|s|s.fetch('data')}
  abort 'routing source or budget changed' unless routes.size==1 && routes.first.fetch('source')==native.fetch('source') &&
    routes.first.values_at('keys','keyAllowance','unseenVectorKeys','totalCells')==[4096,4096,45904,512] &&
    !routes.first.fetch('safeFloatPruning')
  c.reject{|k,_|%w[publication lastOfferedSearch].include?(k)}.merge(
    'semanticCompleted'=>c.fetch('search').fetch('trace').fetch('semantic')=='completed',
    'numerical'=>numerical,'route'=>routes.first,'publicationPath'=>publication.fetch('path'))
end
stops=(0...3).map do |i|
  path=root+"/native-50000/pair-#{i}-shutdown.json"
  stop=json(path)
  abort 'manager teardown failed' unless stop.values_at('acknowledged','daemonExitCode','endpointRemoved','phase')==[true,0,true,'stopped']
  bind(path)
end
before=json(parent+'/direct.stdout.json')
after=json(root+'/direct.stdout.json')
abort 'full keyed-provider result changed' unless before==after
bodyComparisons=[1,2].map do |i|
  old=parent+"/inline-hash/native-50000/pair-#{i}-first/body.txt"
  new=root+"/native-50000/pair-#{i}-first/body.txt"
  abort 'same-question semantic delivery changed' unless File.binread(old)==File.binread(new)
  {pair:i,reference:bind(old),candidate:bind(new),equal:true}
end
request=json(root+'/direct.request.json')
receipt='/Users/ovm/.codex/experiments/eggshell/block-score-20261025/scale-data-50000/receipts/'+request.fetch('receipt')
directPaths=Dir.glob(receipt+'/*.json').sort
directStats=directPaths.select{|p|File.basename(p).start_with?('numerical-')}.map{|p|json(p).fetch('data')}
abort 'direct numerical scoring did not finish' unless directStats.size==1 && directStats.first.fetch('status')=='completed'
evidence.concat(directPaths)
evidence+=Dir.glob(root+'/*.{rb,json,log,txt,rsp}').reject{|p|%w[review.json review.check.json].include?(File.basename(p))}
evidence+=Dir.glob(root+'/native-50000/**/*').select{|p|File.file?(p)}
evidence+=Dir.glob(root+'/preparation/*').select{|p|File.file?(p)}
evidence+=[root+'/fixture/result.json',root+'/scale/result.json']
linked=Shellwords.split(File.read(root+'/runtime.rsp')).select{|p|File.file?(p)}.uniq.map{|p|bind(p)}
record={candidate:'cell-aligned-original-vector-blocks',parentCommit:'bdac92c',adopted:false,productRuntimeChanged:false,
  answeringModelCalls:0,newSeedCalls:0,sourceEmbeddingCalls:0,newPythonImplementation:false,
  inclusiveTokenComparison:false,qualityQualification:false,requiredHistoryRecallQualification:false,millionWindowQualification:false,
  safeFloatPruningClaimed:false,nativeSemanticQualification:cases.all?{|c|c.fetch('semanticCompleted')},
  plan:plan,fixture:fixture,scale:scale,warm:warm,repeatWarm:repeat,
  preparationReuse:json(root+'/native-50000/preparation-reuse.json'),
  native:{pairs:3,cases:cases,shutdowns:stops,semanticCompleted:cases.count{|c|c.fetch('semanticCompleted')}},
  directComparison:{allRankedWindowsRelatedAndCoverageEqual:true,owners:after.fetch('ranked').length,
    reference:bind(parent+'/direct.stdout.json'),candidate:bind(root+'/direct.stdout.json'),numerical:directStats},
  bodyComparisons:bodyComparisons,sources:plan.fetch('sources').map{|f|bind(f.fetch('path')).merge(relative:f.fetch('relative'))},
  originalFiles:inputs,runtime:bind(root+'/eggshell'),payload:bind(root+'/prefix/libexec/eggshell'),
  generated:Dir.glob(root+'/*.{c,o,rsp}').sort.map{|p|bind(p)},linkedInputs:linked,
  evidence:evidence.uniq.sort.map{|p|bind(p)},guards:guards.map{|p,g|bind(p).merge(exitCode:g.fetch('exitCode'),guardTriggered:g.fetch('guardTriggered'),peakRssKiB:g.fetch('sampledPeakRssKiB'))},
  maximumAggregateRssKiB:guards.map{|_,g|g.fetch('sampledPeakRssKiB')}.max,limitRssKiB:3670016,userCeilingRssKiB:4194304,
  archivesCreated:0,proofs:['Eggshell.ClusterBlocks.Buffer.original_byte_count','Eggshell.ClusterBlocks.Buffer.bytes_bounded',
    'Eggshell.VectorBlocks.Verified.slice_size','Eggshell.VectorBlocks.committed_block_preserved_by_append'],
  authority:'Only physical source-vector layout/lookup changes; original e-class recognition, Exact, Union origins, synapses, freshness and ranking policy stay independent of recommendation.',
  scope:'fixed synthetic 50000-window source; all 99969 pooled discovery/focus projections compared byte-for-byte. Three fixed prompt pairs, not LLVM topics 1/2/3 or p99.',
  failures:['Initial Buffer bound and record layout did not compile; the next compile required a checked dependent buffer lookup. Both failed builds are retained.',
    'The corruption audit was strengthened to require the actual vector block checksum-mismatch error before execution.'],
  limitations:['Source-order metadata preparation and original axis/block input are still required for full maintenance; this is not the final incremental million-window layout.',
    'Per-preparation cell buffer budget is 64 MiB; shared parallel preparation needs its own scheduling/resource qualification.',
    'Independent complete-column audit holds at most 512 MiB of expected values only inside that audit, not production.',
    'OS cache is not flushed; no controlled latency improvement percentage or p99 claim.',
    'Approximate router recall is unchanged, including its earlier missed self-query neighbors.',
    'Live multiple-DB/shared concurrency, MCP privacy/storage growth, required-code holdout and matched token/quality adoption experiments remain.']}
abort 'aggregate memory ceiling exceeded' unless record[:maximumAggregateRssKiB]<=3670016
File.write(root+'/review.json',JSON.pretty_generate(record)+"\n")
puts({rows:scale.fetch('rows'),nativeSemanticCompleted:record[:native][:semanticCompleted],
  firstMs:cases.select{|c|c['phase']=='first'}.map{|c|c['totalMs']},
  continuedMs:cases.select{|c|c['phase']=='continued'}.map{|c|c['totalMs']},
  maximumAggregateRssKiB:record[:maximumAggregateRssKiB],adopted:false}.to_json)
