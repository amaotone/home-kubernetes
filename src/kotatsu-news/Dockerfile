FROM python:3.12-slim

WORKDIR /app
COPY requirements.lock ./
RUN PYTHONDONTWRITEBYTECODE=1 pip install --no-cache-dir -r requirements.lock

COPY src src
CMD ["python", "-m", "src.main"]
