require 'json'
require 'digest'
require 'shellwords'
require 'fileutils'
root=File.expand_path(__dir__)
repo='/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell'
parent=repo+'/docs/candidates/source-stream-review.json'
old=JSON.parse(File.read(parent))
profile='/Users/ovm/.codex/experiments/eggshell/warm-producers-20261025'
dest=repo+'/tools/research/canonical-delta'
FileUtils.mkdir_p(dest)
bind=lambda{|p|{path:File.expand_path(p),bytes:File.size(p),sha256:Digest::SHA256.file(p).hexdigest}}
relative=%w[Eggshell/CanonicalSource.lean Eggshell/CanonicalSourceCache.lean Eggshell/Warm.lean
  Eggshell/ContractAudit.lean CanonicalDeltaAudit.lean Main.lean]
sources=relative.map do |p|
  from=root+'/checkout/'+p;to=dest+'/'+p;FileUtils.mkdir_p(File.dirname(to));FileUtils.cp(from,to)
  bind.call(from).merge(relative:p)
end
%w[build.rb setup.rb prepare-mutation.rb freeze.rb].each do |p|
  FileUtils.cp(root+'/'+p,dest+'/'+p);sources<<bind.call(root+'/'+p).merge(relative:p)
end
%w[WarmStagesAudit.lean build-profile.rb].each do |p|
  FileUtils.mkdir_p(dest+'/profiling');FileUtils.cp(profile+'/'+p,dest+'/profiling/'+p)
  sources<<bind.call(profile+'/'+p).merge(relative:'profiling/'+p)
end
runtimeSources=JSON.parse(File.read(root+'/runtime-modules.json')).map{|n|root+'/checkout/'+n.tr('.','/')+'.lean'}.select{|p|File.file?(p)}.map{|p|bind.call(p)}
runtimeSources<<bind.call('/Users/ovm/.codex/experiments/eggshell/partition-native-20261025/inline-hash/checkout/Eggshell/Blake3.lean')
linked=Shellwords.split(File.read(root+'/runtime.rsp')).select{|p|File.file?(p)}.map{|p|bind.call(p)}
guards=Dir[root+'/*.guard.json']+[profile+'/profile.guard.json',profile+'/build-profile.guard.json']
guardRows=guards.map{|p|JSON.parse(File.read(p))}
raise 'guard still owns processes' unless guardRows.all?{|x|x['state']=='finished'&&x['ownedPids'].empty?}
frozen=old.fetch('frozenInputs')
frozen.each{|x|raise "original changed #{x['path']}" unless bind.call(x['path']).transform_keys(&:to_s)==x}
mutationInputs=JSON.parse(File.read(root+'/mutation/inputs.json'))
mutationState=mutationInputs.fetch('files').map do |x|
  now=bind.call(x['path']).transform_keys(&:to_s);raise 'mutation source changed' unless x==now;now
end
mutationBasisFiles=(Dir[mutationInputs.fetch('sourceParent')+'/*']+
  Dir[mutationInputs.fetch('projectionBasis')+'/{projections,vectors}/**/*']).select{|p|File.file?(p)&&!File.symlink?(p)}.uniq.map{|p|bind.call(p)}
evidence=Dir[root+'/*.{json,stdout,stderr}',root+'/preparation/*',root+'/mutation/*',root+'/native-50000/**/*',root+'/fixture/**/*',profile+'/*.{json,stdout,stderr,lean,rb,rsp}']
evidence=evidence.select{|p|File.file?(p)&&!File.symlink?(p)}.uniq.map{|p|bind.call(p)}
first=JSON.parse(File.read(root+'/mutation/first.json')).fetch('databases').fetch(0)
repeat=JSON.parse(File.read(root+'/mutation/repeat.json')).fetch('databases').fetch(0)
profiling=JSON.parse(File.read(profile+'/profile-result.json'))
r={candidate:'canonical-delta',parentCommit:'3f4bd949349d4e6779b683a219e442ce1c3a355c',
  adopted:false,productRuntimeChanged:false,inclusiveTokenComparison:false,qualityQualification:false,
  millionWindowQualification:false,wholeMutationWarmIncrementalQualified:false,heldoutHundredInquiryQualification:false,
  sharedConcurrentQualification:false,prePostScaleQualification:false,mcpStoragePolicyQualified:false,
  physicalCompactionQualified:false,allCanonicalPayloadWorkDelta:false,
  answeringModelCalls:0,newSeedCalls:0,newPythonImplementation:false,successfulLocalSourceEmbeddingWindows:1,
  sources:sources,runtimeSources:runtimeSources,linkedInputs:linked,frozenInputs:frozen,modelFiles:old.fetch('modelFiles'),
  runtime:bind.call(root+'/eggshell'),payload:bind.call(root+'/prefix/libexec/eggshell'),parentRecord:bind.call(parent),
  guards:guards.map{|p|bind.call(p)},maximumAggregateRssKiB:guardRows.map{|x|x['sampledPeakRssKiB']}.max,
  finalGuards:%w[build-retry2 fixture payload base native mutation-first mutation-repeat],evidence:evidence,
  fixture:JSON.parse(File.read(root+'/fixture/result.json')),profiling:profiling,
  parentWholeWarm:old.fetch('mutationWarm'),basePreparation:JSON.parse(File.read(root+'/preparation/base.json')),
  basePreparationNote:'New canonical contract was built. The warm checkpoint was marked over the known-complete parent encoding/focus basis; those functions and encoder bytes were unchanged. This is not a cold whole-warm construction measurement.',
  mutationInputs:mutationInputs,mutationState:mutationState,mutationBasisFiles:mutationBasisFiles,mutationWarm:first,mutationRepeat:repeat,
  native:{summary:bind.call(root+'/native-50000/summary.json'),comparisons:JSON.parse(File.read(root+'/native-comparison.json'))},
  remaining:['lexical and synapse whole-source work','flat canonical payload load/filter/serialization and 32 MiB limit',
    'source segment JSON cache','actual 100-Inquiry all-owner recall and cell drift/retraining',
    'physical page compaction','million-window, shared concurrent and large Pre/Post qualification',
    'MCP privacy policy before every persistence path','matched total tokens and quality, all topics and both laps'],
  buildDiskNote:'The disk reserve for two build retries was 256/128 MiB during external storage pressure; memory stop remained 3.5 GiB. No disk guard fired. All runtime trials used a 512 MiB reserve. The disk recovered before runtime trials.',
  cleanupNotes:'Completed producer trial caches, an obsolete component executable and regenerable compiler C outputs were deleted without archives. Current source/projection/model/baseline inputs remained; F payload storage was APFS-cloned without changing bytes.'}
File.write(repo+'/docs/candidates/canonical-delta-review.json',JSON.pretty_generate(r)+"\n")
puts({sources:sources.size,runtimeSources:runtimeSources.size,linked:linked.size,evidence:evidence.size,guards:guards.size,
  canonicalMs:first['canonical']['elapsedMs'],wholeWarmMs:first['elapsedMs']}.to_json)
