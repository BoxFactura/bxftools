# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "wasmtime"

module Bxftools
  # CFDI XML → PDF with the bxfpdf WebAssembly module, run by wasmtime. The same module works on
  # every platform wasmtime runs on. It ships encrypted (lib/bxftools/bxfpdf.wasm.enc, see Cipher),
  # so rendering needs BXFTOOLS_KEY; wasm-pdfgen's `npm run export:bxftools` puts a new one in.
  #
  #   Bxftools::Pdf.open do |pdf|                                     # one instance for a batch,
  #     pdf.render(File.binread("factura.xml"))                       # let go when the block ends
  #   end
  #   pdf = Bxftools::Pdf.new                                         # or keep one and close it
  #   pdf.render(xml, brand: "neocfdi", logo: File.binread("logo.png"))
  #   pdf.model(xml)                                                  # the parsed CFDI, a Hash
  #   pdf.close
  #
  # Compiling the module to machine code takes several seconds, so the compiled form is kept in
  # `cache_dir` (BXFTOOLS_CACHE_DIR, else ~/.cache/bxftools) and later processes load it in
  # milliseconds; `cache_dir: nil` compiles in every process. The file name carries a digest of the
  # module and of the wasmtime build, so a new module or gem version compiles again. wasmtime trusts
  # these files: the directory must be writable only by your application.
  #
  # The first document of an instance costs ~0.35 s more than the rest (~25 ms for a usual
  # invoice), so render a batch with one instance. WebAssembly memory only grows, so an instance
  # keeps the memory of the largest document it rendered (~250 MB after 3,000 conceptos, against
  # ~30 MB for a usual invoice): after a document that took it past `memory_limit` (MB) it is let
  # go and the next document starts a fresh one, and `close` (or the end of an `open` block) lets
  # go of it for good. Its memory goes back to the system.
  #
  # Without the key, or with a wrong one, Pdf.new raises Bxftools::MissingKeyError or
  # Bxftools::DecryptionError. An instance renders one document at a time and is not thread-safe:
  # use one per thread. Problems with the document raise Bxftools::Pdf::Error (the message is the
  # engine's, in Spanish). When the engine itself fails (a WebAssembly trap: a bug, or a document
  # past its limits, like XML nested thousands of levels deep) it raises Bxftools::Pdf::EngineError,
  # a Pdf::Error too, and the next document starts a fresh instance.
  class Pdf
    class Error < Bxftools::Error; end
    # The engine failed rather than rejected the document. A plain Ruby error: Wasmtime::Trap is a
    # native object that does not cross processes (DRb, Marshal), so it is not kept as the cause.
    class EngineError < Error; end

    ENCRYPTED_PATH = File.expand_path("bxfpdf.wasm.enc", __dir__)
    MEMORY_LIMIT = 128 # MB

    # A valid PDF of one blank US Letter page, what bin/bxfpdf writes in place of a document it
    # could not render. Built without the module, so it is there even without the key.
    def self.blank
      objects = [
        "<</Type/Catalog/Pages 2 0 R>>",
        "<</Type/Pages/Kids[3 0 R]/Count 1>>",
        "<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>"
      ]
      pdf = +"%PDF-1.7\n"
      offsets = objects.each_with_index.map do |object, i|
        offset = pdf.bytesize
        pdf << "#{i + 1} 0 obj\n#{object}\nendobj\n"
        offset
      end
      xref = pdf.bytesize
      # Every cross-reference entry is exactly 20 bytes, its end of line included.
      pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
      offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
      pdf << "trailer\n<</Size #{objects.size + 1}/Root 1 0 R>>\nstartxref\n#{xref}\n%%EOF\n"
      pdf.b.freeze
    end

    def self.cache_dir
      return ENV["BXFTOOLS_CACHE_DIR"] if ENV["BXFTOOLS_CACHE_DIR"]

      File.join(ENV["XDG_CACHE_HOME"] || File.join(Dir.home, ".cache"), "bxftools")
    rescue ArgumentError # no home directory
      File.join(Dir.tmpdir, "bxftools-#{Process.uid}")
    end

    # A renderer for the block's documents, closed when the block ends (even when it raises).
    # Returns what the block returns. Takes the same options as `new`.
    def self.open(**options)
      pdf = new(**options)
      yield pdf
    ensure
      pdf&.close
    end

    def initialize(cache_dir: self.class.cache_dir, key: ENV[Cipher::ENV_KEY], memory_limit: MEMORY_LIMIT)
      wasm = Cipher.decrypt(File.binread(ENCRYPTED_PATH), key)
      @engine = Wasmtime::Engine.new
      @module = load_module(wasm, cache_dir)
      @memory_limit = memory_limit * 1024 * 1024
    end

    # brand: "neocfdi" switches the bundled logo and the footer link. logo: image bytes (PNG, JPEG,
    # GIF, WebP or SVG) shown instead of the bundled logo, embedded as given (resize it first).
    def render(xml, brand: nil, logo: nil)
      call("bxfpdf_render", xml, brand, logo)
    ensure
      release_memory_past_limit
    end

    # The parsed CFDI, as the templates receive it.
    def model(xml)
      JSON.parse(call("bxfpdf_model", xml).force_encoding(Encoding::UTF_8))
    ensure
      release_memory_past_limit
    end

    # Lets go of the instance and its memory now. The renderer stays usable: the next document
    # starts a fresh instance.
    def close
      release_instance
    end

    # Bytes of WebAssembly memory the current instance holds; nil when there is none.
    def memory_size
      @instance && (@instance.export("memory").to_memory.size * 65_536)
    end

    # Version and build of the module, e.g. "0.1.0 (32acd)".
    def version
      call("bxfpdf_version").force_encoding(Encoding::UTF_8)
    end

    private

    def release_memory_past_limit
      release_instance if memory_size.to_i > @memory_limit
    end

    def release_instance
      return unless @instance

      @instance = nil
      GC.start # the instance's memory is returned once Ruby collects it
    end

    def load_module(wasm, cache_dir)
      return Wasmtime::Module.new(@engine, wasm) unless cache_dir

      key = Digest::SHA256.hexdigest(wasm + @engine.precompile_compatibility_key.to_s)[0, 16]
      path = File.join(cache_dir, "bxfpdf-#{key}.cwasm")
      unless File.exist?(path)
        FileUtils.mkdir_p(cache_dir)
        partial = "#{path}.#{Process.pid}.tmp"
        File.binwrite(partial, @engine.precompile_module(wasm))
        File.rename(partial, path) # other processes see the whole file or none
      end
      Wasmtime::Module.deserialize_file(@engine, path)
    rescue SystemCallError => e
      warn "[bxftools] cannot use #{cache_dir} for the compiled module (#{e.message}); compiling in memory"
      Wasmtime::Module.new(@engine, wasm)
    end

    # Protocol: crates/bxfpdf-wasm/src/lib.rs in wasm-pdfgen.
    def call(name, *inputs)
      instance = (@instance ||= Wasmtime::Instance.new(Wasmtime::Store.new(@engine), @module))
      memory = instance.export("memory").to_memory
      pointers = inputs.map { |bytes| write(instance, memory, bytes) }
      status = instance.invoke(name, *pointers.flatten)
      output = memory.read(unsigned(instance.invoke("bxfpdf_result_ptr")), instance.invoke("bxfpdf_result_len"))
      instance.invoke("bxfpdf_result_clear")
      pointers.each { |pointer, length| instance.invoke("bxfpdf_free", pointer, length) unless length.zero? }
      raise Error, output.force_encoding(Encoding::UTF_8) unless status.zero?

      output
    rescue Wasmtime::Trap => e # any export can trap, bxfpdf_alloc too when memory runs out
      @instance = nil # unusable after a trap
      raise EngineError, "El motor no pudo generar el PDF (#{e.message.lines.first.strip})", cause: nil
    end

    def write(instance, memory, bytes)
      return [ 0, 0 ] if bytes.nil? || bytes.empty?

      pointer = instance.invoke("bxfpdf_alloc", bytes.bytesize)
      memory.write(unsigned(pointer), bytes)
      [ pointer, bytes.bytesize ]
    end

    # i32 results come back signed; memory offsets above 2 GiB need the unsigned value.
    def unsigned(value) = value & 0xFFFF_FFFF
  end
end
