require "yaml"

module Bxftools
  # Exposes the bundled SAT captcha-solving ONNX model and its training
  # configuration so any project including this gem can load them by path.
  class CaptchaModel
    CAPTCHA_DIR = File.expand_path("../../captcha", __dir__)
    ONNX_NAME = "model.onnx"
    CONFIGS_NAME = "configs.yaml"

    class << self
      def onnx_path
        File.join(CAPTCHA_DIR, ONNX_NAME)
      end

      def configs_path
        File.join(CAPTCHA_DIR, CONFIGS_NAME)
      end

      def configs
        @configs ||= YAML.safe_load_file(configs_path)
      end

      def vocab
        configs.fetch("vocab")
      end
    end
  end
end
