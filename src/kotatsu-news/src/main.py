import os

from anniversary import create_anniversary_blocks
from blockkit import Message
from slack_sdk import WebClient

SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
CHANNEL_ID = os.getenv("SLACK_CHANNEL_ID")
client = WebClient(token=SLACK_BOT_TOKEN)


def send_message():
    blocks = create_anniversary_blocks()
    if blocks:
        message = Message(blocks=blocks)
        client.chat_postMessage(channel=CHANNEL_ID, blocks=message.build())


if __name__ == "__main__":
    send_message()
