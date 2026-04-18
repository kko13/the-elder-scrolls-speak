from __future__ import annotations

import os
from functools import lru_cache
from typing import Any

import boto3


@lru_cache(maxsize=1)
def books_table():
    name = os.environ["BOOKS_TABLE"]
    return boto3.resource("dynamodb").Table(name)


def get_book(book_id: str) -> dict | None:
    resp = books_table().get_item(Key={"book_id": book_id})
    return resp.get("Item")


def put_book(item: dict) -> None:
    books_table().put_item(Item=item)


def update_book(book_id: str, attrs: dict[str, Any]) -> None:
    if not attrs:
        return
    expr_names = {f"#{k}": k for k in attrs}
    expr_values = {f":{k}": v for k, v in attrs.items()}
    set_expr = ", ".join(f"#{k} = :{k}" for k in attrs)
    books_table().update_item(
        Key={"book_id": book_id},
        UpdateExpression=f"SET {set_expr}",
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
    )
