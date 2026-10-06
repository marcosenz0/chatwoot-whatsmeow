FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg gosu && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir -r requirements.txt && useradd --uid 10001 --create-home telegram && mkdir /data && chown telegram:telegram /data
COPY bridge ./bridge
COPY entrypoint.sh /usr/local/bin/telegram-entrypoint
RUN chmod 755 /usr/local/bin/telegram-entrypoint
ENTRYPOINT ["telegram-entrypoint"]
ENV TELEGRAM_PERSONAL_DATA_DIR=/data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=4)"
CMD ["uvicorn", "bridge.app:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--no-access-log"]
