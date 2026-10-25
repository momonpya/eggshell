require 'json'
require 'digest'
require 'shellwords'
require 'fileutils'
root=File.expand_path(__dir__)
parent=File.join(File.dirname(root),'keyed-runtime-20261025')
def json(path); JSON.parse(File.read(path)); end
def file(path)
  {path:path,bytes:File.size(path),sha256:Digest::SHA256.file(path).hexdigest}
end
source_names=%w[Eggshell/LexicalAdvice.lean Eggshell/KeyedSearchProvider.lean Eggshell/ContractAudit.lean tools/research/LexicalAdviceAudit.lean]
sources=source_names.map{|p|file(File.join(root,'checkout',p)).merge(relative:p)}
export=File.join(root,'export')
FileUtils.mkdir_p(File.join(export,'Eggshell'))
FileUtils.mkdir_p(File.join(export,'tools/research'))
%w[Eggshell/LexicalAdvice.lean tools/research/LexicalAdviceAudit.lean].each{|p|FileUtils.cp(File.join(root,'checkout',p),File.join(export,p))}
File.open(File.join(export,'integration.patch'),'w') do |output|
  %w[Eggshell/KeyedSearchProvider.lean Eggshell/ContractAudit.lean].each do |p|
    IO.popen(['/usr/bin/diff','-U0','--label',"a/#{p}",'--label',"b/#{p}",File.join(parent,'checkout',p),File.join(root,'checkout',p)]){|process|output.write(process.read)}
    abort "diff failed #{p}" unless [0,1].include?($?.exitstatus)
  end
end
guards=Dir.glob(File.join(root,'*.guard.json')).sort.map{|p|[p,json(p)]}
abort 'live guard' unless guards.all?{|_,g|g.fetch('state')=='finished'&&g.fetch('ownedPids').empty?}
%w[build-closed-result audit-final-build fixture keyed-build keyed-fixture benchmark-0 benchmark-1 benchmark-2 native-50000].each do |name|
  g=json(File.join(root,name+'.guard.json'));abort "failed final #{name}" unless g.fetch('exitCode')==0&&!g.fetch('guardTriggered')
end
before=json(File.join(parent,'review.json')).fetch('originalFiles')
originals=before.map{|p|file(p.fetch('path'))}
abort 'original files changed' unless before.zip(originals).all?{|a,b|a.fetch('sha256')==b.fetch(:sha256)&&a.fetch('bytes')==b.fetch(:bytes)}
native=json(File.join(root,'native-50000/summary.json'))
same_bodies=%w[first continued].all?{|phase|File.binread(File.join(root,"native-50000/pair-0-#{phase}/body.txt"))==File.binread(File.join(parent,"native-linear-50000/pair-0-#{phase}/body.txt"))}
abort 'native body changed' unless same_bodies
embedding=file(File.join(root,'checkout/runtime/embedding.py'))
abort 'numerical boundary changed' unless embedding.fetch(:sha256)==Digest::SHA256.file(File.join(parent,'checkout/runtime/embedding.py')).hexdigest
evidence=Dir.glob(File.join(root,'*.{json,log,rb,md}')).reject{|p|%w[review.json review.check.json].include?(File.basename(p))}
%w[benchmark-0 benchmark-1 benchmark-2 native-50000 fixture keyed-fixture].each{|d|evidence+=Dir.glob(File.join(root,d,'**/*')).select{|p|File.file?(p)}}
native.fetch('cases').each do |c|
  evidence+=Dir.glob(File.join(root,'scale-data-50000/receipts',c.fetch('publication').fetch('id'),'*.json'))
end
record={candidate:'consumed-lexical-original-validation',baseCommit:'0174ef8e42e5e60a4739cfc00b3b798d8ea35ec5',
  parentCheckout:File.join(parent,'checkout'),adopted:false,productRuntimeChanged:false,phases0Through6:'active',
  answeringModelCalls:0,seedCalls:0,sourceEmbeddingCalls:0,newPythonImplementation:false,
  inclusiveTokenComparison:false,qualityQualification:false,requiredHistoryRecallQualification:false,millionWindowQualification:false,
  sources:sources,integrationPatch:file(File.join(export,'integration.patch')),runtime:file(File.join(root,'eggshell')),
  pluginLauncher:file(File.join(root,'plugin/bin/eggshelld')),numericalBoundary:embedding,
  policy:'source-bound index hints nominate; bounded consumed owners still pass original checks; complete e-class authority independent',
  rankProof:'Eggshell.LexicalAdvice.rank_prepared_exact',fixture:json(File.join(root,'fixture/result.json')),
  keyedFixture:json(File.join(root,'keyed-fixture/result.json')),
  benchmarkPlan:json(File.join(root,'plan.json')),benchmarks:(0...3).map{|r|json(File.join(root,"benchmark-#{r}/summary.json"))},
  nativeBodyBytesEqual:same_bodies,nativeCases:native.fetch('cases').map{|c|c.select{|k,_|%w[phase totalMs bodySha256 bodyBytes acknowledgedHistory search].include?(k)}},
  sourceFilesUnchanged:true,originalFiles:originals,
  generated:Dir.glob(File.join(root,'*.{c,o,rsp}')).sort.map{|p|file(p)},
  linkedInputs:Shellwords.split(File.read(File.join(root,'runtime.rsp'))).select{|p|File.file?(p)}.uniq.sort.map{|p|file(p)},
  evidence:evidence.uniq.sort.map{|p|file(p)},guards:guards.map{|p,g|file(p).merge(exitCode:g.fetch('exitCode'),peakRssKiB:g.fetch('sampledPeakRssKiB'))},
  maximumAggregateRssKiB:guards.map{|_,g|g.fetch('sampledPeakRssKiB')}.max,limitRssKiB:3670016,userCeilingRssKiB:4194304,
  failures:['redundant second original-witness wrapper failed dependent field typing and was removed in favor of the existing witness',
    'Lean do elaborator rejected a dependent result through the provider loop; retain the closed source inside the result instead',
    'fixture used reserved axiom identifier; renamed without changing tested behavior'],
  retirements:File.exist?(File.join(root,'retirements.json')) ? json(File.join(root,'retirements.json')) : [],archivesCreated:false,
  limitations:['still enumerates and sorts full lexical query postings','cold lexical fallback and native federation unchanged',
    'no new token, quality or required-original recall result','native times are one pair, not p99 or replicated speed comparison',
    'numerical rows remain scalar; next implement router-aligned verified blocks before changing partition policy']}
File.write(File.join(root,'review.json'),JSON.pretty_generate(record)+"\n")
puts JSON.generate({sources:sources.length,artifacts:record.fetch(:evidence).length,peakRssKiB:record.fetch(:maximumAggregateRssKiB),nativeBodiesEqual:same_bodies})
