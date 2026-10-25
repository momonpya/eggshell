require 'json'
require 'digest'
root=File.expand_path(__dir__)
plan=JSON.parse(File.read(root+'/plan.json'))
files=plan.fetch('sourceAndOriginalProjectionFiles')+plan.fetch('clonedProjectionFiles')
files.each do |f|
  path=f.fetch('path')
  abort "frozen input changed: #{path}" unless File.file?(path) && File.size(path)==f.fetch('bytes') && Digest::SHA256.file(path).hexdigest==f.fetch('sha256')
end
%w[routing blocks clustered].each{|dir|abort "duplicate vector body created: #{dir}" if File.exist?(plan.fetch('semantic')+'/'+dir)}
puts({verifiedFrozenFiles:files.size,duplicateVectorDirectories:0}.to_json)
