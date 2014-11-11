require 'rspec'
require 'json'
require 'socket'
require 'tmpdir'

PORT = 30000 + rand(1000)

RSpec.configure do |config|
  config.before(:suite) do
    @d = Dir.mktmpdir
    write_camli_test_config(@d)
    ENV['HOME'] = @d
    @camlistored_pid =
      Process.spawn('camlistored -openbrowser=false > /dev/null 2>&1')
    # Wait for port to open
    Timeout::timeout(10) do
      while true
        begin
          TCPSocket.new('localhost', PORT).close
          break
        rescue Errno::ECONNREFUSED
          sleep 0.1
        end
      end
    end
    # Check if we can send a blob
    fail unless `echo "testing" | camput blob -` =~ /^sha1-/
  end

  config.after(:suite) do
    Process.kill('TERM', @camlistored_pid)
    Process.wait @camlistored_pid
    FileUtils.remove_entry @d
  end
end

def write_camli_test_config(home_dir)
  config_base = File.join(home_dir, '.config', 'camlistore')
  secring_source = File.join(File.dirname(__FILE__), '..', 'fixtures', 'secring.gpg')
  secring = File.join(config_base, 'secring.gpg')
  server_config_file = File.join(config_base, 'server-config.json')
  client_config_file = File.join(config_base, 'client-config.json')

  blobpath = File.join(home_dir, 'blobs')
  sqlite_path = File.join(home_dir, 'index.db')
  identity = '96F730DB'

  FileUtils.mkdir_p config_base
  FileUtils.cp secring_source, secring

  server_config = {
    identitySecretRing: secring,
    identity: identity,
    auth: 'none',
    listen: ":#{PORT}",
    blobPath: blobpath,
    sqlite: sqlite_path
  }

  client_config = {
    identity: identity,
    servers: {
      test: {
        server: "http://localhost:#{PORT}",
        auth: 'none',
        default: true
      }
    }
  }

  File.open(server_config_file, 'w') do |file|
    file.puts(server_config.to_json)
  end

  File.open(client_config_file, 'w') do |file|
    file.puts(client_config.to_json)
  end
end
