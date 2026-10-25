require 'json'
require 'fileutils'
require 'shellwords'
root=File.expand_path(__dir__)
parent='/Users/ovm/.codex/experiments/eggshell/block-score-20261025'
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
Dir.chdir(root+'/checkout')
lean='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean'
cc='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc'
names=ARGV.include?('--core') ? ['VectorPartition'] : ['VectorPartition','PartitionAudit']
selected=ARGV.include?('--audit') ? names.drop(1) : names
selected.each do |name|
  puts JSON.generate({compiling:name}); STDOUT.flush
  stem=name.tr('.','/')
  FileUtils.mkdir_p('.lake/build/lib/lean/'+File.dirname(stem))
  output=root+'/'+name.tr('.','_')
  abort "Lean failed #{name}" unless system(lean,'-j1','-M1536','-DwarningAsError=true','-c',output+'.c','-o','.lake/build/lib/lean/'+stem+'.olean',File.join(root,'checkout',stem+'.lean'))
  abort "C failed #{name}" unless system(cc,'-c','-O2','-o',output+'.o',output+'.c')
end
unless ARGV.include?('--core')
  args=Shellwords.split(File.read(parent+'/runtime.rsp')).reject{|p|p==parent+'/Main.o'}
  names.each{|name|args.unshift(root+'/'+name.tr('.','_')+'.o')}
  File.write(root+'/helper.rsp',args.map{|a|JSON.generate(a)}.join("\n")+"\n")
  abort 'helper link failed' unless system(cc,'-o',root+'/PartitionAudit','@'+root+'/helper.rsp')
end
