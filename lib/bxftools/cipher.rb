# frozen_string_literal: true

require "openssl"

module Bxftools
  # AES-256-GCM with BXFTOOLS_KEY (64 hex characters, `rake key:generate`), for what the gem ships
  # encrypted: lib/bxftools/bxfpdf.wasm.enc. Layout: "BXF1", the 12-byte IV, the 16-byte
  # authentication tag, the ciphertext.
  module Cipher
    ENV_KEY = "BXFTOOLS_KEY"
    MAGIC = "BXF1".b.freeze

    module_function

    def encrypt(plaintext, key)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = binary_key(key)
      iv = cipher.random_iv
      cipher.auth_data = MAGIC
      ciphertext = cipher.update(plaintext) + cipher.final
      MAGIC + iv + cipher.auth_tag + ciphertext
    end

    def decrypt(data, key)
      binary = binary_key(key)
      raise DecryptionError, "Not a file encrypted with #{ENV_KEY}" unless data.b.start_with?(MAGIC)

      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = binary
      cipher.iv = data.byteslice(4, 12)
      cipher.auth_tag = data.byteslice(16, 16)
      cipher.auth_data = MAGIC
      cipher.update(data.byteslice(32..)) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      raise DecryptionError, "Wrong #{ENV_KEY}, or the file is corrupted"
    end

    def binary_key(key)
      raise MissingKeyError, "Set #{ENV_KEY} to use bxfpdf" if key.nil? || key.empty?
      raise MissingKeyError, "#{ENV_KEY} must be 64 hex characters" unless key.match?(/\A\h{64}\z/)

      [ key ].pack("H*")
    end
  end
end
