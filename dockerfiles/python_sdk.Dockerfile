FROM python:3.12-slim-bookworm
COPY --from=docker.io/astral/uv:latest /uv /uvx /bin/

ENV PDM_BUILD_SCM_VERSION=0.1.0

WORKDIR /app

RUN apt update && apt install

COPY . .

RUN uv sync --all-extras
RUN uv run generate_proto.py

EXPOSE 8544

CMD [ "uv", "run", "-m", "tck" ]
