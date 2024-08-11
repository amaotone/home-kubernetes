import os
from slack_sdk import WebClient
from dotenv import load_dotenv

load_dotenv()   

slack_token = os.getenv("SLACK_BOT_TOKEN")
channel_id = os.getenv("SLACK_CHANNEL_ID")
client = WebClient(token=slack_token)

client.chat_postMessage(channel=channel_id, text="Hello from Python!")
