import os
from celery import Celery

celery_app = Celery("worker", broker=os.environ["CELERY_BROKER_URL"])

celery_app.conf.task_routes = {"app.tasks.*": "main-queue"}
