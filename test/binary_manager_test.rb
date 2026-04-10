require_relative "test_helper"
require "securerandom"
require "tmpdir"
require "json"

class BinaryManagerTest < Minitest::Test
  def setup
    @key = SecureRandom.hex(32)
    @original_path = Bxftools::Credentials::CREDENTIALS_PATH
    @original_install_dir = Bxftools::BinaryManager::INSTALL_DIR
  end

  def test_downloads_binary_when_not_present
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      install_dir = File.join(dir, "bin")

      config = { "binary_url" => "https://releases.example.com/bxfpdf" }.to_json
      stub_credentials_path(enc_path) do
        Bxftools::Credentials.new(key: @key).write(config)

        stub_install_dir(install_dir) do
          stub_request(:get, "https://releases.example.com/bxfpdf")
            .to_return(status: 200, body: "#!/bin/sh\necho hello")

          ENV["BXFTOOLS_KEY"] = @key
          path = Bxftools::BinaryManager.ensure_binary!

          assert_equal File.join(install_dir, "bxfpdf-bin"), path
          assert File.executable?(path), "binary should be executable"
          assert_equal "#!/bin/sh\necho hello", File.read(path)
        end
      end
    end
  ensure
    ENV.delete("BXFTOOLS_KEY")
  end

  def test_skips_download_when_binary_exists
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      install_dir = File.join(dir, "bin")
      FileUtils.mkdir_p(install_dir)

      config = { "binary_url" => "https://releases.example.com/bxfpdf" }.to_json
      stub_credentials_path(enc_path) do
        Bxftools::Credentials.new(key: @key).write(config)

        stub_install_dir(install_dir) do
          binary = File.join(install_dir, "bxfpdf-bin")
          File.write(binary, "existing")
          File.chmod(0o755, binary)

          ENV["BXFTOOLS_KEY"] = @key
          path = Bxftools::BinaryManager.ensure_binary!

          assert_equal File.join(install_dir, "bxfpdf-bin"), path
          assert_equal "existing", File.read(path)
        end
      end
    end
  ensure
    ENV.delete("BXFTOOLS_KEY")
  end

  def test_returns_nil_without_key
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      stub_credentials_path(enc_path) do
        ENV.delete("BXFTOOLS_KEY")

        _output = capture_io do
          assert_nil Bxftools::BinaryManager.ensure_binary!
        end
      end
    end
  end

  def test_warns_without_key
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      stub_credentials_path(enc_path) do
        ENV.delete("BXFTOOLS_KEY")

        _, stderr = capture_io do
          Bxftools::BinaryManager.ensure_binary!
        end

        assert_equal "[bxftools] Set BXFTOOLS_KEY to decrypt credentials\n", stderr
      end
    end
  end

  def test_warns_on_download_failure
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      install_dir = File.join(dir, "bin")

      config = { "binary_url" => "https://releases.example.com/bxfpdf" }.to_json
      stub_credentials_path(enc_path) do
        Bxftools::Credentials.new(key: @key).write(config)

        stub_install_dir(install_dir) do
          stub_request(:get, "https://releases.example.com/bxfpdf")
            .to_return(status: 403, body: "Forbidden")

          ENV["BXFTOOLS_KEY"] = @key
          _, stderr = capture_io do
            result = Bxftools::BinaryManager.ensure_binary!
            assert_nil result
          end

          assert_equal "[bxftools] Failed to download binary: HTTP 403\n", stderr
        end
      end
    end
  ensure
    ENV.delete("BXFTOOLS_KEY")
  end

  private

  def stub_credentials_path(path)
    Bxftools::Credentials.send(:remove_const, :CREDENTIALS_PATH)
    Bxftools::Credentials.const_set(:CREDENTIALS_PATH, path)
    yield
  ensure
    Bxftools::Credentials.send(:remove_const, :CREDENTIALS_PATH)
    Bxftools::Credentials.const_set(:CREDENTIALS_PATH, @original_path)
  end

  def stub_install_dir(path)
    Bxftools::BinaryManager.send(:remove_const, :INSTALL_DIR)
    Bxftools::BinaryManager.const_set(:INSTALL_DIR, path)
    yield
  ensure
    Bxftools::BinaryManager.send(:remove_const, :INSTALL_DIR)
    Bxftools::BinaryManager.const_set(:INSTALL_DIR, @original_install_dir)
  end
end
