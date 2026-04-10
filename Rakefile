require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

namespace :credentials do
  desc "Generate a new encryption key (save this securely, share via BXFTOOLS_KEY env var)"
  task :generate_key do
    require "securerandom"
    key = SecureRandom.hex(32)
    puts "Generated key (64 hex chars):"
    puts key
    puts
    puts "Set this as BXFTOOLS_KEY in the host app's environment."
    puts "Keep it secret. The encrypted credentials file is useless without it."
  end

  desc "Encrypt credentials from credentials.json using BXFTOOLS_KEY"
  task :encrypt do
    require_relative "lib/bxftools"
    json_path = File.expand_path("credentials.json", __dir__)

    unless File.exist?(json_path)
      abort "Create credentials.json first with {\"binary_url\": \"...\", \"binary_name\": \"...\"}"
    end

    key = ENV["BXFTOOLS_KEY"]
    abort "Set BXFTOOLS_KEY env var" unless key

    Bxftools::Credentials.write(File.read(json_path), key)
    puts "Encrypted credentials.json -> credentials.enc"
    puts "You can now safely commit credentials.enc and delete credentials.json"
  end

  desc "Decrypt and display credentials (requires BXFTOOLS_KEY)"
  task :decrypt do
    require_relative "lib/bxftools"
    puts Bxftools::Credentials.read
  end
end
