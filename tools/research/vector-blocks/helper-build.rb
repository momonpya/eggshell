require "shellwords"
require "json"
root=Dir.pwd
ENV["LEAN_PATH"]=File.read("lean-path.txt").strip
lean="/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
cc="/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/leanc"
Dir.chdir(root+"/checkout")
["Eggshell.VectorBlocks","tools.research.VectorBlocksAudit"].each do |name|
 out=root+"/"+name.split(".").last
 abort "Lean failed #{name}" unless system(lean,"-j1","-M","1536","-DwarningAsError=true","-c",out+".c","-o",".lake/build/lib/lean/"+name.tr(".","/")+".olean",name.tr(".","/")+".lean")
 abort "C failed #{name}" unless system(cc,"-c","-O2","-o",out+".o",out+".c")
end
parent="/Users/ovm/.codex/experiments/eggshell/lexical-advice-20261025"
args=[root+"/VectorBlocks.o"]+Shellwords.split(File.read(parent+"/runtime.rsp")).map{|a|a==parent+"/Main.o" ? root+"/VectorBlocksAudit.o" : a}
File.write(root+"/VectorBlocksAudit.rsp",args.map{|a|JSON.generate(a)}.join("\n")+"\n")
abort "link failed" unless system(cc,"-o",root+"/VectorBlocksAudit","@"+root+"/VectorBlocksAudit.rsp")
