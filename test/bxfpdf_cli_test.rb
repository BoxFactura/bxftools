require_relative "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

class BxfpdfCliTest < Minitest::Test
  BIN = File.expand_path("../bin/bxfpdf", __dir__)
  LIB = File.expand_path("../lib", __dir__)
  INDY = File.expand_path("fixtures/cfdi-indiana-jones.xml", __dir__)
  # 10,000 nested elements exhaust the engine's call stack: a real trap.
  TEMPLE_OF_DOOM = %(<cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/4" Version="4.0"><cfdi:Addenda>#{"<a>" * 10_000}#{"</a>" * 10_000}</cfdi:Addenda></cfdi:Comprobante>).freeze
  USAGE = "Uso: bxfpdf <input.xml> [input2.xml …]\n" \
          "      bxfpdf -i <input.xml> -o <output.pdf> [--brand bxf|neocfdi] [--logo imagen]\n".freeze

  # Runs bin/bxfpdf in `dir`: stdout, stderr with each timing as "(ms)", and the exit status.
  def bxfpdf(*args, dir:, env: {})
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "-I", LIB, BIN, *args, chdir: dir)
    [ stdout, stderr.gsub(/\(\d+\.\d ms\)/, "(ms)"), status.exitstatus ]
  end

  def test_writes_the_pdf_next_to_the_xml
    Dir.mktmpdir do |dir|
      FileUtils.cp(INDY, File.join(dir, "arca-perdida.xml"))

      assert_equal [ "", "arca-perdida.xml -> arca-perdida.pdf (ms)\n", 0 ], bxfpdf("arca-perdida.xml", dir: dir)
      assert_equal "%PDF-1.7", File.binread(File.join(dir, "arca-perdida.pdf"), 8)
    end
  end

  def test_renders_every_xml_it_gets
    Dir.mktmpdir do |dir|
      FileUtils.cp(INDY, File.join(dir, "arca-perdida.xml"))
      FileUtils.cp(INDY, File.join(dir, "templo-maldito.xml"))

      assert_equal [ "", "arca-perdida.xml -> arca-perdida.pdf (ms)\ntemplo-maldito.xml -> templo-maldito.pdf (ms)\n", 0 ],
        bxfpdf("arca-perdida.xml", "templo-maldito.xml", dir: dir)
      assert_equal [ "arca-perdida.pdf", "arca-perdida.xml", "templo-maldito.pdf", "templo-maldito.xml" ], Dir.children(dir).sort
    end
  end

  def test_writes_the_pdf_where_output_says_with_the_brand_it_gets
    Dir.mktmpdir do |dir|
      FileUtils.cp(INDY, File.join(dir, "arca-perdida.xml"))

      assert_equal [ "", "arca-perdida.xml -> ultima-cruzada.pdf (ms)\n", 0 ],
        bxfpdf("-i", "arca-perdida.xml", "-o", "ultima-cruzada.pdf", "--brand", "neocfdi", dir: dir)
      assert_equal [ "arca-perdida.xml", "ultima-cruzada.pdf" ], Dir.children(dir).sort
      assert_equal true, File.binread(File.join(dir, "ultima-cruzada.pdf")).include?("neocfdi.com/pdf")
    end
  end

  def test_writes_a_blank_pdf_for_a_document_it_cannot_render_renders_the_rest_and_exits_with_1
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "reino-calavera.xml"), "esto no es XML")
      FileUtils.cp(INDY, File.join(dir, "arca-perdida.xml"))

      assert_equal [ "", "reino-calavera.xml: El XML no contiene un elemento raíz válido (Comprobante) " \
                         "(PDF en blanco: reino-calavera.pdf)\n" \
                         "arca-perdida.xml -> arca-perdida.pdf (ms)\n", 1 ],
        bxfpdf("reino-calavera.xml", "arca-perdida.xml", dir: dir)
      assert_equal Bxftools::Pdf.blank, File.binread(File.join(dir, "reino-calavera.pdf"))
    end
  end

  def test_writes_a_blank_pdf_when_the_engine_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "templo-maldito.xml"), TEMPLE_OF_DOOM)

      assert_equal [ "", "templo-maldito.xml: El motor no pudo generar el PDF (wasm trap: call stack exhausted) " \
                         "(PDF en blanco: templo-maldito.pdf)\n", 1 ],
        bxfpdf("templo-maldito.xml", dir: dir)
      assert_equal Bxftools::Pdf.blank, File.binread(File.join(dir, "templo-maldito.pdf"))
    end
  end

  def test_writes_a_blank_pdf_where_output_says_when_the_xml_is_missing
    Dir.mktmpdir do |dir|
      assert_equal [ "", "cristal.xml: No such file or directory @ rb_sysopen - cristal.xml (PDF en blanco: calavera.pdf)\n", 1 ],
        bxfpdf("-i", "cristal.xml", "-o", "calavera.pdf", dir: dir)
      assert_equal Bxftools::Pdf.blank, File.binread(File.join(dir, "calavera.pdf"))
    end
  end

  def test_writes_blank_pdfs_without_the_key_and_exits_with_1
    Dir.mktmpdir do |dir|
      FileUtils.cp(INDY, File.join(dir, "arca-perdida.xml"))

      assert_equal [ "", "arca-perdida.xml: Set BXFTOOLS_KEY to use bxfpdf (PDF en blanco: arca-perdida.pdf)\n", 1 ],
        bxfpdf("arca-perdida.xml", dir: dir, env: { "BXFTOOLS_KEY" => nil })
      assert_equal Bxftools::Pdf.blank, File.binread(File.join(dir, "arca-perdida.pdf"))
    end
  end

  def test_writes_blank_pdfs_when_the_logo_cannot_be_read
    Dir.mktmpdir do |dir|
      FileUtils.cp(INDY, File.join(dir, "arca-perdida.xml"))

      assert_equal [ "", "arca-perdida.xml: idolo.png: No such file or directory @ rb_sysopen - idolo.png " \
                         "(PDF en blanco: arca-perdida.pdf)\n", 1 ],
        bxfpdf("arca-perdida.xml", "--logo", "idolo.png", dir: dir)
      assert_equal Bxftools::Pdf.blank, File.binread(File.join(dir, "arca-perdida.pdf"))
    end
  end

  def test_shows_the_usage_without_inputs
    Dir.mktmpdir do |dir|
      assert_equal [ "", USAGE, 1 ], bxfpdf(dir: dir)
    end
  end

  def test_refuses_one_output_for_several_inputs
    Dir.mktmpdir do |dir|
      assert_equal [ "", "Error: --output solo se puede usar con un archivo de entrada\n", 1 ],
        bxfpdf("arca-perdida.xml", "templo-maldito.xml", "-o", "ultima-cruzada.pdf", dir: dir)
    end
  end
end
