FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec \"$@\"", "sh"]
CMD ["python", "-m", "src.worker"]
