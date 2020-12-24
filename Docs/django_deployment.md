# Deploying Django Docker images to Heroku <!-- omit in toc -->

Created a single page django project with static files, to test and learn django deployment with docker to heroku.

<!-- omit in toc -->
## Table of contents

- [Configurable environment variables](#configurable-environment-variables)
- [Granularise the settings](#granularise-the-settings)
- [Staticfiles for Deployment](#staticfiles-for-deployment)
  - [Static file management in django](#static-file-management-in-django)
  - [Serving static files from AWS s3 bucket](#serving-static-files-from-aws-s3-bucket)
  - [Setting up django to serve static from s3](#setting-up-django-to-serve-static-from-s3)
- [Creating a deployment ready docker image](#creating-a-deployment-ready-docker-image)
- [Deploying to Heroku](#deploying-to-heroku)
  - [Instructions to deploy the app](#instructions-to-deploy-the-app)
  - [heroku basic commands](#heroku-basic-commands)
  - [Using environment variables in heroku](#using-environment-variables-in-heroku)
  - [Using the free heroku postgres addon](#using-the-free-heroku-postgres-addon)
  - [Static assets management with django and heroku](#static-assets-management-with-django-and-heroku)
  - [Using whitenoise](#using-whitenoise)
  - [collectstatic during builds](#collectstatic-during-builds)
  - [Heroku postgress connection with django](#heroku-postgress-connection-with-django)
- [Deploying the sample app](#deploying-the-sample-app)
  - [The env variables](#the-env-variables)
  - [psycopg2 dependencies](#psycopg2-dependencies)
  - [Create image and push to heroku](#create-image-and-push-to-heroku)

## Configurable environment variables

* Environment variables used to store sensitive information, their value is set outside the program in a separate `.env` file, not checked into VCS.
* Create a `.env` file in the project folder, that stores security keys and passwords.
* Move the `SECRET_KEY` and other admin configurable values to the `.env` file, and use the [`dotenv`](https://pypi.org/project/python-dotenv/), [`Django-environ`](https://django-environ.readthedocs.io/en/latest/), [`python-decouple`](https://pypi.org/project/python-decouple/)
* Here using `python-dotenv`, to retrieve the stored value use `os.environ['KEY']`
* To set environment variables in heroku, Go to your app dashboard > settings > set your env variables as Config Vars or using the CLI(mentioned below detailed).

## Granularise the settings

* Best settings practices [look here](https://djangostars.com/blog/configuring-django-settings-best-practices/) and [here](https://simpleisbetterthancomplex.com/tips/2017/07/03/django-tip-20-working-with-multiple-settings-modules.html).
* Break the settings.py into different sub files, like storage.py, credentials.py  etc

  ```sh
  |-- core(project folder)
    |-- settings
        |-- __init__.py
        |-- settings.py
        |-- storage.py
        |-- ...
    |-- .env
  ```

* In the `__init__.py`, import the py files to build a package.

  ```py
  from .settings import *
  from .storage import *
  ```

* In the `settings.py` and sub-settings, declare the base directory correctly, the settings will now look like,

  ```py
  import os
  from pathlib import Path
  from dotenv import load_dotenv

  BASE_DIR = Path(__file__).resolve().parent.parent.parent
  env_path = BASE_DIR / 'core/.env'

  TEMPLATE_DIR = BASE_DIR / 'templates'

  load_dotenv(env_path)

  SECRET_KEY = os.environ['SECRET_KEY']

  DEBUG = os.environ['DEBUG']

  ALLOWED_HOSTS = os.environ['ALLOWED_HOSTS'].split(',')

  ```

  And the storage.py looks like,

  ```py
  import os
  from pathlib import Path

  BASE_DIR = Path(__file__).resolve().parent.parent.parent

  STATIC_URL = '/static/'

  STATIC_ROOT = os.path.join(BASE_DIR, 'static')

  STATICFILES_DIRS = [
      os.path.join(BASE_DIR, 'core/static')
  ]

  MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

  MEDIA_URL = '/media/'
  ```

## Staticfiles for Deployment

* The static files(js,css, img), the development static files stored in the `STATICFILES_DIRS` specified in the settings, here it is inside the main project(`core/static`),
* But for deployment all these static files needed to be in one place, that path is defined in the `STATIC_ROOT`, in the settings, here it is `root/static`, but it can also be some remote storage like the AWS s3 buckets.
* Use the `python manage.py collectstatic`, to collect all static files, including admin static (after done all development), from the `STATICFILES_DIRS` to `STATIC_ROOT`.

### Static file management in django

* `MEDIA_ROOT` is the folder where files uploaded using a FileField will go, `STATIC_ROOT` is the folder where static files will be stored after using `manage.py collectstatic` and `STATICFILES_DIRS` is the list of folders where Django will search for additional static files aside from the `static` folder of each app installed.
* `STATIC_ROOT` is useless during development, it's only required for deployment.
While in development, `STATIC_ROOT` does nothing, even don't need to set it. Django looks for static files inside each app's directory (myProject/appName/static) and serves them automatically, done by `manage.py runserver` when `DEBUG=True`.
* When the project goes live, Most likely the dynamic content served using Django and static files will be served by Nginx. Why? Because Nginx is incredibly efficient and will reduce the workload off Django.This is where `STATIC_ROOT` needed, as Nginx doesn't know anything about the django project and doesn't know where to find static files.
* So set `STATIC_ROOT = '/some/folder/'` and tell Nginx to look for static files in `/some/folder/`. Then you run `manage.py collectstatic` and Django will copy static files from all the apps you have to `/some/folder/`.

### Serving static files from AWS s3 bucket

* Log in to the AWS account, look for s3(simple storage service)(services -> storage -> s3),
* Create a new bucket, bucket name (django-app-203), region, uncheck block all public access, need to serve the static.
* Create a new policy for the bucket, go to the "IAM" service, go to policies -> new policy, JSON for the settings look like, this policy only allows a user access only to s3,and the resource inside it(only the admin controls AWS(more secure))

  ```json
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Action": "s3:*",
              "Resource": [
                  "arn:aws:s3:::django-app-203",
                  "arn:aws:s3:::django-app-203/*"
              ]
          }
      ]
  }
  ```

  review the policy, give a name to the policy "django-static-s3".
* Create a new user then, "django-app-manager", this user only controls the django app no aws management console access, so give only Programmatic access
* Attach it to an existing policy, search and add it,
* ignore optional tags for now, then create user, this user has the credentials that allows access to s3, just record the access key and the secret key, it is used for accessing the user through s3.

### Setting up django to serve static from s3

* Install some packages that allows django to interface with s3, `pip install django-storages`(also add `storages` to settings applist), then `pip install boto3`(helps connects to external resources).

* Configure the `storage.py` in settings,

  ```py
  import os
  from pathlib import Path
  from dotenv import load_dotenv

  BASE_DIR = Path(__file__).resolve().parent.parent.parent
  env_path = BASE_DIR / 'core/.env'

  load_dotenv(env_path)

  # Boto3
  STATICFILES_STORAGE = 'storages.backends.s3boto3.S3Boto3Storage'

  # AWS
  AWS_ACCESS_KEY_ID = os.environ['AWS_ACCESS_KEY_ID']
  AWS_SECRET_ACCESS_KEY = os.environ['AWS_SECRET_ACCESS_KEY']
  AWS_STORAGE_BUCKET_NAME = os.environ['AWS_STORAGE_BUCKET_NAME']
  # Default access control (access and download-public read)
  AWS_DEFAULT_ACL = 'public-read'
  # custom domain
  AWS_S3_CUSTOM_DOMAIN = f'{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com'
  # cache control
  AWS_S3_OBJECT_PARAMETERS = {'CacheControl': 'max-age=86400'}

  # Make the folder on the bucket, to store the static files
  AWS_LOCATION = 'static'
  STATIC_URL = f'https://{AWS_S3_CUSTOM_DOMAIN}/{AWS_LOCATION}/'

  # STATIC_URL = '/static/'

  # STATIC_ROOT = os.path.join(BASE_DIR, 'static')

  STATICFILES_DIRS = [
      os.path.join(BASE_DIR, 'core/static'),
  ]

  # MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

  # MEDIA_URL = '/media/'
  ```

* Also set the environment variables accordingly,

  ```txt
  #ALLOWED_HOSTS
  AWS_ACCESS_KEY_ID=Akj;sldhpon;isd
  AWS_SECRET_ACCESS_KEY=sdsdsddsdssdsddssdsd
  AWS_STORAGE_BUCKET_NAME=django-app-203
  ```

* Then a `python manage.py collectstatic` will put all the staticfiles to s3 bucket static folder as defined.

## Creating a deployment ready docker image

---

* Install gunicorn(`pip install gunicorn`)
* To the Dockerfile, add the `RUN` commands for starting server and building the image,
* Run the image with temporary ports mapped to run it on local, to test the working through gunicorn.(The development completes here)

   ```dockerfile
   FROM python:3.8.7-alpine3.12

   COPY requirements.txt /app/requirements.txt

   RUN set -ex \
     && pip install --upgrade pip \
     && pip install --no-cache-dir -r /app/requirements.txt

   # Working directory
   WORKDIR /app

   COPY . .

   EXPOSE 8000

   CMD ["gunicorn", "--bind", ":8000", "--workers", "3", "core.wsgi:application"]
   ```

* The port 8000 cannot be exposed on a heroku image.
* Use a `.dockerignore` to avoid unwanted files from building the image.
* Build the image using `docker build -t heroku-tester:v1` .
* Test it locally with `docker run -p 8000:8000 heroku-tester:v1`.(working)
* Using a temporary solution to serve staticfiles with the [django-helper function](https://docs.djangoproject.com/en/3.1/howto/static-files/#serving-static-files-during-development)
* For best production methods refer [this](https://docs.djangoproject.com/en/3.1/howto/static-files/deployment/).

## Deploying to Heroku

* Use gunicorn to serve the app, django server only meant for development.
* Install [**heroku CLI**](https://devcenter.heroku.com/articles/heroku-cli).
* The Dockerfile needs to be modified to remove hardcoded ports, add additional commands,
* To run the gunicorn server, change the entrypoint command to `CMD gunicorn core.wsgi:application --bind 0.0.0.0:$PORT` (The `$PORT` environment variable is automatically applied by heroku, from the config vars)

### Instructions to deploy the app

* `docker-compose` and its volumes, is for local testing(Just to help with long running commands and environment variables...etc). It can be used to build images with CI/CD tools, but for heroku normal deployment build the image from Dockerfile with server starting entry-point.
* if needed to test run with django server modify the Dockerfile to run the command to put the django server up adding to the last line: `CMD python3 manage.py runserver 0.0.0.0:$PORT`,
* The staticfiles needed to be collected before building the image.

### heroku basic commands

* View the full list of [commands](https://devcenter.heroku.com/articles/heroku-cli-commands).
* Log in to heroku: `heroku login`, create an app `heroku create <name>` (if name not given a random name added)
* Check the container running locally with `heroku ps`, login to heroku container registry `heroku container:login`,
* To list all the apps `heroku apps`
* To push the created image to heroku, use `heroku container:push web`, finally to deploy the changes `heroku container:release web`

* To destroy the old app if needed `heroku apps:destroy old_app` (this will permanently and irrevocably destroy old_app)
* To view the logs `heroku logs --tail` (`heroku logs --tail -a heroku-tester-v1`)
* A `Procfile` in heroku is similar to "Dockerfile"(Used when deploying, through git), it is to explicitly declare what command should be executed to start your app.
* A `dyno` in heroku is similar to the docker container, use `heroku ps` to show all the *dyno*s running,
* And a `stack` is the heroku version of images,

### Using environment variables in heroku

* Environment variables denoted as `config vars` in heroku, heroku can store data such as encryption keys or external resource addresses in config vars. At runtime, config vars are exposed as environment variables to the application.
* To set the config var on Heroku, use `heroku config:set TIMES=2`, To fetch the env variables use `os.environ.get('TIMES',3)`(here 3 is the default.), also `os.environ["TIMES"]` can be used.
* View all the config vars that are set, use `heroku config`,

### Using the free heroku postgres addon

* Heroku Postgres add-on automatically provisioned when the app was deployed and it is free, A database is an add-on, use the addons command in the CLI, to find all addons existing, `heroku addons`
* the `heroku config` for your app will display the URL that your app is using to connect to the database, DATABASE_URL:

  ```console
  $ heroku config
  === serene-caverns-82714 Config Vars
  DATABASE_URL: postgres://qayojflkqzwdlk:c9b49b89f95625e0c1ed...
  ```

* To get more information use `heroku pg` command.
* Configure the settings to use the pg database in django then run `heroku run python manage.py migrate`, to create tables.
* Use the `heroku pg:psql`, to connect to remote database and see all the tables.

### Static assets management with django and heroku

* Heroku recommended static files settings,

  ```python
  BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

  STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
  STATIC_URL = '/static/'

  STATICFILES_DIRS = (
      os.path.join(BASE_DIR, 'static'),
  )
  ```

* Need to create the `STATIC_ROOT` folder and run the `collectstatic`, locally before deploying,(cz git doesn't adds empty folders)
* run `collectstatic` inside Dockerfile to create that directory at the build time.

### Using whitenoise

* Django does not support serving static files in production. However, the WhiteNoise project can integrate into Django application and can serve static files.
* Whitenoise [documentation](http://whitenoise.evans.io/en/stable/).
* Using [Whitenoise on django](http://whitenoise.evans.io/en/stable/django.html).
* Install whitenoise(`pip install whitenoise`), install WhiteNoise into the Django application, in settings.py‘s middleware section(at top):

  ```python
  MIDDLEWARE_CLASSES = (
    # Simplified static file serving.
    # https://warehouse.python.org/project/whitenoise/
    'whitenoise.middleware.WhiteNoiseMiddleware',
    ...
  ```

* The whitenoise's `gzip` functionality compresses the staticfiles to serve it efficiently, to add it to django,

  ```python
  STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
  ```

* The application will now serve static assets directly from Gunicorn in production. This will be perfectly adequate for most applications, but top-tier applications may want to explore using a CDN with [Django-Storages.](http://django-storages.readthedocs.org/en/latest/)

### collectstatic during builds

* When a Django application is deployed to Heroku, `$ python manage.py collectstatic --noinput` is run automatically during the build. A build will fail if the collectstatic step is not successful, the target static folder must be present.
* For debugging that use, `heroku config:set DEBUG_COLLECTSTATIC=1`
* To disable collectstatic, `heroku config:set DISABLE_COLLECTSTATIC=1`

### Heroku postgress connection with django

* Install the `dj-database-url` package using `pip`. (`pip install dj-database-url`)
* Also be sure that `psycopg2` is installed (`pip install psycopg2` or `psycopg2-binary`)
* Then add the following settings in the bottom of `settings.py`

  ```py
  import dj_database_url
  DATABASES['default'] = dj_database_url.config(conn_max_age=600, ssl_require=True)
  ```

  This will parse the values of the DATABASE_URL environment variable and covert to django supporting format with the help of the installed addon, `conn_max_age=600`, limits the connections using django's persistent connections.

* Use the official heroku postgress [documentation](https://devcenter.heroku.com/articles/heroku-postgresql#sharing-heroku-postgres-between-applications) to fetch out more.

## Deploying the sample app

### The env variables

* Remove the local environment variables (ie the `.env` file), need to set up config vars in heroku.
* To setup config vars in heroku use `heroku config:set SECRET_KEY=yoursecretkey`,
* Also the secret keys(config vars) can also be added with Heroku dashboard, click on the app, go to apps settings, from the "Config Vars" section -> "Reveal Vars" or "Add Vars" and add the SECRET_KEY there.
* No need to change the settings the `os.environ["KEY"]` can fetch the values from heroku ecosystem too.

### psycopg2 dependencies

* To use the package built from sources, use python -m pip install psycopg2. That process will require several dependencies ([documentation](http://initd.org/psycopg/docs/install.html#install-from-source))

* Also use this [stackoverflow link](https://stackoverflow.com/a/58984045/12167598).
* To build `Psycopg`, need the packages `gcc musl-dev postgresql-dev`. Also need that `pg_config` executable: while simply installing `postgresql-dev` will work, `postgresql-libs` does fine too and takes up some 12 MB less space.

### Create image and push to heroku

* Delete the old local image,
* The `Dockerfile` for heroku deployment image,
* Modified the settings remove the dotenv modules,(as env files served from heroku), added whitenoise and postgres addon

  ```Dockerfile
  FROM python:3.8.7-alpine3.12

  COPY requirements.txt /app/requirements.txt

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
  ```

* To create new application use `heroku create`,( using the old app - heroku-tester-v1)
* To push the image to the heroku container, (check login using, `heroku container:login`),

  ```shell
  heroku container:push web -a=heroku-tester-v1
  ```

  heroku will work with docker to create an image, ie ready to deploy to heroku and pushes it to the heroku container registry(*registry.heroku.com*).\
  If look at the images with `docker images`, can see a new specific image created `registry.heroku.com/heroku-tester-v1/web`.

* And finally a `release` will make it public,

  ```shell
  heroku container:release web -a heroku-tester-v1
  ```

* Check out the logs using `heroku logs`.
* Just open it on browser using, `heroku open -a=heroku-tester-v1`
