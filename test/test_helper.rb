require "dotenv/load" # BXFTOOLS_KEY decrypts the bxfpdf module
require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/bxftools"

# Bxftools::Pdf keeps the compiled WebAssembly module here between runs (compiling it takes a few
# seconds); the bxfpdf processes the tests start find it through the environment.
ENV["BXFTOOLS_CACHE_DIR"] = File.expand_path("../tmp/wasm-cache", __dir__)
