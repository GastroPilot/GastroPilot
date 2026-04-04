FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir asyncpg redis

COPY reset_demo.py .

CMD ["python3", "reset_demo.py"]
