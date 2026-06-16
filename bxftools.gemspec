Gem::Specification.new do |s|
  s.name        = "bxftools"
  s.version     = "0.1.0"
  s.summary     = "BXF Tools"
  s.description = "Tooling for BXF binary operations"
  s.authors     = ["Rafael Soto"]
  s.license     = "Nonstandard"

  s.required_ruby_version = ">= 3.1"

  s.files = Dir["lib/**/*", "bin/bxfpdf", "bin/bxfunar", "bin/unar/*.gz", "captcha/*", "credentials.enc", "LICENSE", "README.md"]
  s.executables << "bxfpdf"
  s.executables << "bxfunar"

  s.require_paths = ["lib"]

  s.add_dependency "base64"

  s.add_development_dependency "dotenv"
end
