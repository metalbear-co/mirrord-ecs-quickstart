# The mirrord remote bootstrap needs glibc 2.30 or later. Debian bookworm ships 2.36.
# Alpine (musl) images are not supported.
FROM python:3.12-slim-bookworm

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
