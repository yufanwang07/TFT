#!/usr/bin/env python3
"""
Trigger small, specific error repros.

Install a driver if needed:
    python3 -m pip install PyMySQL

Trigger a MySQL "server has gone away" error on localhost:
    python3 test.py mysql_gone_away

Trigger the exact TypeError text:
    python3 test.py exact_type_error

Configure with environment variables:
    MYSQL_HOST=127.0.0.1
    MYSQL_PORT=3306
    MYSQL_USER=root
    MYSQL_PASSWORD=...
    MYSQL_DATABASE=...

If nothing is listening on localhost:3306, this script starts a throwaway
Docker MySQL container bound to 127.0.0.1:3306. That disposable server uses an
oversized packet repro, which reliably raises:
    pymysql.err.OperationalError: (2006, "MySQL server has gone away ...")
"""

import os
import subprocess
import sys
import time


MYSQL_CONTAINER = "tft-mysql-gone-away"
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
MAGENTA = "\033[35m"
BLUE = "\033[34m"


def log_header(stage: str, message: str, color: str = CYAN) -> None:
    print(f"{DIM}tft-overlay{RESET} {color}{BOLD}{stage}{RESET} {message}")


def log_kv(key: str, value: object, color: str = DIM) -> None:
    if isinstance(value, str):
        rendered = f'"{value}"'
    elif isinstance(value, bool):
        rendered = str(value).lower()
    else:
        rendered = value
    print(f"  {color}- {key} = {rendered}{RESET}")


def print_pipeline_prelude() -> None:
    log_header("[vision]", "probe finished", GREEN)
    log_kv("sidebar", True)
    log_kv("OCR champion_name", "Pyke")
    log_kv("OCR cost_confidence", 0.982)
    log_kv("bench_slots_detected", 8)
    log_kv("shop_frame_hash", "a9f1:44c2:001b")
    log_header("[state]", "augmenting board snapshot", BLUE)
    log_kv("round", "2-2")
    log_kv("gold", 12)
    log_kv("level", 4)
    log_kv("traits.delta", "+1 Psionic / +1 Voyager")
    log_header("[resolver]", "candidate champion graph materialized", MAGENTA)
    log_kv("nodes", 143)
    log_kv("edges", 918)
    log_kv("top_candidate", "Pyke")
    log_kv("recommendation_cache", "cold")


def print_recovery_logs() -> None:
    log_header("[ui]", "draw aborted due to missing information", YELLOW)
    log_kv("reason", "recommended_builds missing")
    log_kv("fallback", "None")
    log_header("[telemetry]", "queued degraded-mode event", BLUE)
    log_kv("event", "recommended_build_fetch_failed")
    log_kv("retry_in_ms", 750)
    log_header("[runtime]", "application loop still alive", GREEN)
    log_kv("frame_budget_ms", 16.7)
    log_kv("next_tick", "vision_probe")
    log_header("[shutdown]", "demo pipeline stopped cleanly", DIM)


def connect_mysql():
    import pymysql

    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ.get("MYSQL_USER", "root"),
        password=os.environ.get("MYSQL_PASSWORD", ""),
        database=os.environ.get("MYSQL_DATABASE") or None,
        autocommit=True,
    )


def start_local_mysql_container() -> None:
    log_header("[db]", "probe refused; retrying", YELLOW)
    try:
        subprocess.run(
            [
                "docker",
                "run",
                "-d",
                "--rm",
                "--name",
                MYSQL_CONTAINER,
                "-e",
                "MYSQL_ROOT_PASSWORD=rootpass",
                "-e",
                "MYSQL_DATABASE=test",
                "-p",
                "127.0.0.1:3306:3306",
                "mysql:8.4",
            ],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("Docker is not installed and localhost MySQL is not running.") from exc
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or exc.stdout.strip()
        raise RuntimeError(
            "Could not start local MySQL with Docker. Start Docker Desktop, "
            f"then run this again. Docker said: {message}"
        ) from exc

    os.environ["MYSQL_HOST"] = "127.0.0.1"
    os.environ["MYSQL_PORT"] = "3306"
    os.environ["MYSQL_USER"] = "root"
    os.environ["MYSQL_PASSWORD"] = "rootpass"
    os.environ["MYSQL_DATABASE"] = "test"


def stop_local_mysql_container() -> None:
    subprocess.run(
        ["docker", "stop", MYSQL_CONTAINER],
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def wait_for_local_mysql() -> None:
    deadline = time.monotonic() + 90
    last_error = None

    while time.monotonic() < deadline:
        try:
            conn = connect_mysql()
        except Exception as exc:
            last_error = exc
            time.sleep(2)
            continue

        conn.close()
        return

    raise TimeoutError(f"Timed out waiting for local MySQL to accept connections: {last_error}")


def get_mysql_connection():
    import pymysql

    try:
        return connect_mysql(), False
    except pymysql.err.OperationalError as exc:
        host = os.environ.get("MYSQL_HOST", "127.0.0.1")
        port = int(os.environ.get("MYSQL_PORT", "3306"))
        if exc.args[0] != 2003 or host not in {"127.0.0.1", "localhost"} or port != 3306:
            raise

        start_local_mysql_container()
        wait_for_local_mysql()
        return connect_mysql(), True


def mysql_gone_away() -> None:
    print_pipeline_prelude()
    log_header("[db]", "fetching BUILD from server", CYAN)

    conn, started_container = get_mysql_connection()

    try:
        if started_container:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                log_header("[db]", "connected to server", GREEN)
                cursor.execute("SET GLOBAL max_allowed_packet = 1024")

            conn.close()
            time.sleep(1)
            conn = connect_mysql()

            log_header("[db]", "issuing BUILD query payload", CYAN)
            with conn.cursor() as cursor:
                payload = "x" * (2 * 1024 * 1024)
                cursor.execute("SELECT %s", (payload,))
                print(cursor.fetchone())
            return

        with conn.cursor() as cursor:
            cursor.execute("SELECT 1")
            log_header("[db]", "connected to localhost MySQL", GREEN)
            log_header("[db]", "setting session wait_timeout to 1 second", YELLOW)
            cursor.execute("SET SESSION wait_timeout = 1")

        log_header("[builds]", "waiting for stale connection window", CYAN)
        time.sleep(3)

        log_header("[builds]", "querying through stale connection", CYAN)
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1")
            print(cursor.fetchone())
    except Exception as exc:
        log_header("[db]", "error during BUILD fetch", RED)
        log_kv("phase", "db.query")
        log_kv("query_type", "BUILD")
        log_kv("a", "Pyke")
        log_kv("exception", f"{type(exc).__module__}.{type(exc).__name__}: {exc}", RED)
        log_kv("desc", f"{exc}", RED)
        print_recovery_logs()
    finally:
        conn.close()
        if started_container:
            stop_local_mysql_container()


def exact_type_error() -> None:
    raise TypeError("func() takes exactly 2 arguments (2 given)")


def main() -> None:
    repro = sys.argv[1] if len(sys.argv) > 1 else "mysql_gone_away"

    if repro == "mysql_gone_away":
        mysql_gone_away()
    elif repro == "exact_type_error":
        exact_type_error()
    else:
        raise SystemExit(
            f"Unknown repro {repro!r}. Use: mysql_gone_away or exact_type_error"
        )


if __name__ == "__main__":
    main()
