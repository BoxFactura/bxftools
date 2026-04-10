require_relative "test_helper"
require "securerandom"
require "tmpdir"
require "json"

class CredentialsTest < Minitest::Test
  def setup
    @key = SecureRandom.hex(32)
    @original_path = Bxftools::Credentials::CREDENTIALS_PATH
  end

  def test_roundtrip_encrypt_decrypt
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      stub_credentials_path(enc_path) do
        plaintext = '{"binary_url":"https://example.com/bin","binary_name":"bxf"}'

        Bxftools::Credentials.new(key: @key).write(plaintext)

        assert File.exist?(enc_path), "credentials.enc should be created"
        refute_equal plaintext, File.read(enc_path), "encrypted file should not contain plaintext"

        decrypted = Bxftools::Credentials.new(key: @key).read
        assert_equal '{"binary_url":"https://example.com/bin","binary_name":"bxf"}', decrypted
      end
    end
  end

  def test_wrong_key_raises_decryption_error
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "credentials.enc")
      stub_credentials_path(enc_path) do
        Bxftools::Credentials.new(key: @key).write("secret stuff")

        wrong_key = SecureRandom.hex(32)
        assert_raises(Bxftools::DecryptionError) do
          Bxftools::Credentials.new(key: wrong_key).read
        end
      end
    end
  end

  def test_missing_key_raises_missing_key_error
    ENV.delete("BXFTOOLS_KEY")

    assert_raises(Bxftools::MissingKeyError) do
      Bxftools::Credentials.new(key: nil).read
    end
  end

  def test_missing_credentials_file_raises_error
    Dir.mktmpdir do |dir|
      enc_path = File.join(dir, "nonexistent.enc")
      stub_credentials_path(enc_path) do
        assert_raises(Bxftools::Error) do
          Bxftools::Credentials.new(key: @key).read
        end
      end
    end
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
end
