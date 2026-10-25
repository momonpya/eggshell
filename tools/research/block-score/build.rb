require 'json'
require 'shellwords'
require 'fileutils'
root=File.expand_path(__dir__)
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
Dir.chdir(root+'/checkout')
changed=JSON.parse(File.read(root+'/build-modules.json')).reject{|n|n=='tools.research.HookScaleRun'}
ordered=[];seen={};affected={}
visit=nil
visit=lambda do |name|
  return affected[name] if seen[name]
  seen[name]=true
  source=name.tr('.','/')+'.lean'
  unless File.file?(source)
    affected[name]=false
    next false
  end
  children=File.read(source).scan(/^(?:public\s+)?import\s+([A-Za-z0-9_.]+)/).flatten
  dependent=children.map{|child|visit.call(child)}.any?
  affected[name]=changed.include?(name)||dependent
  ordered<<name if affected[name]
  affected[name]
end
%w[Main Eggshell.ContractAudit].each{|n|visit.call(n)}
selected=ARGV.include?('--link-only') ? [] : ordered
if (index=ARGV.index('--from'))
  selected=selected.drop_while{|name|name!=ARGV[index+1]}
end
lean='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean'
cc='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc'
selected.each do |name|
  puts JSON.generate({compiling:name});STDOUT.flush
  output=root+'/'+name.tr('.','_')
  FileUtils.mkdir_p('.lake/build/lib/lean/'+File.dirname(name.tr('.','/')))
  abort "Lean failed #{name}" unless system(lean,'-j1','-M',name=='Eggshell.Handoff' ? '3072' : '1536','-DwarningAsError=true','-c',output+'.c','-o','.lake/build/lib/lean/'+name.tr('.','/')+'.olean',name.tr('.','/')+'.lean')
  abort "C failed #{name}" unless system(cc,'-c','-O2','-o',output+'.o',output+'.c')
end
mapping=JSON.parse(File.read(root+'/link-modules.json'))
used={}
args=Shellwords.split(File.read(root+'/link-basis.rsp')).map do |arg|
  name=mapping[arg]
  if ordered.include?(name) && name!='Eggshell.ContractAudit'
    next if used[name]
    used[name]=true
    root+'/'+name.tr('.','_')+'.o'
  else arg
  end
end.compact
(ordered-used.keys-['Eggshell.ContractAudit']).each{|name|args.unshift(root+'/'+name.tr('.','_')+'.o')}
File.write(root+'/runtime.rsp',args.map{|arg|JSON.generate(arg)}.join("\n")+"\n")
abort 'runtime link failed' unless system(cc,'-o',root+'/eggshell','@'+root+'/runtime.rsp')
