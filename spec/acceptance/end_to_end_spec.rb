$: << File.join(File.dirname(__FILE__), '..', '..', 'lib')

require 'rspec'
require 'json'
require 'socket'
require 'tmpdir'

require 'camli_movie_tagger'

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
  secring = File.join(config_base, 'identity-secring.gpg')
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

def upload_test_file(filename)
  full_path = File.join(File.dirname(__FILE__), '..', 'fixtures',
                        'files', filename)
  sha = `camput file -filenodes #{full_path}`.lines.first.chomp
  fail unless sha =~ /\Asha1-[0-9a-f]+\z/
  sha
end

def set_attribute(sha, name, value)
  fail unless system('camput', 'attr', sha, name, value, out: '/dev/null')
end

def permanode_attributes_for(sha)
  json = JSON.parse(`camtool describe #{sha}`)
  json['meta'][sha]['permanode']['attr']
end

RSpec.describe 'CamliMovieTagger' do
  context 'for a given permanode with a TMDB ID' do
    subject do
      # Given: upload a test file, set it's tmdb_id attribute
      sha1 = upload_test_file('Serenity.mp4')
      set_attribute(sha1, 'tmdb_id', '16320')
      sha2 = upload_test_file('Avengers.mp4')
      set_attribute(sha2, 'tmdb_id', '24428')
      # When: Run the tagger on the uploaded sha
      tagger = CamliMovieTagger.new
      tagger.run([sha1])
      tagger.run([sha2])

      # inspect the permanode attributes after the run
      {
        serenity: permanode_attributes_for(sha1),
        avengers: permanode_attributes_for(sha2)
      }
    end

    it 'the title is set' do
      expect(subject[:serenity]).to include('title' => ['Serenity'])
      expect(subject[:avengers]).to include('title' => ['The Avengers'])
    end
  end
end
