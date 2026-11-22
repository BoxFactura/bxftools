require "dotenv/load"
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

namespace :unar do
  desc "Rebuild the bundled unar payload from Ubuntu 24.04 (requires Docker)"
  task :build do
    sh File.expand_path("script/build_unar.sh", __dir__)
  end
end

namespace :pdf do
  desc "Encrypt a bxfpdf.wasm (from wasm-pdfgen) with BXFTOOLS_KEY into lib/bxftools/bxfpdf.wasm.enc"
  task :import, [ :wasm ] do |_, args|
    require_relative "lib/bxftools"
    abort 'Usage: rake "pdf:import[path/to/bxfpdf.wasm]"' unless args[:wasm]

    encrypted = Bxftools::Cipher.encrypt(File.binread(args[:wasm]), ENV[Bxftools::Cipher::ENV_KEY])
    File.binwrite(Bxftools::Pdf::ENCRYPTED_PATH, encrypted)
    puts "#{args[:wasm]} -> #{Bxftools::Pdf::ENCRYPTED_PATH}"
  rescue Bxftools::Error => e
    abort e.message
  end
end

namespace :key do
  desc "Generate a new BXFTOOLS_KEY (re-import the module with it, and set it where the gem runs)"
  task :generate do
    require "securerandom"
    puts SecureRandom.hex(32)
  end
end
