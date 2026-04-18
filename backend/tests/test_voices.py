from tts.voices import DEFAULT_VOICE, LONG_FORM_VOICES, voice_for_author


def test_default_for_unknown():
    assert voice_for_author(None) == DEFAULT_VOICE
    assert voice_for_author("Unknown") == DEFAULT_VOICE
    assert voice_for_author("Anonymous") == DEFAULT_VOICE


def test_stable_per_author():
    a = voice_for_author("Vivec")
    b = voice_for_author("Vivec")
    assert a == b
    assert a in LONG_FORM_VOICES
