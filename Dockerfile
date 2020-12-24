FROM python:3.8.7-alpine3.12

COPY requirements.txt /app/requirements.txt

# Configure server
# RUN pip install --upgrade pip
# COPY ./requirements.txt /requirements.txt
# RUN apk add --update --no-cache postgresql-client jpeg-dev
# RUN apk add --update --no-cache --virtual .tmp-build-deps \
#   gcc libc-dev linux-headers postgresql-dev musl-dev zlib zlib-dev
# RUN pip install -r /requirements.txt
# RUN apk del .tmp-build-deps

RUN set -ex \
  && pip install --upgrade pip \
  && apk add --update --no-cache postgresql-libs \
  && apk add --update --no-cache --virtual .tmp-build-deps \
  gcc musl-dev postgresql-dev \
  && pip install --no-cache-dir -r /app/requirements.txt \
  && apk --purge del .tmp-build-deps

# Working directory
WORKDIR /app

COPY . .

CMD gunicorn core.wsgi:application --bind 0.0.0.0:$PORT