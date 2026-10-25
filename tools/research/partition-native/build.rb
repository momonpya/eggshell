require 'json'
require 'shellwords'
require 'fileutils'
root=File.expand_path(__dir__)
parent='/Users/ovm/.codex/experiments/eggshell/block-score-20261025'
partition='/Users/ovm/.codex/experiments/eggshell/vector-partition-20261025'
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
Dir.chdir(root+'/checkout')
changed=%w[VectorPartition PartitionBuild PartitionNativeAudit Eggshell.KeyedProtocol Eggshell.KeyedSearchClient Eggshell.KeyedSearchProvider Eggshell.Warm Main]
seen={};affected={};ordered=[]
visit=nil
visit=lambda do |name|
  return affected[name] if seen[name]
  seen[name]=true
  path=name.tr('.','/')+'.lean'
  unless File.file?(path);affected[name]=false;next false;end
  children=File.read(path).scan(/^(?:public\s+)?import\s+([A-Za-z0-9_.]+)/).flatten
  dependent=children.map{|n|visit.call(n)}.any?
  affected[name]=changed.include?(name)||dependent
  ordered<<name if affected[name]
  affected[name]
end
%w[Main Eggshell.ContractAudit].each{|n|visit.call(n)}
File.write(root+'/modules.json',JSON.pretty_generate(ordered)+"\n")
selected=ARGV.include?('--link-only') ? [] : ordered
if (i=ARGV.index('--from'));selected=selected.drop_while{|n|n!=ARGV[i+1]};end
lean='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean'
cc='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc'
selected.each do |name|
  path=name.tr('.','/')
  source=path+'.lean'
  if File.symlink?(source)
    content=File.binread(source)
    File.unlink(source)
    File.binwrite(source,content)
  end
  stem=
'.lake/build/lib/lean/'+path
  FileUtils.mkdir_p(File.dirname(stem))
  Dir.glob(stem+'.*').each{|p|File.unlink(p) if File.symlink?(p)}
  puts JSON.generate({compiling:name});STDOUT.flush
  output=root+'/'+name.tr('.','_')
  abort "Lean failed #{name}" unless system(lean,'-j1','-M',name=='Eggshell.Handoff' ? '3072' : '1536','-DwarningAsError=true','-c',output+'.c','-o',stem+'.olean',File.join(root,'checkout',path+'.lean'))
  abort "C failed #{name}" unless system(cc,'-c','-O2','-o',output+'.o',output+'.c')
end
mapping=JSON.parse(File.read(parent+'/link-modules.json'))
used={}
args=Shellwords.split(File.read(parent+'/runtime.rsp')).map do |arg|
  name=mapping[arg]
  name='Main' if arg==parent+'/Main.o'
  if ordered.include?(name) && name!='Eggshell.ContractAudit'
    next if used[name]
    used[name]=true
    root+'/'+name.tr('.','_')+'.o'
  else arg
  end
end.compact
(ordered-used.keys-['Eggshell.ContractAudit']).each{|name|args.unshift(root+'/'+name.tr('.','_')+'.o')}
# The parent native runtime predates this new module.
File.write(root+'/runtime.rsp',args.map{|a|JSON.generate(a)}.join("\n")+"\n")
abort 'native link failed' unless system(cc,'-o',root+'/eggshell','@'+root+'/runtime.rsp')
