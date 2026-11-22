require_relative "test_helper"

class CipherTest < Minitest::Test
  SANKARA_KEY = "5a" * 32
  KALI_KEY = "0b" * 32

  def test_decrypts_what_it_encrypted
    sealed = Bxftools::Cipher.encrypt("Fortune and glory, kid", SANKARA_KEY)

    assert_equal "Fortune and glory, kid", Bxftools::Cipher.decrypt(sealed, SANKARA_KEY)
  end

  def test_marks_what_it_encrypts_and_keeps_no_plaintext
    sealed = Bxftools::Cipher.encrypt("Fortune and glory, kid", SANKARA_KEY)

    assert_equal "BXF1", sealed.byteslice(0, 4)
    assert_equal 32 + "Fortune and glory, kid".bytesize, sealed.bytesize
    assert_equal false, sealed.include?("Fortune")
  end

  def test_refuses_a_wrong_key
    sealed = Bxftools::Cipher.encrypt("Fortune and glory, kid", SANKARA_KEY)

    error = assert_raises(Bxftools::DecryptionError) { Bxftools::Cipher.decrypt(sealed, KALI_KEY) }
    assert_equal "Wrong BXFTOOLS_KEY, or the file is corrupted", error.message
  end

  def test_refuses_a_tampered_file
    sealed = Bxftools::Cipher.encrypt("Fortune and glory, kid", SANKARA_KEY)
    sealed.setbyte(40, sealed.getbyte(40) ^ 1)

    error = assert_raises(Bxftools::DecryptionError) { Bxftools::Cipher.decrypt(sealed, SANKARA_KEY) }
    assert_equal "Wrong BXFTOOLS_KEY, or the file is corrupted", error.message
  end

  def test_refuses_data_it_did_not_encrypt
    error = assert_raises(Bxftools::DecryptionError) { Bxftools::Cipher.decrypt("\0asm plain module", SANKARA_KEY) }

    assert_equal "Not a file encrypted with BXFTOOLS_KEY", error.message
  end

  def test_asks_for_the_key_when_there_is_none
    error = assert_raises(Bxftools::MissingKeyError) { Bxftools::Cipher.decrypt("BXF1", nil) }

    assert_equal "Set BXFTOOLS_KEY to use bxfpdf", error.message
  end

  def test_refuses_a_key_that_is_not_64_hex_characters
    error = assert_raises(Bxftools::MissingKeyError) { Bxftools::Cipher.encrypt("Fortune and glory, kid", "short-round") }

    assert_equal "BXFTOOLS_KEY must be 64 hex characters", error.message
  end
end
