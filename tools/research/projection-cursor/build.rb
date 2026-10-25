require 'json'
require 'shellwords'
require 'fileutils'
root=File.expand_path(__dir__)
base='/Users/ovm/.codex/experiments/eggshell/block-score-20261025'
partition='/Users/ovm/.codex/experiments/eggshell/partition-native-20261025'
cluster='/Users/ovm/.codex/experiments/eggshell/cluster-blocks-20261025'
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
Dir.chdir(root+'/checkout')
changed=%w[ProjectionCache Eggshell.Numerical Eggshell.SearchProvider ProjectionCursor DirectProjectionAudit Eggshell.VectorBlocks VectorPartition PartitionBuild ClusterBlocks Eggshell.BlockScore Eggshell.Warm Eggshell.KeyedSearchProvider Eggshell.ContractAudit tools.research.NativeHookAudit Main]
children={}
scan=nil
scan=lambda do |name|
  next if children.key?(name)
  path=name.tr('.','/')+'.lean'
  children[name]=File.file?(path) ? File.read(path).scan(/^(?:public\s+)?import\s+(?:all\s+)?([A-Za-z0-9_.]+)/).flatten : []
  children[name].each{|n|scan.call(n)}
end
scan.call('Main')
runtimeNames=children.keys.dup
scan.call('Eggshell.ContractAudit')
seen={};affected={};ordered=[]
visit=nil
visit=lambda do |name|
  return affected[name] if seen[name]
  seen[name]=true
  dependent=children.fetch(name,[]).map{|n|visit.call(n)}.any?
  affected[name]=changed.include?(name)||dependent
  ordered<<name if affected[name]
  affected[name]
end
%w[Main Eggshell.ContractAudit].each{|n|visit.call(n)}
File.write(root+'/modules.json',JSON.pretty_generate(ordered)+"\n")
File.write(root+'/runtime-modules.json',JSON.pretty_generate(runtimeNames)+"\n")
selected=ARGV.include?('--link-only') ? [] : ordered
if (i=ARGV.index('--from'));selected=selected.drop_while{|n|n!=ARGV[i+1]};end
tool='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/'
selected.each do |name|
  path=name.tr('.','/')
  source=path+'.lean'
  if File.symlink?(source)
    content=File.binread(source);File.unlink(source);File.binwrite(source,content)
  end
  stem='.lake/build/lib/lean/'+path
  FileUtils.mkdir_p(File.dirname(stem))
  Dir.glob(stem+'.*').each{|p|File.unlink(p) if File.symlink?(p)}
  puts({compiling:name}.to_json);STDOUT.flush
  output=root+'/'+name.tr('.','_')
  abort "Lean failed #{name}" unless system(tool+'lean','-j1','-M','1536','-DwarningAsError=true',
    '-c',output+'.c','-o',stem+'.olean',root+'/checkout/'+source)
  abort "C failed #{name}" unless system(tool+'leanc','-c','-O2','-o',output+'.o',output+'.c')
end
mapping=JSON.parse(File.read(base+'/link-modules.json'))
[base,partition,cluster].each do |parent|
  mapping[parent+'/Main.o']='Main'
  next unless File.file?(parent+'/modules.json')
  JSON.parse(File.read(parent+'/modules.json')).each{|n|mapping[parent+'/'+n.tr('.','_')+'.o']=n}
end
mapping[partition+'/inline-hash/Blake3.o']='Eggshell.Blake3'
used={}
args=Shellwords.split(File.read(cluster+'/runtime.rsp')).map do |arg|
  name=mapping[arg]
  next if name && (!runtimeNames.include?(name) || used[name])
  used[name]=true if name
  ordered.include?(name) ? root+'/'+name.tr('.','_')+'.o' : arg
end.compact
(ordered-used.keys).select{|n|runtimeNames.include?(n)}.each{|n|args.unshift(root+'/'+n.tr('.','_')+'.o')}
File.write(root+'/runtime.rsp',args.map{|a|JSON.generate(a)}.join("\n")+"\n")
abort 'runtime link failed' unless system(tool+'leanc','-o',root+'/eggshell','@'+root+'/runtime.rsp')
