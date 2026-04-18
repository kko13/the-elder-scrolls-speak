from ingestion.matcher import best_matches, normalise


def test_normalise_strips_volume_markers():
    assert normalise("The Real Barenziah, Book III") == "the real barenziah 3"


def test_normalise_v_prefix_is_volume_not_roman():
    # Imperial Library uses "v 1" / "v1" for volume; not the roman numeral 5.
    assert normalise("A Dance in Fire, v 1") == "a dance in fire 1"
    assert normalise("A Dance in Fire, v1") == "a dance in fire 1"


def test_match_high_score():
    il = ["The Real Barenziah, v 1"]
    uesp = ["The Real Barenziah, Book I", "Lusty Argonian Maid"]
    matches = best_matches(il, uesp)
    assert matches[0].uesp_title == "The Real Barenziah, Book I"
    assert matches[0].score >= 90


def test_match_no_candidate():
    matches = best_matches(["A Wholly Unique Book"], ["Something Else Entirely"])
    assert matches[0].uesp_title is None
