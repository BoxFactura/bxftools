require "zlib"
require "rbconfig"
require "open3"
require "fileutils"
require "rubygems/package"

module Bxftools
  # Ships the `unar` archive extractor, replacing the standalone unar_bxf gem.
  #
  # Following the bxfzip layout, the payload is a per-platform archive in bin/
  # named bxfunar-<os>-<version>_<arch>.tar.gz (e.g. bxfunar-ubuntu-24.04_amd64
  # .tar.gz). The right one is picked at runtime from /etc/os-release + the CPU,
  # or forced with BXFUNAR_SUFFIX. It is expanded in place on first use.
  #
  # unar links ~11 shared libraries, but the archive carries only the GNUstep
  # Objective-C runtime (libgnustep-base, libobjc) -- the libraries a stock host
  # never provides. Everything else unar needs (libicu74, libxml2, libxslt,
  # libdbus, libavahi) is resolved from the host at runtime, which keeps the
  # payload at ~3 MB instead of ~47 MB. This works because we pin to Ubuntu
  # 24.04, whose native library versions match the binary.
  class Unar
    BIN_DIR = File.expand_path("../../bin", __dir__)
    BINARY_NAME = "unar"

    class << self
      # Path to the gzipped tarball shipped for the current platform.
      def archive_path
        File.join(BIN_DIR, "bxfunar-#{suffix}.tar.gz")
      end

      # Directory the archive expands into (archive name minus .tar.gz).
      def payload_dir
        File.join(BIN_DIR, "bxfunar-#{suffix}")
      end

      def binary_path
        File.join(payload_dir, BINARY_NAME)
      end

      # A payload ships for this platform.
      def supported?
        File.exist?(archive_path)
      end

      # Absolute path to a ready-to-run unar binary, expanding the archive on
      # first call. Returns nil when no payload ships for this platform.
      def ensure_binary!
        return unless supported?

        expand_payload! unless File.executable?(binary_path)
        binary_path if File.executable?(binary_path)
      end

      # Replace the current process with unar. Used by the bxfunar executable.
      def exec!(*args)
        binary = ensure_binary!
        abort "[bxftools] no unar payload for this platform (#{suffix})" unless binary

        Kernel.exec(env, binary, *args.flatten.map(&:to_s))
      end

      # Run unar and capture its result: { ok:, out: }.
      def run(*args)
        binary = ensure_binary!
        return { ok: false, out: "[bxftools] unar unavailable for this platform (#{suffix})" } unless binary

        out, status = Open3.capture2e(env, binary, *args.flatten.map(&:to_s))
        { ok: status.success?, out: out }
      end

      # Platform suffix, e.g. "ubuntu-24.04_amd64". Mirrors bxfzip's detection
      # and honours a BXFUNAR_SUFFIX override.
      def suffix
        override = ENV["BXFUNAR_SUFFIX"].to_s
        return override unless override.empty?

        "#{os}_#{architecture}"
      end

      private

      def architecture
        case RbConfig::CONFIG["host_cpu"]
        when "arm64", "aarch64", "arch64" then "arm64"
        when "x86_64" then "amd64"
        else "i386"
        end
      end

      def os
        return "unknown" unless RbConfig::CONFIG["host_os"] =~ /linux/

        id = `. /etc/os-release 2> /dev/null && echo ${ID}_${VERSION_ID}`.strip
        id.start_with?("ubuntu_24.") ? "ubuntu-24.04" : id
      end

      # Bundled GNUstep libs take precedence; the rest resolve from the host.
      def env
        path = [ payload_dir, ENV["LD_LIBRARY_PATH"] ].compact.reject(&:empty?).join(":")
        { "LD_LIBRARY_PATH" => path }
      end

      def expand_payload!
        FileUtils.mkdir_p(payload_dir)

        Zlib::GzipReader.open(archive_path) do |gz|
          Gem::Package::TarReader.new(gz) do |tar|
            tar.each do |entry|
              next unless entry.file?

              dest = File.join(payload_dir, File.basename(entry.full_name))
              File.open(dest, "wb") { |file| file << entry.read }
              File.chmod(File.basename(dest) == BINARY_NAME ? 0o755 : 0o644, dest)
            end
          end
        end
      end
    end
  end
end
