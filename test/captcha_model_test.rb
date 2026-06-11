require_relative "test_helper"

class CaptchaModelTest < Minitest::Test
  def test_onnx_path_points_to_bundled_model
    path = Bxftools::CaptchaModel.onnx_path

    assert_equal "model.onnx", File.basename(path)
    assert_equal "captcha", File.basename(File.dirname(path))
    assert File.exist?(path), "model.onnx should be bundled with the gem"
    assert File.size(path).positive?, "model.onnx should not be empty"
  end

  def test_configs_path_points_to_bundled_yaml
    path = Bxftools::CaptchaModel.configs_path

    assert_equal "configs.yaml", File.basename(path)
    assert_equal "captcha", File.basename(File.dirname(path))
    assert File.exist?(path), "configs.yaml should be bundled with the gem"
  end

  def test_configs_parses_the_full_yaml
    assert_equal({
      "batch_size" => 64,
      "height" => 60,
      "learning_rate" => 0.001,
      "max_text_length" => 6,
      "model_path" => "model",
      "train_epochs" => 1000,
      "train_workers" => 20,
      "vocab" => "Y65WRD98SMBG3NJ21CP4KF7ZXHVTQL",
      "width" => 160
    }, Bxftools::CaptchaModel.configs)
  end

  def test_vocab_returns_the_character_set
    assert_equal "Y65WRD98SMBG3NJ21CP4KF7ZXHVTQL", Bxftools::CaptchaModel.vocab
  end
end
