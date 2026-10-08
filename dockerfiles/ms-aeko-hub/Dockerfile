FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec \"$@\"", "sh"]
CMD ["uvicorn", "cmd.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
