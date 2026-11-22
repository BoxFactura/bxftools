require_relative "test_helper"
require "tmpdir"

class PdfTest < Minitest::Test
  INDY = File.binread(File.expand_path("fixtures/cfdi-indiana-jones.xml", __dir__))
  NOT_A_CFDI = "esto no es XML".freeze
  CFDI_3_2 = %(<?xml version="1.0"?><cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/3" version="3.2"/>).freeze
  # 10,000 nested elements exhaust the engine's call stack: a real trap.
  TEMPLE_OF_DOOM = %(<cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/4" Version="4.0"><cfdi:Addenda>#{"<a>" * 10_000}#{"</a>" * 10_000}</cfdi:Addenda></cfdi:Comprobante>).freeze

  def pdf
    @pdf ||= Bxftools::Pdf.new
  end

  def page_count(document) = document[%r{/Type/Pages/Count (\d+)}, 1]

  def test_renders_the_cfdi_as_a_one_page_pdf
    document = pdf.render(INDY)

    assert_equal "%PDF-1.7", document.byteslice(0, 8)
    assert_equal "1", page_count(document)
  end

  def test_blank_is_one_empty_letter_page
    assert_equal "%PDF-1.7\n" \
                 "1 0 obj\n<</Type/Catalog/Pages 2 0 R>>\nendobj\n" \
                 "2 0 obj\n<</Type/Pages/Kids[3 0 R]/Count 1>>\nendobj\n" \
                 "3 0 obj\n<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>\nendobj\n" \
                 "xref\n0 4\n0000000000 65535 f \n0000000009 00000 n \n0000000054 00000 n \n0000000105 00000 n \n" \
                 "trailer\n<</Size 4/Root 1 0 R>>\nstartxref\n170\n%%EOF\n", Bxftools::Pdf.blank
  end

  def test_links_the_footer_to_boxfactura
    document = pdf.render(INDY)

    assert_equal [ true, false ], [ document.include?("boxfactura.com/pdf"), document.include?("neocfdi.com/pdf") ]
  end

  def test_neocfdi_brand_links_the_footer_to_neocfdi
    document = pdf.render(INDY, brand: "neocfdi")

    assert_equal [ false, true ], [ document.include?("boxfactura.com/pdf"), document.include?("neocfdi.com/pdf") ]
  end

  def test_reads_the_cfdi_as_the_templates_receive_it
    model = pdf.model(INDY)

    assert_equal(
      { "version" => "4.0", "serie" => "IJ", "folio" => "1936", "tipoDeComprobante" => "I", "moneda" => "MXN", "total" => "8978.40" },
      model.slice("version", "serie", "folio", "tipoDeComprobante", "moneda", "total")
    )
    assert_equal({ "rfc" => "MBA360612AB1", "nombre" => "MARCUS BRODY ANTIGÜEDADES" }, model["emisor"].slice("rfc", "nombre"))
    assert_equal({ "rfc" => "JOJH990701IJ3", "nombre" => "HENRY WALTON JONES JR" }, model["receptor"].slice("rfc", "nombre"))
    assert_equal [ "Ídolo de oro de los Chachapoyas", "Cruz de Coronado", "Látigo de cuero", "Sombrero fedora" ],
      model["conceptos"].map { |concepto| concepto["descripcion"] }
  end

  def test_rejects_a_cfdi_older_than_3_3
    error = assert_raises(Bxftools::Pdf::Error) { pdf.render(CFDI_3_2) }

    assert_equal "CFDI versión no soportada. Se requiere 3.3 o superior. Versión encontrada: no especificada", error.message
  end

  def test_rejects_text_that_is_not_a_cfdi
    error = assert_raises(Bxftools::Pdf::Error) { pdf.render(NOT_A_CFDI) }

    assert_equal "El XML no contiene un elemento raíz válido (Comprobante)", error.message
  end

  def test_turns_an_engine_trap_into_an_engine_error_that_is_a_pdf_error
    error = assert_raises(Bxftools::Pdf::EngineError) { pdf.render(TEMPLE_OF_DOOM) }

    assert_equal "El motor no pudo generar el PDF (wasm trap: call stack exhausted)", error.message
    assert_equal true, error.is_a?(Bxftools::Pdf::Error)
  end

  def test_keeps_rendering_after_an_engine_trap
    assert_raises(Bxftools::Pdf::EngineError) { pdf.render(TEMPLE_OF_DOOM) }

    assert_equal "1", page_count(pdf.render(INDY))
  end

  def test_keeps_rendering_after_a_rejected_document
    assert_raises(Bxftools::Pdf::Error) { pdf.render(NOT_A_CFDI) }

    assert_equal "1", page_count(pdf.render(INDY))
  end

  def test_ships_the_module_encrypted_and_never_plain
    assert_equal "BXF1", File.binread(Bxftools::Pdf::ENCRYPTED_PATH, 4)
    assert_equal [], Dir[File.expand_path("../lib/**/*.wasm", __dir__)]
  end

  def test_needs_the_key
    error = assert_raises(Bxftools::MissingKeyError) { Bxftools::Pdf.new(key: nil) }

    assert_equal "Set BXFTOOLS_KEY to use bxfpdf", error.message
  end

  def test_refuses_a_wrong_key
    error = assert_raises(Bxftools::DecryptionError) { Bxftools::Pdf.new(key: "0b" * 32) }

    assert_equal "Wrong BXFTOOLS_KEY, or the file is corrupted", error.message
  end

  def test_holds_no_memory_before_its_first_document
    assert_nil Bxftools::Pdf.new.memory_size
  end

  def test_keeps_its_instance_after_a_normal_invoice
    pdf.render(INDY)

    assert_equal true, pdf.memory_size.between?(1, 128 * 1024 * 1024)
  end

  # WebAssembly memory only grows: an instance that went past memory_limit (MB) is let go, and the
  # next document starts a fresh one.
  def test_lets_go_of_an_instance_that_grew_past_the_memory_limit
    short_leash = Bxftools::Pdf.new(memory_limit: 16)

    assert_equal "1", page_count(short_leash.render(INDY))
    assert_nil short_leash.memory_size
    assert_equal "1", page_count(short_leash.render(INDY))
    assert_nil short_leash.memory_size
  end

  # Even a fresh instance holds ~10 MB, so with a 1 MB limit a rejected document lets it go too.
  def test_lets_go_of_it_after_a_rejected_document_too
    shortest_leash = Bxftools::Pdf.new(memory_limit: 1)
    assert_raises(Bxftools::Pdf::Error) { shortest_leash.render(NOT_A_CFDI) }

    assert_nil shortest_leash.memory_size
  end

  def test_open_hands_one_instance_to_the_block_and_returns_what_the_block_returns
    pages = Bxftools::Pdf.open { |batch| [ page_count(batch.render(INDY)), page_count(batch.render(INDY)) ] }

    assert_equal [ "1", "1" ], pages
  end

  def test_open_lets_go_of_the_instance_when_the_block_ends
    batch = nil
    Bxftools::Pdf.open do |pdf|
      batch = pdf
      pdf.render(INDY)
    end

    assert_nil batch.memory_size
  end

  def test_open_lets_go_of_the_instance_when_the_block_raises
    batch = nil
    error = assert_raises(RuntimeError) do
      Bxftools::Pdf.open do |pdf|
        batch = pdf
        pdf.render(INDY)
        raise "It belongs in a museum"
      end
    end

    assert_equal "It belongs in a museum", error.message
    assert_nil batch.memory_size
  end

  def test_close_lets_go_of_the_instance_and_keeps_the_renderer_usable
    pdf.render(INDY)
    pdf.close

    assert_nil pdf.memory_size
    assert_equal "1", page_count(pdf.render(INDY))
  end

  def test_reports_the_module_version
    assert_equal "0.1.0", pdf.version.split(" ").first
  end

  def test_compiles_the_module_once_into_the_cache_directory
    Dir.mktmpdir do |dir|
      Bxftools::Pdf.new(cache_dir: dir)
      document = Bxftools::Pdf.new(cache_dir: dir).render(INDY)

      assert_equal [ ".cwasm" ], Dir.children(dir).map { |name| File.extname(name) }
      assert_equal "1", page_count(document)
    end
  end

  def test_compiles_in_memory_when_the_cache_directory_is_unusable
    Dir.mktmpdir do |dir|
      blocker = File.join(dir, "the-ark")
      File.write(blocker, "")
      fallback = nil
      _, stderr = capture_io { fallback = Bxftools::Pdf.new(cache_dir: File.join(blocker, "cache")) }

      assert_equal "[bxftools] cannot use #{blocker}/cache for the compiled module " \
                   "(File exists @ dir_s_mkdir - #{blocker}); compiling in memory\n", stderr
      assert_equal "1", page_count(fallback.render(INDY))
    end
  end
end
