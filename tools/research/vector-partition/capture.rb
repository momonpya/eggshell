require 'json'
require 'digest'
require 'shellwords'
root=File.expand_path(__dir__)
parent='/Users/ovm/.codex/experiments/eggshell/block-score-20261025'
repo='/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell'
def json(p); JSON.parse(File.read(p)); end
def file_binding(p); {path:p,bytes:File.size(p),sha256:Digest::SHA256.file(p).hexdigest}; end
guards=Dir.glob(root+'/*.guard.json').sort.map{|p|[p,json(p)]}
abort 'live owned work remains' unless guards.all?{|_,g|g.fetch('state')=='finished' && g.fetch('ownedPids').empty?}
%w[build-final trial].each{|n|g=json(root+'/'+n+'.guard.json');abort "failed final #{n}" unless g.fetch('exitCode')==0 && !g.fetch('guardTriggered')}
r=json(root+'/trial/result.json')
abort 'wrong fixed trial' unless r.fetch('queries').size==11 && r.fetch('trainingSamples')==16384 && r.fetch('cells')==512 && r.fetch('cellSizes').sum==50000
abort 'unexpected adoption, model, or exact-stop claim' unless r.fetch('adopted')==false && r.fetch('answeringModelCalls')==0 && r.fetch('sourceEmbeddingCalls')==0 && r.fetch('safeFloatPruningClaimed')==false
abort 'scalar/full-provider reference not checked' unless r.fetch('queries').first.fetch('originalScalarBitsChecked')==3125 && r.fetch('queries').first.fetch('storedFullProviderOwnerRankingChecked')
summary=r.fetch('queries').map do |q|
  wanted=q.fetch('selection').fetch('keys')
  abort 'invalid learned nominations' unless wanted.size==3125 && wanted.uniq.size==wanted.size
  methods=q.fetch('methods').map do |m|
    m.fetch('windowRecall').each do |rec|
      abort 'invalid top-k evidence' unless rec.fetch('expected').size==rec.fetch('k') && rec.fetch('retained').size==rec.fetch('found') && rec.fetch('retained').uniq.size==rec.fetch('found') && (rec.fetch('retained')-rec.fetch('expected')).empty?
      if m.fetch('method')=='learned-eligible'
        abort 'retained windows not actually nominated' unless (rec.fetch('expected')&wanted)==rec.fetch('retained')
      end
    end
    {method:m.fetch('method'),nominations:m.fetch('nominations'),routingMs:m.fetch('routingMs'),windowRecall:m.fetch('windowRecall').map{|v|{k:v.fetch('k'),found:v.fetch('found')}},ownerTop8Found:(m.fetch('topOwners')&q.fetch('fullOwnerTop8')).size,ownerTop8:m.fetch('topOwners'),selfPresent:m.fetch('selfPresent')}
  end
  {query:q.fetch('query'),fullReferenceMs:q.fetch('fullReferenceMs'),originalScalarBitsChecked:q.fetch('originalScalarBitsChecked'),storedFullProviderOwnerRankingChecked:q.fetch('storedFullProviderOwnerRankingChecked'),fullOwnerTop8:q.fetch('fullOwnerTop8'),methods:methods,visitedCells:q.fetch('selection').fetch('visitedCells'),partialCell:q.fetch('selection').fetch('partialCell'),unvisitedEligibleRows:50000-wanted.size}
end
originals=json(parent+'/relocated-fixture-check.json').fetch('files').map do |f|
  actual=file_binding(f.fetch('path'));abort 'original DB/lexical file changed' unless actual.fetch(:bytes)==f.fetch('bytes') && actual.fetch(:sha256)==f.fetch('sha256');actual
end
semantic=parent+'/scale-data-50000/read-cache/'+r.fetch('basis').fetch('source').fetch('identity')+'/semantic/'
numerical=json(repo+'/docs/candidates/vector-blocks-review.json').fetch('sourceNumericalFiles').map do |f|
  path=semantic+f.fetch('path').split('/semantic/',2).fetch(1)
  actual=file_binding(path);abort 'original matrix/axis-router file changed' unless actual.fetch(:bytes)==f.fetch('bytes') && actual.fetch(:sha256)==f.fetch('sha256');actual
end
scores=Dir.glob(root+'/trial/*.scores').sort.map{|p|abort('wrong complete-score size') unless File.size(p)==50000*8;file_binding(p)}
abort 'full scores missing' unless scores.size==11
sources=%w[VectorPartition.lean PartitionAudit.lean].map{|p|file_binding(root+'/checkout/'+p).merge(relative:p)}
evidence=Dir.glob(root+'/*.{rb,json,log,txt,rsp}').reject{|p|%w[review.json review.check.json].include?(File.basename(p))} + Dir.glob(root+'/trial/**/*').select{|p|File.file?(p)}
record={candidate:'eligible-full-dimensional-balanced-partition',parentCommit:'33fd925',adopted:false,productRuntimeChanged:false,answeringModelCalls:0,newSeedCalls:0,sourceEmbeddingCalls:0,newPythonImplementation:false,sourceEncoderChanged:false,inclusiveTokenComparison:false,qualityQualification:false,requiredHistoryRecallQualification:false,nativeHookQualification:false,millionWindowQualification:false,safeFloatPruningClaimed:false,
  sources:sources,plan:json(root+'/plan.json'),basis:r.fetch('basis'),fixture:r.fetch('fixture'),preparation:r.reject{|k,v|%w[queries basis fixture].include?(k)},queries:summary,
  sourceProbeScope:'8 stored-vector self queries outside the plane-training sample; they remain ordinary indexed points and contribute to full-cell centroids. This is not an independent held-out repository or semantic task set.',
  controls:'same source, cached query vectors, scores, 3125 nomination cap; eligible-axis control is an in-memory rebuild, while current and learned controls read published indexes. Their routing times are not an equivalent I/O speed comparison. Eligible-axis preparation/query zero-ms fields are invalid timing evidence: generated C evaluates these pure functions after the recorded end-clock; exclude them from every latency claim.',
  excludedTimings:['preparation.axisTrainingMs','queries.methods[axis-eligible].routingMs'],
  numericalReference:'all 50000 eligible rows streamed through unchanged NumPy binary64-to-float32 per-row dot; natural-1 additionally matches every stored 3125 scalar score bit and frozen full-provider owner top 8',
  proofs:['Eggshell.VectorPartition.training_preserves_samples','Eggshell.VectorPartition.node_roundtrip'],originalFiles:originals,originalNumericalFiles:numerical,completeScores:scores,
  generated:Dir.glob(root+'/*.{c,o,rsp}').sort.map{|p|file_binding(p)},helper:file_binding(root+'/PartitionAudit'),linkedInputs:Shellwords.split(File.read(root+'/helper.rsp')).select{|p|File.file?(p)}.uniq.map{|p|file_binding(p)},
  evidence:evidence.uniq.sort.map{|p|file_binding(p)},guards:guards.map{|p,g|file_binding(p).merge(exitCode:g.fetch('exitCode'),guardTriggered:g.fetch('guardTriggered'),peakRssKiB:g.fetch('sampledPeakRssKiB'))},maximumAggregateRssKiB:guards.map{|_,g|g.fetch('sampledPeakRssKiB')}.max,limitRssKiB:3670016,userCeilingRssKiB:4194304,
  failures:['initial module search rooted an incomplete local Eggshell namespace; isolated modules now use top-level research names and import the intact current parent library without copying it',
    'reserved Lean identifier from, proof simplification, self-source include path, and missing Inhabited instance were fixed before execution',
    'audit frame used boolean equality instead of propositional equality; process record layout and owner IDs were corrected before execution',
    'one linked helper was never run and was deleted before correcting audit tie/query-key policy to the original provider',
    'eligible-axis pure preparation/query timings were found outside their intended intervals in generated C; values are retained but excluded from latency claims'],
  archivesCreated:false,limitations:['synthetic clock-heavy source, not LLVM tasks or an independent generalization corpus','only recommendation-window and numerical owner recall; no hybrid delivery/answer/token claim','fixed 512-cell prototype; scaling cell hierarchy, external-memory metadata, publication deltas and compaction remain','no certified float32 dot bound, exact top-k stopping or useful-history completeness','current learned index is not wired to Warm/keyed provider/native hooks/federation; 1M+, shared concurrency, p99 and privacy qualification remain']}
File.write(root+'/review.json',JSON.pretty_generate(record)+"\n")
puts JSON.generate({queries:summary.size,cells:r.fetch('cells'),originalFiles:originals.size,numericalFiles:numerical.size,peakRssKiB:record.fetch(:maximumAggregateRssKiB),naturalLearnedTop8:summary.first(3).map{|q|q[:methods].find{|m|m[:method]=='learned-eligible'}[:ownerTop8Found]},adopted:false})
