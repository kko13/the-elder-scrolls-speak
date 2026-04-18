from shared.slug import slugify


def test_slugify_basic():
    assert slugify("A Dance in Fire, v1") == "a-dance-in-fire-v1"


def test_slugify_unicode():
    assert slugify("Brìnnyälda's Tome") == "brinnyaldas-tome"


def test_slugify_empty():
    assert slugify("   ") == "untitled"
