require 'shellwords'
root=File.expand_path(__dir__)
ENV['LEAN_PATH']=File.read(root+'/lean-path.txt').strip
toolchain='/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/'
Dir.chdir(root+'/checkout')
abort 'Lean BLAKE3 compile failed' unless system(toolchain+'lean','-j1','-M','1536',
  '-DwarningAsError=true','-c',root+'/Blake3.c','-o','.lake/build/lib/lean/Eggshell/Blake3.olean',
  root+'/checkout/Eggshell/Blake3.lean')
abort 'native BLAKE3 compile failed' unless system(toolchain+'leanc','-c','-O2','-o',root+'/Blake3.o',root+'/Blake3.c')
abort 'native runtime link failed' unless system(toolchain+'leanc','-o',root+'/eggshell','@'+root+'/runtime.rsp')
