"""align user table with orm models

Revision ID: 8f3b6c1a4d27
Revises: 91979b40eb38
Create Date: 2026-09-08 10:12:44.000000

Closes the drift between the initial revision (91979b40eb38) and
app/db/models.py. The ORM is treated as the source of truth:

  * drops the ``address`` column, which no model, schema, crud function,
    router or frontend view ever referenced;
  * widens ``email``/``first_name``/``last_name``/``hashed_password`` from
    VARCHAR(50)/VARCHAR(100) to unbounded VARCHAR;
  * adds the unique index on ``email`` and the plain index on ``id`` that
    ``Column(..., unique=True, index=True)`` implies;
  * adds server defaults to ``is_active``/``is_superuser`` so raw-SQL
    inserts (seed scripts, psql, data fixes) do not violate NOT NULL. The
    Python-side defaults on the model stay as they are.

DUPLICATE EMAILS: ``sign_up_new_user`` in app/core/auth.py does a
non-atomic check-then-insert, so a live database may already hold
duplicate addresses that make ``CREATE UNIQUE INDEX`` fail. Rather than
surfacing that as a bare Postgres error inside a migration Job, this
revision checks first and aborts with the offending addresses listed. To
pre-check by hand before deploying::

    SELECT email, COUNT(*) FROM "user" GROUP BY email HAVING COUNT(*) > 1;

DOWNGRADE: re-narrowing the varchars fails if any stored value is longer
than the old limit, and the dropped ``address`` column comes back empty --
its data is not recoverable.
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "8f3b6c1a4d27"
down_revision = "91979b40eb38"
branch_labels = None
depends_on = None


def _abort_on_duplicate_emails():
    """
    Fail with an actionable message instead of a bare unique violation.
    """
    duplicates = (
        op.get_bind()
        .execute(
            sa.text(
                'SELECT email, COUNT(*) AS total FROM "user" '
                "GROUP BY email HAVING COUNT(*) > 1 ORDER BY email"
            )
        )
        .fetchall()
    )

    if duplicates:
        listed = ", ".join(
            "{} (x{})".format(row[0], row[1]) for row in duplicates
        )
        raise RuntimeError(
            "Cannot create the unique index on user.email: the table "
            "already contains duplicate addresses: {}. Merge or delete "
            "the extra rows, then re-run 'alembic upgrade head'.".format(listed)
        )


def upgrade():
    _abort_on_duplicate_emails()

    op.drop_column("user", "address")

    op.alter_column(
        "user",
        "email",
        existing_type=sa.String(50),
        type_=sa.String(),
        existing_nullable=False,
    )
    op.alter_column(
        "user",
        "first_name",
        existing_type=sa.String(100),
        type_=sa.String(),
        existing_nullable=True,
    )
    op.alter_column(
        "user",
        "last_name",
        existing_type=sa.String(100),
        type_=sa.String(),
        existing_nullable=True,
    )
    op.alter_column(
        "user",
        "hashed_password",
        existing_type=sa.String(100),
        type_=sa.String(),
        existing_nullable=False,
    )

    op.alter_column(
        "user",
        "is_active",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=sa.true(),
    )
    op.alter_column(
        "user",
        "is_superuser",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=sa.false(),
    )

    op.create_index("ix_user_email", "user", ["email"], unique=True)
    op.create_index("ix_user_id", "user", ["id"], unique=False)


def downgrade():
    op.drop_index("ix_user_id", table_name="user")
    op.drop_index("ix_user_email", table_name="user")

    op.alter_column(
        "user",
        "is_superuser",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=None,
    )
    op.alter_column(
        "user",
        "is_active",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=None,
    )

    op.alter_column(
        "user",
        "hashed_password",
        existing_type=sa.String(),
        type_=sa.String(100),
        existing_nullable=False,
    )
    op.alter_column(
        "user",
        "last_name",
        existing_type=sa.String(),
        type_=sa.String(100),
        existing_nullable=True,
    )
    op.alter_column(
        "user",
        "first_name",
        existing_type=sa.String(),
        type_=sa.String(100),
        existing_nullable=True,
    )
    op.alter_column(
        "user",
        "email",
        existing_type=sa.String(),
        type_=sa.String(50),
        existing_nullable=False,
    )

    op.add_column("user", sa.Column("address", sa.String(100), nullable=True))
