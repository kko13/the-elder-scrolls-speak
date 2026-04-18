from ingestion.matcher import best_matches, normalise


def test_normalise_roman():
    assert normalise("The Real Barenziah, V") == "the real barenziah 5"


def test_match_high_score():
    il = ["The Real Barenziah, V 1"]
    uesp = ["The Real Barenziah, Book I", "Lusty Argonian Maid"]
    matches = best_matches(il, uesp)
    assert matches[0].uesp_title == "The Real Barenziah, Book I"
    assert matches[0].score >= 90


def test_match_no_candidate():
    matches = best_matches(["A Wholly Unique Book"], ["Something Else Entirely"])
    assert matches[0].uesp_title is None
