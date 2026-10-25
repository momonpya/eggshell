require 'json'
require 'shellwords'
p=Dir.pwd
ENV['LEAN_PATH']=File.read(p+'/lean-path.txt').strip
lean='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean'
cc='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc'
Dir.chdir(p+'/checkout')
ARGV.each do |name|
  puts JSON.generate({helper:name});STDOUT.flush
  short=name.split('.').last
  out=p+'/'+short
  abort "helper Lean failed #{name}" unless system(lean,'-j1','-M','1536','-DwarningAsError=true','-c',out+'.c','-o','.lake/build/lib/lean/'+name.tr('.','/')+'.olean',name.tr('.','/')+'.lean')
  abort "helper C failed #{name}" unless system(cc,'-c','-O2','-o',out+'.o',out+'.c')
  next if ['StudyRuntime','ContractAudit'].include?(short)
  args=Shellwords.split(File.read(p+'/runtime.rsp')).map{|arg|arg==p+'/Main.o' ? out+'.o' : arg}
  abort 'wrong helper entrypoint' if args.include?(p+'/Main.o') || !args.include?(out+'.o')
  if short=='HookScaleRun'
    args=[p+'/StudyRuntime.o','/Users/ovm/.codex/experiments/eggshell/separated-discovery-20261025/ArtifactHash.o']+args
  end
  File.write(out+'.rsp',args.map{|arg|JSON.generate(arg)}.join("\n")+"\n")
  abort "helper link failed #{name}" unless system(cc,'-o',out,'@'+out+'.rsp')
end
