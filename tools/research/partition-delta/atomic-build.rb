require 'json'
require 'shellwords'
root=File.expand_path(__dir__)
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
Dir.chdir(root+'/checkout')
bin='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/'
abort 'Lean atomic audit failed' unless system(bin+'lean','-j1','-M','1536','-DwarningAsError=true','-c',root+'/AtomicAudit.c','-o',root+'/checkout/.lake/build/lib/lean/AtomicAudit.olean',root+'/checkout/AtomicAudit.lean')
abort 'atomic C failed' unless system(bin+'leanc','-c','-O2','-o',root+'/AtomicAudit.o',root+'/AtomicAudit.c')
args=Shellwords.split(File.read(root+'/runtime.rsp')).map{|arg|arg==root+'/Main.o' ? root+'/AtomicAudit.o' : arg}
File.write(root+'/atomic.rsp',args.map{|arg|JSON.generate(arg)}.join("\n")+"\n")
abort 'atomic link failed' unless system(bin+'leanc','-o',root+'/atomic-audit','@'+root+'/atomic.rsp')
