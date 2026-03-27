import argparse
import datetime as dt
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
from typing import List, Optional, Tuple


def pull_android_db(package_name: str, output_file: str) -> None:
    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as temp_file:
        temp_path = temp_file.name

    try:
        with open(temp_path, "wb") as stream:
            result = subprocess.run(
                [
                    "adb",
                    "exec-out",
                    "run-as",
                    package_name,
                    "cat",
                    "databases/biometric_scanner.db",
                ],
                stdout=stream,
                stderr=subprocess.PIPE,
                check=False,
            )

        if result.returncode != 0:
            stderr_text = result.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(stderr_text or "adb pull failed")

        if os.path.getsize(temp_path) == 0:
            raise RuntimeError("pulled db is empty")

        try:
            os.replace(temp_path, output_file)
        except PermissionError as exc:
            raise RuntimeError(
                f"cannot write '{output_file}' (it may be open/locked in DB Browser)"
            ) from exc
    finally:
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


def mirror_db(source_file: str, mirror_file: str) -> None:
    mirror_dir = os.path.dirname(mirror_file)
    if mirror_dir:
        os.makedirs(mirror_dir, exist_ok=True)

    with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as temp_file:
        temp_path = temp_file.name

    try:
        with open(source_file, "rb") as source, open(temp_path, "wb") as out:
            out.write(source.read())

        try:
            os.replace(temp_path, mirror_file)
        except PermissionError as exc:
            raise RuntimeError(
                f"cannot write mirror '{mirror_file}' (it may be open/locked in DB Browser)"
            ) from exc
    finally:
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


def get_table_counts(db_path: str) -> Tuple[int, List[Tuple[str, Optional[int]]]]:
    connection = sqlite3.connect(db_path)
    cursor = connection.cursor()

    user_version = cursor.execute("PRAGMA user_version").fetchone()[0]
    table_rows = cursor.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ).fetchall()

    counts: List[Tuple[str, Optional[int]]] = []
    for (table_name,) in table_rows:
        try:
            row_count = cursor.execute(f'SELECT COUNT(*) FROM "{table_name}"').fetchone()[0]
            counts.append((table_name, row_count))
        except sqlite3.DatabaseError:
            counts.append((table_name, None))

    connection.close()
    return user_version, counts


def print_snapshot(db_path: str) -> None:
    user_version, counts = get_table_counts(db_path)
    stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{stamp}] synced -> {db_path}")
    print(f"user_version={user_version}")
    print("tables:")
    for table_name, row_count in counts:
        if row_count is None:
            print(f"  - {table_name}: <unavailable>")
        else:
            print(f"  - {table_name}: {row_count}")
    print("-" * 50)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Continuously mirror Android runtime biometric_scanner.db to a local file "
            "and print row counts for all tables."
        )
    )
    parser.add_argument(
        "--package",
        default="com.example.user_attendance_scanner",
        help="Android application ID used by run-as",
    )
    parser.add_argument(
        "--output",
        default=r"C:\SQLiteDB\biometric_scanner.from_android.current.db",
        help="Local output path for mirrored db",
    )
    parser.add_argument(
        "--mirror-output",
        default=r"C:\SQLiteDB\biometric_scanner.db",
        help="Optional second local DB file to mirror to (set empty to disable)",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="Seconds between pulls",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Pull and print once, then exit",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        while True:
            try:
                pull_android_db(args.package, args.output)
                mirror_target = (args.mirror_output or "").strip()
                if mirror_target:
                    mirror_db(args.output, mirror_target)
                print_snapshot(args.output)
            except Exception as exc:  # noqa: BLE001
                stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                print(f"[{stamp}] sync failed: {exc}", file=sys.stderr)

            if args.once:
                break

            time.sleep(max(0.2, args.interval))
    except KeyboardInterrupt:
        print("Stopped.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
