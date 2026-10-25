require 'json'
require 'fileutils'
require 'digest'
root=File.expand_path(__dir__)
parent='/Users/ovm/.codex/experiments/eggshell/source-stream-20261025'
base='/Users/ovm/.codex/experiments/eggshell/block-score-20261025'
id='eb5d3f9baf77963bfcfdc94afde22939b244236c8a6ef70bf4c12133b3058971'
source=base+'/fixtures/source-50000.egg'
guard=base+'/resource-controller/StudyMain'
FileUtils.mkdir_p(root+'/preparation')
FileUtils.mkdir_p(root+'/scale-data/read-cache')
destination=root+'/scale-data/read-cache/'+id
abort 'preserve existing scale basis' if File.exist?(destination)
abort 'APFS private basis clone failed' unless system('/bin/cp','-cR',parent+'/scale-data/read-cache/'+id,destination)
File.write(root+'/preparation/config.toml',File.read(parent+'/preparation/config.toml').gsub(parent,root))
FileUtils.mkdir_p(root+'/prefix/share/eggshell')
File.symlink('/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm',root+'/prefix/share/eggshell/minilm')
env=['/usr/bin/env','EGGSHELL_PREFIX='+root+'/prefix','EGGSHELL_DATA_ROOT='+root+'/scale-data',
  'PLUGIN_ROOT='+root+'/prefix/plugins/eggshell','EGGSHELL_CONFIG='+root+'/preparation/config.toml']
settings=lambda do |name,args|
  x={cwd:root,limitRssKiB:3670016,minFreeKiB:524288,ownedPrefixes:[root],record:root+"/#{name}.guard.json",command:env+args}
  File.write(root+"/#{name}.settings.json",JSON.pretty_generate(x)+"\n")
end
settings.call('fixture',[root+'/eggshell','canonical-delta-fixture',root+'/fixture'])
settings.call('payload',[root+'/eggshell','stage-native-payload',root+'/prefix'])
settings.call('base',[root+'/prefix/libexec/eggshell','canonical-delta-base',source,root+'/preparation/base.json'])
settings.call('native',[root+'/eggshell','native-hook-audit',root+'/prefix/libexec/eggshell',root+'/prefix/plugins/eggshell',source,root+'/native-50000','3'])
puts({privateBasis:destination,source:source,runtimeSha256:Digest::SHA256.file(root+'/eggshell').hexdigest}.to_json)
