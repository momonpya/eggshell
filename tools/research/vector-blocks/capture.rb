require 'json'
require 'digest'
require 'shellwords'
root=File.expand_path(__dir__)
parent=File.join(File.dirname(root),'lexical-advice-20261025')
def json(path); JSON.parse(File.read(path)); end
def file(path); {path:path,bytes:File.size(path),sha256:Digest::SHA256.file(path).hexdigest}; end
guards=Dir.glob(root+'/*.guard.json').sort.map{|p|[p,json(p)]}
abort 'live guard' unless guards.all?{|_,g|g.fetch('state')=='finished' && g.fetch('ownedPids').empty?}
%w[build-cache-bound helper-linked fixture prepare-50000 read-helper-build read-0 read-1 read-2].each do |name|
  g=json(root+'/'+name+'.guard.json');abort "failed final #{name}" unless g.fetch('exitCode')==0 && !g.fetch('guardTriggered')
end
sources=%w[Eggshell/VectorBlocks.lean tools/research/VectorBlocksAudit.lean tools/research/VectorBlocksReadAudit.lean].map{|p|file(root+'/checkout/'+p).merge(relative:p)}
originals=json(parent+'/review.json').fetch('originalFiles').map do |f|
  actual=file(f.fetch('path')); abort 'original source changed' unless actual.fetch(:sha256)==f.fetch('sha256') && actual.fetch(:bytes)==f.fetch('bytes'); actual
end
numerical=file(root+'/checkout/runtime/embedding.py')
abort 'encoder/numerical boundary changed' unless numerical.fetch(:sha256)==Digest::SHA256.file(parent+'/checkout/runtime/embedding.py').hexdigest
fixture=json(root+'/fixture/result.json')
prepared=json(root+'/blocked-50000/result.json')
abort 'incomplete original audit' unless prepared.fetch('allOriginalBitsAndCoverageEqual') && prepared.fetch('checkedRows')==99969 && prepared.fetch('repeated').fetch('writtenBytes')==0
comparisons=(0...3).map{|r|json(root+"/read-#{r}/result.json")}
comparisons.each do |c|
  abort 'unequal/changed comparison' unless c.fetch('originalRowsAndCoverageExactlyEqual') && c.fetch('keys')==3125 && c.fetch('residentBlockReadsAndHashes')==0 && c.fetch('residentCacheHits')==3125
  abort 'different publication' unless c.fetch('originalMatrix')==prepared.fetch('originalMatrix') && c.fetch('originalRoute')==prepared.fetch('originalRoute') && c.fetch('blocked')==prepared.fetch('blocked')
end
abort 'changed request' unless comparisons.map{|c|c.fetch('requestSha256')}.uniq.size==1
linked=Dir.glob(root+'/*.rsp').flat_map{|p|Shellwords.split(File.read(p))}.select{|p|File.file?(p)}.uniq.sort.map{|p|file(p)}
evidence=Dir.glob(root+'/*.{json,log,rb,md,txt}').reject{|p|%w[review.json review.check.json].include?(File.basename(p))}
%w[fixture blocked-50000 read-0 read-1 read-2].each{|d|evidence+=Dir.glob(root+'/'+d+'/**/*').select{|p|File.file?(p)}}
numerical_root='/Users/ovm/.codex/experiments/eggshell/lexical-advice-20261025/scale-data-50000/read-cache/eb5d3f9baf77963bfcfdc94afde22939b244236c8a6ef70bf4c12133b3058971/semantic'
source_numerical=%w[projections routing].flat_map{|d|Dir.glob(numerical_root+'/'+d+'/**/*')}.select{|p|File.file?(p)}.sort.map{|p|file(p)}
record={candidate:'router-aligned-original-vector-blocks',baseCommit:'5227a18bde0bb6aab3439007e1b84e03ef62a69c',parentCheckout:parent+'/checkout',adopted:false,productRuntimeChanged:false,
  answeringModelCalls:0,seedCalls:0,sourceEmbeddingCalls:0,newPythonImplementation:false,numericalBoundaryChanged:false,
  inclusiveTokenComparison:false,qualityQualification:false,requiredHistoryRecallQualification:false,nativeHookQualification:false,millionWindowQualification:false,
  sources:sources,sourceNumericalFiles:source_numerical,numericalBoundary:numerical,sourceFilesUnchanged:true,originalFiles:originals,plan:json(root+'/plan.json'),fixture:fixture,prepared:prepared,comparisons:comparisons,
  proofs:['Eggshell.VectorBlocks.block_roundtrip','Eggshell.VectorBlocks.committed_block_preserved_by_append','Eggshell.VectorBlocks.Verified.slice_size','Eggshell.VectorBlocks.State.actual_bytes_bounded'],
  generated:Dir.glob(root+'/*.{c,o,rsp}').sort.map{|p|file(p)},linkedInputs:linked,
  evidence:evidence.uniq.sort.map{|p|file(p)},guards:guards.map{|p,g|file(p).merge(exitCode:g.fetch('exitCode'),peakRssKiB:g.fetch('sampledPeakRssKiB'))},
  maximumAggregateRssKiB:guards.map{|_,g|g.fetch('sampledPeakRssKiB')}.max,limitRssKiB:3670016,userCeilingRssKiB:4194304,
  failures:['initial implementation used unavailable Option.toExcept; replaced with explicit UTF-8 validation',
    'first helper link wrapper omitted require json; no stale executable ran'],
  retirements:File.exist?(root+'/retirements.json') ? json(root+'/retirements.json') : [],archivesCreated:false,
  limitations:['reader only; no numerical transport/scorer or native warm/provider connection',
    'row and block directories still use point lookups',
    'whole dense region rebuilt on basis change; incremental segments and compaction unfinished',
    'current axis router unchanged; IVF, safe bounds, full-score recall and hybrid-rank scope unfinished',
    'reference preparations use O(N) key/metadata memory; no million-plus, federation or shared-user qualification',
    'component timings are not token, answer quality, useful-history recall or native latency measurements']}
File.write(root+'/review.json',JSON.pretty_generate(record)+"\n")
puts JSON.generate({sources:sources.size,checkedRows:prepared.fetch('checkedRows'),comparisons:comparisons.size,peakRssKiB:record.fetch(:maximumAggregateRssKiB)})
