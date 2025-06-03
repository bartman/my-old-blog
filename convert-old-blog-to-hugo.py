#!/usr/bin/env python3

import os
import sys
import glob
from datetime import datetime
import pytz

def parse_header(lines):
    headers = {}
    body_start = 0
    for i, line in enumerate(lines):
        if not line.strip():
            body_start = i + 1
            break
        if ":" in line:
            key, val = line.split(":", 1)
            headers[key.strip()] = val.strip()
    return headers, lines[body_start:]

def sanitize_filename(name):
    return "-".join(name.strip().lower().split())

def convert_timestamp(ts):
    dt = datetime.strptime(ts, "%Y%m%d%H%M%S")
    local_dt = dt.astimezone()  # use system local timezone
    return local_dt.isoformat()

def write_output(filename, headers, body, iso_date):
    alias = headers.get("Alias", "").strip()
    subject = headers.get("Subject", "").strip()
    tags = [tag.strip() for tag in headers.get("Tags", "").split(",") if tag.strip()]
    if alias:
        outname = f"{alias}.md"
    else:
        outname = f"{sanitize_filename(subject)}.md"

    if os.path.exists(outname):
        print(f"Note: Output file {outname} already exists. Skipping.")
        return

    body = [line.replace("<read-more>", "<!--more-->") for line in body]

    front_matter = [
        "+++",
        f'title = "{subject}"',
        f'date = "{iso_date}"',
        'author = "bartman"',
        'authorTwitter = "barttrojanowski"',
        'cover = ""',
        f'tags = {tags}',
        f'keywords = {tags}',
        'description = ""',
        'showFullContent = false',
        'readingTime = false',
        'hideComments = false',
        "+++",
        ""
    ]

    with open(outname, "w", encoding="utf-8") as f:
        f.write("\n".join(front_matter + body))

def main():
    for fname in glob.glob("[0-9]" * 14):  # matches 14-digit files like 20040305155708
        print(f"Processing {fname}")
        with open(fname, encoding="utf-8") as f:
            lines = [line.rstrip('\r\n') for line in f]

        headers, body = parse_header(lines)
        iso_date = convert_timestamp(os.path.basename(fname))
        write_output(fname, headers, body, iso_date)
        print(f"Processed {fname}")

if __name__ == "__main__":
    main()

