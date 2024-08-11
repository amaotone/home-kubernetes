import os
from datetime import datetime

from blockkit import Context, MarkdownText, Section
from blockkit.blocks import Block
from dateutil.relativedelta import relativedelta


def get_anniversary_duration(anniversary: datetime) -> str | None:
    anniversary_dt = datetime.strptime(anniversary, "%Y-%m-%d")
    today = datetime.now()
    delta = relativedelta(today, anniversary_dt)

    if delta.days != 0 or not (delta.years > 0 or delta.months > 0):
        return None

    y = f"{delta.years}年" if delta.years > 0 else ""
    m = f"{delta.months}ヶ月" if delta.months > 0 else ""
    return y + m


def create_anniversary_blocks() -> list[Block]:
    anniversary = os.environ["ANNIVERSARY_DATE"]
    duration = get_anniversary_duration(anniversary)
    if duration is None:
        return []

    return [
        Context(elements=[MarkdownText(text=":tada: 記念日")]),
        Section(text=MarkdownText(text=f"今日は付き合い始めて{duration}です！")),
    ]
