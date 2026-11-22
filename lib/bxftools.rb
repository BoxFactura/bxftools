require_relative "bxftools/captcha_model"
require_relative "bxftools/unar"

module Bxftools
  class Error < StandardError; end
  class MissingKeyError < Error; end
  class DecryptionError < Error; end

  # CFDI XML → PDF. Loaded on first use: it brings in wasmtime.
  autoload :Pdf, File.expand_path("bxftools/pdf", __dir__)
  autoload :Cipher, File.expand_path("bxftools/cipher", __dir__)
end
