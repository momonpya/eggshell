require 'json'
require 'fileutils'
require 'digest'
root=File.expand_path(__dir__)
base='/Users/ovm/.codex/experiments/eggshell/block-score-20261025'
parent='/Users/ovm/.codex/experiments/eggshell/partition-delta-20261025'
id='eb5d3f9baf77963bfcfdc94afde22939b244236c8a6ef70bf4c12133b3058971'
source=root+'/mutation-source.egg'
data=root+'/mutation-data'
abort 'preserve earlier mutation input' if File.exist?(data)||File.exist?(source)
clone=lambda do |a,b|
  FileUtils.mkdir_p(File.dirname(b))
  abort 'clone target exists' if File.exist?(b)
  abort "APFS clone failed: #{a}" unless system('/bin/cp','-cR',a,b)
end
clone.call(parent+'/mutation-retention-source.egg',source)
clone.call(root+'/scale-data/read-cache/'+id,data+'/read-cache/'+id)
semantic=data+'/read-cache/'+id+'/semantic'
%w[projections vectors].each do |name|
  FileUtils.rm_rf(semantic+'/'+name)
  clone.call(parent+'/mutation-retention-data/read-cache/'+id+'/semantic/'+name,semantic+'/'+name)
end
lexical=base+'/fixtures/source-50000.egg/derived/'+id+'/lexical'
target=data+'/read-cache/'+id+'/lexical'
FileUtils.rm_rf(target)
clone.call(lexical,target)
Dir.glob(target+'/**/*',File::FNM_DOTMATCH).each do |p|
  next if ['.','..'].include?(File.basename(p))
  old=lexical+p.delete_prefix(target)
  abort 'clone aliases original inode' if File.stat(p).ino==File.stat(old).ino
  File.chmod(File.directory?(p) ? 0700 : 0600,p)
end
File.chmod(0700,target)
FileUtils.mkdir_p(root+'/mutation')
config=File.read(root+'/preparation/config.toml').sub(base+'/fixtures/source-50000.egg',source)
File.write(root+'/mutation/config.toml',config)
env=['/usr/bin/env','EGGSHELL_PREFIX='+root+'/prefix','EGGSHELL_DATA_ROOT='+data,
  'PLUGIN_ROOT='+root+'/prefix/plugins/eggshell','EGGSHELL_CONFIG='+root+'/mutation/config.toml']
%w[first repeat].each do |stage|
  command=env+['/bin/sh','-c','exec "$1" egg warm "$2" > "$3"','warm',root+'/prefix/libexec/eggshell',source,root+"/mutation/#{stage}.json"]
  x={cwd:root,record:root+"/mutation-#{stage}.guard.json",command:command,limitRssKiB:3670016,
    minFreeKiB:524288,ownedPrefixes:[root]}
  File.write(root+"/mutation-#{stage}.settings.json",JSON.pretty_generate(x)+"\n")
end
files=Dir[source+'/*'].select{|p|File.file?(p)}.sort.map{|p|{path:p,bytes:File.size(p),sha256:Digest::SHA256.file(p).hexdigest}}
File.write(root+'/mutation/inputs.json',JSON.pretty_generate({sourceParent:parent+'/mutation-retention-source.egg',
  privateBasis:root+'/scale-data/read-cache/'+id,projectionBasis:parent+'/mutation-retention-data/read-cache/'+id+'/semantic',
  privateLexicalBasis:lexical,files:files})+"\n")
puts({source:source,files:files.size}.to_json)
