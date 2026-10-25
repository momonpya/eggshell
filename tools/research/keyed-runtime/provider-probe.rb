require 'json'
require 'securerandom'

root = File.expand_path(__dir__)
output = File.join(root,ARGV.fetch(0,'provider-probe'))
abort 'preserve previous provider probe' if Dir.exist?(output)
Dir.mkdir(output)
summary = JSON.parse(File.read(File.join(root,'native-50000/summary.json')))
head = summary.fetch('source')
source = '/Users/ovm/.codex/experiments/eggshell/hook-scale-20261024/windows-50000/source.egg'
request = {query: summary.fetch('cases').first.fetch('question'),
  sources: [{owner: {database: head.fetch('identity'), directory: source},head: head}],
  leaves: 128,rows: 8192,receipt: SecureRandom.hex(32)}
input = File.join(output,'request.jsonl')
File.write(input,JSON.generate(request)+"\n")
env = {'EGGSHELL_PREFIX'=>'/Users/ovm/.codex/experiments/eggshell/hook-scale-20261024/prefix',
       'EGGSHELL_DATA_ROOT'=>File.join(root,'scale-data-50000')}
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
pid = Process.spawn(env,File.join(root,'eggshell'),'keyed-search-provider',
  in: input,out: File.join(output,'response.jsonl'),err: File.join(output,'stderr.txt'))
_, status = Process.wait2(pid)
elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round
reply = JSON.parse(File.read(File.join(output,'response.jsonl')))
abort "provider probe failed #{reply['error']}" unless status.success? && !reply.key?('error')
record = {elapsedMs: elapsed, exitCode: status.exitstatus,requestBytes: File.size(input),
  ranked: reply.fetch('ranked').length,related: reply.fetch('related').length,
  coverage: reply.fetch('coverage'),receipt: request.fetch(:receipt),
  scope: 'same pinned synthetic source and frozen question; provider only, no native deadline or answering model'}
File.write(File.join(output,'result.json'),JSON.pretty_generate(record)+"\n")
puts JSON.generate(record)
