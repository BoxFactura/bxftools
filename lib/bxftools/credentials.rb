require "openssl"
require "base64"
require "json"

module Bxftools
  class Credentials
    CREDENTIALS_PATH = File.expand_path("../../credentials.enc", __dir__)
    ENV_KEY = "BXFTOOLS_KEY"
    CIPHER = "aes-256-gcm"

    def self.read
      new.read
    end

    def self.write(data, key)
      new(key: key).write(data)
    end

    def initialize(key: nil)
      @key = key || ENV[ENV_KEY]
    end

    def read
      raise MissingKeyError, "Set #{ENV_KEY} to decrypt credentials" unless @key
      raise Error, "No credentials file at #{CREDENTIALS_PATH}" unless File.exist?(CREDENTIALS_PATH)

      decrypt(File.binread(CREDENTIALS_PATH))
    end

    def write(data)
      raise MissingKeyError, "Key is required to encrypt credentials" unless @key

      File.binwrite(CREDENTIALS_PATH, encrypt(data))
    end

    private

    def encryption_key
      # The key is hex-encoded 32 bytes (like Rails)
      [ @key ].pack("H*")
    end

    def encrypt(plaintext)
      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.encrypt
      cipher.key = encryption_key
      iv = cipher.random_iv

      encrypted = cipher.update(plaintext) + cipher.final
      tag = cipher.auth_tag

      # Pack as: iv (12 bytes) + tag (16 bytes) + ciphertext
      Base64.strict_encode64(iv + tag + encrypted)
    end

    def decrypt(encoded)
      raw = Base64.strict_decode64(encoded)

      iv = raw[0, 12]
      tag = raw[12, 16]
      ciphertext = raw[28..]

      cipher = OpenSSL::Cipher.new(CIPHER)
      cipher.decrypt
      cipher.key = encryption_key
      cipher.iv = iv
      cipher.auth_tag = tag

      cipher.update(ciphertext) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      raise DecryptionError, "Wrong key or corrupted credentials file"
    end
  end
end
