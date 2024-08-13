import os

from blockkit import Context, Divider
from slack_sdk import WebClient

from .anniversary import create_anniversary_blocks
from .weather import create_weather_blocks

SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
CHANNEL_ID = os.getenv("SLACK_CHANNEL_ID")
client = WebClient(token=SLACK_BOT_TOKEN)


def send_message():
    raw_blocks = [*create_anniversary_blocks(), *create_weather_blocks()]

    # 先頭以外にContextがあったらその前にDividerを挿入
    blocks = []
    for i, block in enumerate(raw_blocks):
        if i != 0 and isinstance(block, Context):
            blocks.append(Divider())
        blocks.append(block.build())

    if blocks:
        client.chat_postMessage(channel=CHANNEL_ID, text="today's news", blocks=blocks)


if __name__ == "__main__":
    send_message()
