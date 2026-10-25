require 'json'
p=Dir.pwd
ENV['LEAN_PATH']=File.read(p+'/lean-path.txt').strip
plan=JSON.parse(File.read(p+'/build-plan.json'))
Dir.chdir(p+'/checkout')
started=ARGV.empty?
plan.fetch('modules').each do |name|
  started=true if name==ARGV.first
  next unless started
  puts JSON.generate({compiling:name}); STDOUT.flush
  out=p+'/'+name.tr('.','_')
  memory=name=='Eggshell.Handoff' ? '3072' : '1536'
  abort "Lean failed #{name}" unless system('/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean','-j1','-M',memory,'-DwarningAsError=true','-c',out+'.c','-o','.lake/build/lib/lean/'+name.tr('.','/')+'.olean',plan.fetch('sourceFiles').fetch(name))
  abort "C failed #{name}" unless system('/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc','-c','-O2','-o',out+'.o',out+'.c')
end
used={}
args=plan.fetch('extraObjects')+plan.fetch('args').map do |arg|
  name=plan.fetch('objectModules')[arg]
  if plan.fetch('modules').include?(name)
    next if used[name]
    used[name]=true
    p+'/'+name.tr('.','_')+'.o'
  else arg
  end
end.compact
(plan.fetch('modules')-used.keys).each{|name|args.unshift(p+'/'+name.tr('.','_')+'.o')}
File.write(p+'/runtime.rsp',args.map{|arg|JSON.generate(arg)}.join("\n")+"\n")
abort 'runtime link failed' unless system('/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc','-o',p+'/eggshell','@'+p+'/runtime.rsp')
