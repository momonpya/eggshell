require 'json'
require 'shellwords'
p=Dir.pwd
root=p+'/checkout'
files={}
Dir.glob(root+'/{Eggshell,tools}/**/*.lean').each{|path|files[path.sub(root+'/','').sub(/\.lean$/,'').tr('/','.')]=path.sub(root+'/','')}
files['Main']='Main.lean'
imports={}
files.each{|name,path|imports[name]=File.read(root+'/'+path).lines.filter{|line|line.match?(/^(?:public |meta )?import /)}.flat_map{|line|line.sub(/^(?:public |meta )?import /,'').strip.split(/\s+/)}.select{|name|files.key?(name)}}
changed=%w[Eggshell.VectorRoute Eggshell.KeyedProtocol Eggshell.KeyedSearchClient Eggshell.KeyedSearchProvider Eggshell.Warm Eggshell.Handoff Main]
affected=changed.dup
loop do
  next_set=affected+(imports.select{|name,deps|deps.any?{|dep|affected.include?(dep)}}.keys)
  next_set=next_set.uniq
  break if next_set==affected
  affected=next_set
end
needed=[]
visit=lambda{|name|return if needed.include?(name); (imports[name]||[]).each{|dep|visit.call(dep)}; needed << name}
visit.call('Main')
modules=needed.select{|name|affected.include?(name)}
old='/Users/ovm/.codex/experiments/eggshell/empty-search-20261025'
base=JSON.parse(File.read(old+'/build-plan.json'))
map=base.fetch('objectModules')
%w[Eggshell.PluginHooks Eggshell.PluginCli Eggshell.Daemon Eggshell.Install Eggshell.Setup Main].each{|name|map[old+'/'+name.tr('.','_')+'.o']=name}
args=Shellwords.split(File.read(old+'/runtime.rsp'))
File.write(p+'/build-plan.json',JSON.pretty_generate({modules:modules,affected:affected,sourceFiles:files,objectModules:map,args:args,extraObjects:['/Users/ovm/.codex/experiments/eggshell/keyed-advice-20261025/WindowOwners.o']})+"\n")
puts JSON.generate({modules:modules})
