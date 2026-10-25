require 'json'
require 'digest'
root=File.expand_path(__dir__)
abort 'retirement already recorded' if File.exist?(root+'/retirements.json')
Dir.glob(root+'/*.guard.json').each do |p|
  g=JSON.parse(File.read(p)); abort "live guard #{p}" unless g.fetch('state')=='finished' && g.fetch('ownedPids').empty?
end
entries=%w[VectorBlocksAudit VectorBlocksReadAudit].map do |name|
  path=root+'/'+name
  {path:path,bytes:File.size(path),sha256:Digest::SHA256.file(path).hexdigest,reason:'terminal rebuildable research helper; source, generated objects, link inputs and raw evidence retained'}
end
File.write(root+'/retirements.json',JSON.pretty_generate(entries)+"\n")
entries.each{|entry|File.unlink(entry.fetch(:path))}
puts JSON.generate({retired:entries.size,bytes:entries.map{|entry|entry.fetch(:bytes)}.sum,archivesCreated:false})
