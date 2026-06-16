require_relative "test_helper"
require "tmpdir"
require "fileutils"

class UnarTest < Minitest::Test
  PAYLOAD_DIR = Bxftools::Unar::UNAR_DIR

  def test_binary_path_points_inside_bin_unar
    assert_equal File.join(PAYLOAD_DIR, "unar"), Bxftools::Unar.binary_path
  end

  def test_payload_is_shipped_gzipped
    assert File.exist?(File.join(PAYLOAD_DIR, "unar.gz")), "unar.gz should be committed"
    assert File.exist?(File.join(PAYLOAD_DIR, "libgnustep-base.so.1.29.gz"))
    assert File.exist?(File.join(PAYLOAD_DIR, "libobjc.so.4.gz"))
  end

  def test_ensure_binary_expands_payload_and_marks_unar_executable
    Dir.mktmpdir do |dir|
      Dir[File.join(PAYLOAD_DIR, "*.gz")].each { |gz| FileUtils.cp(gz, dir) }

      stub_unar_dir(dir) do
        path = Bxftools::Unar.ensure_binary!

        assert_equal File.join(dir, "unar"), path
        assert File.executable?(path), "expanded unar should be executable"
        assert valid_elf?(path), "expanded unar should be a real ELF binary"
        assert File.exist?(File.join(dir, "libgnustep-base.so.1.29")), "gnustep lib should be expanded"
        assert File.exist?(File.join(dir, "libobjc.so.4")), "objc lib should be expanded"
      end
    end
  end

  def test_ensure_binary_returns_nil_on_unsupported_platform
    Bxftools::Unar.stub(:supported?, false) do
      assert_nil Bxftools::Unar.ensure_binary!
    end
  end

  def test_run_reports_unavailable_off_platform
    Bxftools::Unar.stub(:supported?, false) do
      result = Bxftools::Unar.run("anything.zip")
      refute result[:ok]
      assert_match(/unavailable/, result[:out])
    end
  end

  # End-to-end extraction. Only runs where the host can satisfy unar's
  # non-bundled deps (Ubuntu 24.04 / libicu74); skips elsewhere (e.g. the
  # 20.04 dev box), so the suite stays green without a matching host.
  def test_extracts_a_real_archive
    skip "host lacks libicu74 (run on Ubuntu 24.04)" unless host_libs_available?
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

  def host_libs_available?
    Bxftools::Unar.supported? && system("ldconfig -p | grep -q libicui18n.so.74")
  end

  def stub_unar_dir(path)
    Bxftools::Unar.send(:remove_const, :UNAR_DIR)
    Bxftools::Unar.const_set(:UNAR_DIR, path)
    yield
  ensure
    Bxftools::Unar.send(:remove_const, :UNAR_DIR)
    Bxftools::Unar.const_set(:UNAR_DIR, PAYLOAD_DIR)
  end
end
