require_relative "bxftools/credentials"
require_relative "bxftools/binary_manager"

module Bxftools
  class Error < StandardError; end
  class MissingKeyError < Error; end
  class DecryptionError < Error; end
end
