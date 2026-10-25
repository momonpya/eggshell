require 'json'
require 'shellwords'
root=File.expand_path(__dir__)
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
lean='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean'
cc='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc'
Dir.chdir(root+'/checkout')
name='tools/research/VectorBlocksReadAudit'
out=root+'/VectorBlocksReadAudit'
abort 'Lean failed' unless system(lean,'-j1','-M','1536','-DwarningAsError=true','-c',out+'.c','-o','.lake/build/lib/lean/'+name+'.olean',name+'.lean')
abort 'C failed' unless system(cc,'-c','-O2','-o',out+'.o',out+'.c')
args=Shellwords.split(File.read(root+'/VectorBlocksAudit.rsp')).map{|p|p==root+'/VectorBlocksAudit.o' ? out+'.o' : p}
File.write(out+'.rsp',args.map{|p|JSON.generate(p)}.join("\n")+"\n")
abort 'link failed' unless system(cc,'-o',out,'@'+out+'.rsp')
