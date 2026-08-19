FROM python:3.12-alpine AS builder

RUN apk add --no-cache gcc musl-dev postgresql-dev \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --target=/deps psycopg2-binary requests

FROM python:3.12-alpine

RUN rm -rf /usr/local/lib/python3.12/site-packages/pip* \
    /usr/local/lib/python3.12/site-packages/setuptools* \
    /usr/local/lib/python3.12/site-packages/pkg_resources \
    /usr/local/bin/pip*

COPY --from=builder /deps /deps
COPY dead_mans_switch.py /app/dead_mans_switch.py
ENV PYTHONPATH=/deps

CMD ["python", "/app/dead_mans_switch.py"]
