require_relative "bxftools/credentials"
require_relative "bxftools/binary_manager"
require_relative "bxftools/captcha_model"

module Bxftools
  class Error < StandardError; end
  class MissingKeyError < Error; end
  class DecryptionError < Error; end
end
