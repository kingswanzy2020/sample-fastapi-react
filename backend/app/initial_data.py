#!/usr/bin/env python3

from app.db.session import get_db
from app.db.crud import create_user, get_user_by_email
from app.db.schemas import UserCreate
from app.db.session import SessionLocal

SUPERUSER_EMAIL = "admin@test.com"


def init() -> None:
    db = SessionLocal()

    # Runs on every deploy (see deploy.sh.tftpl / roles/app/tasks/deploy.yml),
    # so it must be safe to run against a database that already has the
    # superuser -- email carries a unique index, so a bare create_user() would
    # otherwise crash the second time with an IntegrityError.
    if get_user_by_email(db, SUPERUSER_EMAIL):
        print(f"Superuser {SUPERUSER_EMAIL} already exists, skipping")
        return

    print(f"Creating superuser {SUPERUSER_EMAIL}")
    create_user(
        db,
        UserCreate(
            email=SUPERUSER_EMAIL,
            password="admin",
            is_active=True,
            is_superuser=True,
        ),
    )
    print("Done")


if __name__ == "__main__":
    init()
