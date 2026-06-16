require_relative "test_helper"
require "tmpdir"
require "fileutils"

class UnarTest < Minitest::Test
  BIN_DIR = Bxftools::Unar::BIN_DIR
  SUFFIX = "ubuntu-24.04_amd64"
  ARCHIVE = File.join(BIN_DIR, "bxfunar-#{SUFFIX}.tar.gz")

  def teardown
    ENV.delete("BXFUNAR_SUFFIX")
  end

  def test_ships_a_single_consolidated_archive
    archives = Dir[File.join(BIN_DIR, "bxfunar-*.tar.gz")]
    assert_equal 1, archives.size, "expected exactly one consolidated payload, got: #{archives}"
    assert_equal ARCHIVE, archives.first
  end

  def test_naming_follows_bxfzip_suffix_pattern
    ENV["BXFUNAR_SUFFIX"] = SUFFIX
    assert_equal ARCHIVE, Bxftools::Unar.archive_path
    assert_equal File.join(BIN_DIR, "bxfunar-#{SUFFIX}"), Bxftools::Unar.payload_dir
    assert_equal File.join(BIN_DIR, "bxfunar-#{SUFFIX}", "unar"), Bxftools::Unar.binary_path
  end

  def test_bxfunar_suffix_env_overrides_detection
    ENV["BXFUNAR_SUFFIX"] = "custom-os_arch"
    assert_equal "custom-os_arch", Bxftools::Unar.suffix
  end

  def test_ensure_binary_expands_consolidated_archive
    Dir.mktmpdir do |dir|
      FileUtils.cp(ARCHIVE, File.join(dir, "bxfunar-#{SUFFIX}.tar.gz"))
      ENV["BXFUNAR_SUFFIX"] = SUFFIX

      stub_bin_dir(dir) do
        path = Bxftools::Unar.ensure_binary!

        assert_equal File.join(dir, "bxfunar-#{SUFFIX}", "unar"), path
        assert File.executable?(path), "expanded unar should be executable"
        assert valid_elf?(path), "expanded unar should be a real ELF binary"

        payload = File.join(dir, "bxfunar-#{SUFFIX}")
        assert File.exist?(File.join(payload, "libgnustep-base.so.1.29")), "gnustep lib should be expanded"
        assert File.exist?(File.join(payload, "libobjc.so.4")), "objc lib should be expanded"
      end
    end
  end

  def test_unsupported_platform_returns_nil
    ENV["BXFUNAR_SUFFIX"] = "no-such-os_arch"
    assert_nil Bxftools::Unar.ensure_binary!

    result = Bxftools::Unar.run("anything.zip")
    refute result[:ok]
    assert_match(/unavailable/, result[:out])
  end

  # End-to-end extraction. Only runs where a payload ships for the detected
  # platform and the host can satisfy unar's non-bundled deps (libicu74);
  # skips elsewhere (e.g. the 20.04 dev box), so the suite stays green.
  def test_extracts_a_real_archive
    skip "no payload for this platform (#{Bxftools::Unar.suffix})" unless Bxftools::Unar.supported?
    skip "host lacks libicu74" unless system("ldconfig -p | grep -q libicui18n.so.74")
    skip "zip not installed" unless system("which zip > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "triforce.txt"), "courage, wisdom, power")
      system("cd #{dir} && zip -q hyrule.zip triforce.txt && rm triforce.txt")

      out_dir = File.join(dir, "out")
      result = Bxftools::Unar.run("-force-overwrite", "-output-directory", out_dir, File.join(dir, "hyrule.zip"))

      assert result[:ok], "extraction failed: #{result[:out]}"
      assert File.exist?(File.join(out_dir, "triforce.txt")), "extracted file missing"
    end
  end

  private

  def valid_elf?(path)
    File.binread(path, 4) == "\x7fELF".b
  end

  def stub_bin_dir(path)
    Bxftools::Unar.send(:remove_const, :BIN_DIR)
    Bxftools::Unar.const_set(:BIN_DIR, path)
    yield
  ensure
    Bxftools::Unar.send(:remove_const, :BIN_DIR)
    Bxftools::Unar.const_set(:BIN_DIR, BIN_DIR)
  end
end
