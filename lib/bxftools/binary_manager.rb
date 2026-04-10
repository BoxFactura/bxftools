require "json"
require "net/http"
require "uri"
require "fileutils"

module Bxftools
  class BinaryManager
    INSTALL_DIR = File.expand_path("../../bin", __dir__)
    BINARY_NAME = "bxfpdf-bin"

    def self.ensure_binary!
      new.ensure_binary!
    end

    def self.binary_path
      File.join(INSTALL_DIR, BINARY_NAME)
    end

    def initialize
      @binary_url = JSON.parse(Credentials.read).fetch("binary_url")
    rescue Bxftools::Error => e
      warn "[bxftools] #{e.message}"
      @binary_url = nil
    end

    def ensure_binary!
      return unless @binary_url
      return binary_path if File.executable?(binary_path)

      download!
      binary_path if File.executable?(binary_path)
    end

    def binary_path
      self.class.binary_path
    end

    private

    def download!
      FileUtils.mkdir_p(INSTALL_DIR)

      uri = URI(@binary_url)
      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        warn "[bxftools] Failed to download binary: HTTP #{response.code}"
        return
      end

      File.binwrite(binary_path, response.body)
      File.chmod(0o755, binary_path)
    end
  end
end
