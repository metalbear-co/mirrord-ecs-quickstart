"""A small orders API that runs as an ECS service and reads from a private RDS database."""

import os
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI
from pydantic import BaseModel

# Change these and run the service with mirrord to see your local code answer requests.
GREETING = "Hello from the orders service"
VERSION = "v1"

SEED_ITEMS = ["coffee beans", "oat milk", "croissant"]


def connect() -> psycopg.Connection:
    # DB_HOST resolves only inside the VPC. Under mirrord, the local process gets these
    # variables from the ECS task and its connection leaves from the task.
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
    )


@asynccontextmanager
async def lifespan(_: FastAPI):
    with connect() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS orders ("
            " id SERIAL PRIMARY KEY,"
            " item TEXT NOT NULL,"
            " created_at TIMESTAMPTZ NOT NULL DEFAULT now())"
        )
        if conn.execute("SELECT count(*) FROM orders").fetchone()[0] == 0:
            conn.cursor().executemany(
                "INSERT INTO orders (item) VALUES (%s)", [(i,) for i in SEED_ITEMS]
            )
    yield


app = FastAPI(lifespan=lifespan)


class NewOrder(BaseModel):
    item: str


@app.get("/")
def index():
    return {"message": GREETING, "version": VERSION}


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.get("/orders")
def list_orders():
    with connect() as conn:
        rows = conn.execute(
            "SELECT id, item, created_at FROM orders ORDER BY id"
        ).fetchall()
    return {
        "version": VERSION,
        "db_host": os.environ["DB_HOST"],
        "orders": [{"id": r[0], "item": r[1], "created_at": r[2].isoformat()} for r in rows],
    }


@app.post("/orders", status_code=201)
def create_order(order: NewOrder):
    with connect() as conn:
        row = conn.execute(
            "INSERT INTO orders (item) VALUES (%s) RETURNING id", (order.item,)
        ).fetchone()
    return {"id": row[0], "item": order.item, "version": VERSION}
