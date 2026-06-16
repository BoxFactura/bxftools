require "zlib"
require "rbconfig"
require "open3"

module Bxftools
  # Ships the `unar` archive extractor for linux x86_64 (built on Ubuntu 24.04),
  # replacing the standalone unar_bxf gem.
  #
  # unar links ~11 shared libraries, but only the GNUstep Objective-C runtime
  # (libgnustep-base, libobjc) is bundled here, since a stock host never
  # provides it. Everything else unar needs -- libicu74, libxml2, libxslt,
  # libdbus, libavahi -- is resolved from the host at runtime. That keeps the
  # shipped payload at ~3 MB gzipped instead of ~47 MB, and works because we
  # pin to Ubuntu 24.04, whose native library versions match the binary.
  #
  # The binary and its two libraries are committed gzipped under bin/unar/ and
  # expanded in place on first use, mirroring the bxfzip launcher.
  class Unar
    UNAR_DIR = File.expand_path("../../bin/unar", __dir__)
    BINARY_NAME = "unar"

    class << self
      def binary_path
        File.join(UNAR_DIR, BINARY_NAME)
      end

      def supported?
        RbConfig::CONFIG["host_os"] =~ /linux/ &&
          %w[x86_64 amd64].include?(RbConfig::CONFIG["host_cpu"])
      end

      # Absolute path to a ready-to-run unar binary, expanding the gzipped
      # payload on first call. Returns nil on an unsupported platform.
      def ensure_binary!
        return unless supported?

        expand_payload!
        binary_path if File.executable?(binary_path)
      end

      # Replace the current process with unar. Used by the bxfunar executable.
      def exec!(*args)
        binary = ensure_binary!
        abort "[bxftools] unar is only available on linux x86_64" unless binary

        Kernel.exec(env, binary, *args.flatten.map(&:to_s))
      end

      # Run unar and capture its result: { ok:, out: }.
      def run(*args)
        binary = ensure_binary!
        return { ok: false, out: "[bxftools] unar unavailable on this platform" } unless binary

        out, status = Open3.capture2e(env, binary, *args.flatten.map(&:to_s))
        { ok: status.success?, out: out }
      end

      private

      # Bundled GNUstep libs take precedence; the rest resolve from the host.
      def env
        path = [UNAR_DIR, ENV["LD_LIBRARY_PATH"]].compact.reject(&:empty?).join(":")
        { "LD_LIBRARY_PATH" => path }
      end

      def expand_payload!
        Dir[File.join(UNAR_DIR, "*.gz")].each do |gz|
          dest = gz.delete_suffix(".gz")
          next if File.exist?(dest)

          File.open(dest, "wb") do |file|
            Zlib::GzipReader.open(gz) { |gzip| file << gzip.read }
          end
          File.chmod(0o755, dest) if File.basename(dest) == BINARY_NAME
        end
      end
    end
  end
end
