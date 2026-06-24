"""Admin user CLI.

Usage:
    python manage_users.py create <username> [--role admin|user]
    python manage_users.py list
    python manage_users.py passwd <username>
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import sys

from sqlalchemy import select

from app.auth import hash_password
from app.db import SessionLocal
from app.models.user import User


async def create(username: str, role: str) -> int:
    async with SessionLocal() as session:
        existing = await session.scalar(select(User).where(User.username == username))
        if existing:
            print(f"User {username!r} already exists.")
            return 1
        pw = getpass.getpass(f"Password for {username}: ")
        if pw != getpass.getpass("Confirm password: "):
            print("Passwords do not match.")
            return 1
        session.add(
            User(username=username, password_hash=hash_password(pw), role=role)
        )
        await session.commit()
        print(f"Created {role} user {username!r}.")
        return 0


async def list_users() -> int:
    async with SessionLocal() as session:
        users = (await session.scalars(select(User).order_by(User.id))).all()
        if not users:
            print("(no users yet)")
        for u in users:
            print(f"#{u.id:<4} {u.username:<24} {u.role}")
        return 0


async def passwd(username: str) -> int:
    async with SessionLocal() as session:
        user = await session.scalar(select(User).where(User.username == username))
        if not user:
            print(f"No such user: {username!r}")
            return 1
        pw = getpass.getpass(f"New password for {username}: ")
        if pw != getpass.getpass("Confirm password: "):
            print("Passwords do not match.")
            return 1
        user.password_hash = hash_password(pw)
        user.token_version += 1  # log out existing sessions
        await session.commit()
        print(f"Password updated for {username!r}.")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="NASCinema user management")
    sub = parser.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create", help="Create a user")
    c.add_argument("username")
    c.add_argument("--role", choices=["admin", "user"], default="user")

    sub.add_parser("list", help="List users")

    p = sub.add_parser("passwd", help="Reset a user's password")
    p.add_argument("username")

    args = parser.parse_args()

    if args.cmd == "create":
        return asyncio.run(create(args.username, args.role))
    if args.cmd == "list":
        return asyncio.run(list_users())
    if args.cmd == "passwd":
        return asyncio.run(passwd(args.username))
    return 1


if __name__ == "__main__":
    sys.exit(main())
