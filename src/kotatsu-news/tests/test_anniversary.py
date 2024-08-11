import freezegun
import pytest

from src.anniversary import get_anniversary_duration


@pytest.mark.parametrize(
    ("today", "expected"),
    [
        ("2005-01-01", "5年"),
        ("2000-03-01", "2ヶ月"),
        ("2010-05-01", "10年4ヶ月"),
        ("2000-01-02", None),
    ],
)
def test_get_anniversary_duration(today: str, expected: str):
    anniversary = "2000-01-01"
    with freezegun.freeze_time(today):
        actual = get_anniversary_duration(anniversary)
        assert actual == expected
