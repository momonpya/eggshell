require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'zlib'
base='/Users/ovm/.codex/experiments/eggshell'
out=base+'/canonical-selection-audit-20261023'
provider=out+'/eggshell'
archive=JSON.parse(File.read(out+'/archived-reference-runtime.json')).first
unless File.exist?(provider)
Zlib::GzipReader.open(archive.fetch('archive')) do |input|
 File.open(provider,'wb'){|output|IO.copy_stream(input,output)}
end
raise 'provider payload mismatch' unless Digest::SHA256.file(provider).hexdigest==archive.fetch('sha256')
end
File.chmod(0755,provider)
spec=JSON.parse(File.read(base+'/canonical-indexed-20261023/warm-source-spec.json'))
results=[]
[3,4].each do |stage|
 row=spec.find{|x|x['stage']==stage}
 dir=out+"/probe-stage#{stage}"
 recovered=File.exist?(dir+'/result.json')
 raise 'partial diagnostic output must be inspected' if File.exist?(dir)&&!recovered
 FileUtils.mkdir_p(dir)
 source=dir+'/work.egg'
 raise 'source clone failed' unless recovered||system('/bin/cp','-cR',row.fetch('source'),source)
 before=row.fetch('files')
 before.each{|name,hash|raise 'original source mismatch' unless Digest::SHA256.file(source+'/'+name).hexdigest==hash} unless recovered
 File.write(dir+'/prompt.txt',row.fetch('prompt'))
 env={'EGGSHELL_DATA_ROOT'=>dir+'/data','HF_HUB_OFFLINE'=>'1','OMP_NUM_THREADS'=>'1','TOKENIZERS_PARALLELISM'=>'false','EGGSHELL_HANDOFF_TRACE'=>dir+'/trace.txt'}
 start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
 unless recovered
 a,b,s=Open3.capture3(env,out+'/CanonicalSelectionProbe',source,dir+'/prompt.txt',row.fetch('workspace'),provider,dir+'/result.json',chdir:row.fetch('workspace'))
 File.write(dir+'/stdout',a);File.write(dir+'/stderr',b)
 raise 'probe failed' unless s.success?
 end
 b=File.read(dir+'/stderr')
 snapshots=b.lines.map{|line|line.start_with?('EGGSHELL_FIT_AUDIT ') ? JSON.parse(line.delete_prefix('EGGSHELL_FIT_AUDIT ')) : nil}.compact
 raise 'expected one actual selection snapshot' unless snapshots.size==1
 File.write(dir+'/selection.json',JSON.generate(snapshots.first))
 handoff=JSON.parse(File.read(dir+'/result.json'))
 body=handoff.fetch('text')
 File.write(dir+'/body.txt',body)
 reference=base+"/canonical-deferred-20261023/six-ready-cache/stage#{stage}/native-0/body.txt"
 same=body==File.read(reference)
 after=before.map{|name,hash|[name,Digest::SHA256.file(source+'/'+name).hexdigest==hash]}
 # Source head can advance for derived preparation; source fact auditing is
 # performed by the independent native publication checker, not this flag.
 result={stage:stage,exitCode:recovered ? 0 : s.exitstatus,recoveredCompletedChildAfterWrapperFailure:recovered,elapsedMs:recovered ? nil : ((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round,
  exactFrozenSourceBefore:true,rawSourceFilesEqualAfter:after,byteEqualActualHook:same,
  bodySha256:Digest::SHA256.hexdigest(body),referenceSha256:Digest::SHA256.file(reference).hexdigest,
  snapshots:snapshots.size}
 File.write(dir+'/record.json',JSON.pretty_generate(result)+"\n")
 results<<result
 puts result.to_json
end
File.write(out+'/probe-results.json',JSON.pretty_generate(results)+"\n")
