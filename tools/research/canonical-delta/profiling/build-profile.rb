require 'shellwords'
r=File.expand_path(__dir__)
ENV['LEAN_PATH']=File.read(r+'/lean-path.txt').strip
Dir.chdir(r)
t='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/'
abort 'Lean stage audit failed' unless system(t+'lean','-j1','-M','1536','-DwarningAsError=true','-c',r+'/WarmStagesAudit.c',r+'/WarmStagesAudit.lean')
abort 'C stage audit failed' unless system(t+'leanc','-c','-O2','-o',r+'/WarmStagesAudit.o',r+'/WarmStagesAudit.c')
abort 'link stage audit failed' unless system(t+'leanc','-o',r+'/warm-stages','@'+r+'/runtime.rsp')
