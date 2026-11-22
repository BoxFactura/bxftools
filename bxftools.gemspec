Gem::Specification.new do |s|
  s.name        = "bxftools"
  s.version     = "0.1.0"
  s.summary     = "BXF Tools"
  s.description = "Tooling for BXF binary operations"
  s.authors     = [ "Rafael Soto" ]
  s.license     = "Nonstandard"

  s.required_ruby_version = ">= 3.3" # wasmtime 50

  # The bxfpdf module ships encrypted (bxfpdf.wasm.enc), never as a plain .wasm.
  s.files = Dir["lib/**/*", "bin/bxfpdf", "bin/bxfunar", "bin/bxfunar-*.tar.gz", "captcha/*", "LICENSE", "README.md"] -
            Dir["lib/**/*.wasm"]
  s.executables << "bxfpdf"
  s.executables << "bxfunar"

  s.require_paths = [ "lib" ]

  # Runs lib/bxftools/bxfpdf.wasm (CFDI → PDF, Bxftools::Pdf); precompiled gems for Linux and macOS.
  s.add_dependency "wasmtime", "~> 50.0"

  s.add_development_dependency "dotenv"
end
