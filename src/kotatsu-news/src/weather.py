import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import requests
from blockkit import Context, MarkdownText, Message, Section
from blockkit.blocks import Block

OPEN_WEATHER_MAP_API_KEY = os.getenv("OPEN_WEATHER_MAP_API_KEY")
ZIP = os.getenv("OPEN_WEATHER_MAP_ZIP")


@dataclass
class Weather:
    dt: datetime
    weather_id: str
    weather_name: str
    temperature: float

    @property
    def emoji(self):
        return _get_weather_emoji(self.weather_id)

    def get_message(self):
        return f"{self.emoji} {self.temperature:.0f}"


def _get_weather_emoji(weather_id):
    """Openweathermap Weather codes and corresponding emojis
    ref: https://gist.github.com/michels/90327b8d284646a238e6
    """

    thunderstorm = "⛈"  # Code: 200's, 900, 901, 902, 905
    drizzle = "🌧️"  # Code: 300's
    rain = "☔"  # Code: 500's
    snowflake = "❄️"  # Code: 600's snowflake
    snowman = "☃️"  # Code: 600's snowman, 903, 906
    atmosphere = "🌁"  # Code: 700's foggy
    clear_sky = "☀️"  # Code: 800 clear sky
    few_clouds = "🌤️"  # Code: 801 sun behind clouds
    clouds = "☁️"  # Code: 802-803-804 clouds general
    hot = "🔥"  # Code: 904
    default_emoji = "▫"  # default emojis

    weather_id = str(weather_id)

    if weather_id.startswith("2") or weather_id in ["900", "901", "902", "905"]:
        return thunderstorm
    elif weather_id.startswith("3"):
        return drizzle
    elif weather_id.startswith("5"):
        return rain
    elif weather_id.startswith("6") or weather_id in ["903", "906"]:
        return snowflake + " " + snowman
    elif weather_id.startswith("7"):
        return atmosphere
    elif weather_id == "800":
        return clear_sky
    elif weather_id == "801":
        return few_clouds
    elif weather_id in ["802", "803", "804"]:
        return clouds
    elif weather_id == "904":
        return hot
    else:
        return default_emoji


def get_weathers() -> list[Weather]:
    url = f"https://api.openweathermap.org/data/2.5/forecast?zip={ZIP},JP&appid={OPEN_WEATHER_MAP_API_KEY}&units=metric"
    response = requests.get(url)
    data = response.json()
    weathers = data["list"][:5]
    weathers = [
        Weather(
            dt=datetime.fromtimestamp(w["dt"], tz=timezone(timedelta(hours=9))),
            weather_id=w["weather"][0]["id"],
            weather_name=w["weather"][0]["main"],
            temperature=w["main"]["temp"],
        )
        for w in weathers
    ]
    return weathers


def create_weather_blocks() -> list[Block]:
    weathers = get_weathers()
    weather_transition = " → ".join(w.get_message() for w in weathers)

    return [
        Context(elements=[MarkdownText(text="🌤️ 天気予報")]),
        Section(text=MarkdownText(text=weather_transition)),
    ]


if __name__ == "__main__":
    print(create_weather_blocks())
