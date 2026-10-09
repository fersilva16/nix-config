import argparse
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import NoReturn

# Loopback only, on purpose: the whole point is that the text never leaves
# this machine, so OLLAMA_HOST is deliberately not honored.
URL = "http://127.0.0.1:11434/api/chat"
MODEL = "gemma4:12b"
# Per request. Small chunks keep each one far inside the context window and
# give the model less text in which to miss an identifier.
CHUNK_CHARS = 3000

PROMPT = """\
You are a clinical text de-identification tool. The user message is a clinical text. Output the same text with every piece of protected health information replaced by a bracketed tag. Change nothing else.

Replace with these tags:
- Person names (patients, relatives, doctors, staff): [NAME]
- Dates tied to a person (birth, admission, discharge, visits, procedures): [DATE]
- Ages over 89: [AGE]
- Street addresses, cities, postal codes, other locations below country level: [LOCATION]
- Phone and fax numbers: [PHONE]
- Email addresses: [EMAIL]
- National IDs, passport, insurance, medical record, account, license, device or other ID numbers: [ID]
- Hospitals, clinics, companies, schools: [ORGANIZATION]
- URLs and IP addresses: [URL]

Rules:
- Keep all clinical content exactly as written: symptoms, diagnoses, drugs, doses, lab values, vital signs, durations ("3 days ago"), and ages 89 or under.
- Keep the original language, wording, punctuation and line breaks.
- When unsure whether something identifies a person, replace it.
- Output only the de-identified text. No preamble, no notes, no explanation.
"""


def die(msg) -> NoReturn:
    print(f"anonymize: {msg}", file=sys.stderr)
    sys.exit(1)


def split_chunks(text):
    """Cut at blank lines once a chunk reaches CHUNK_CHARS (hard cut at 2x)."""
    chunks, cur = [], ""
    for line in text.splitlines(keepends=True):
        if cur and len(cur) >= CHUNK_CHARS and (not line.strip() or len(cur) >= 2 * CHUNK_CHARS):
            chunks.append(cur)
            cur = ""
        cur += line
    if cur:
        chunks.append(cur)
    return chunks


def stream_chunk(body):
    req = urllib.request.Request(
        URL,
        data=json.dumps({
            "model": MODEL,
            "stream": True,
            "think": False,
            "messages": [
                {"role": "system", "content": PROMPT},
                {"role": "user", "content": body},
            ],
            "options": {"temperature": 0, "num_ctx": 8192},
        }).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        resp = urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        err = json.loads(e.read() or b"{}").get("error", str(e))
        if e.code == 404:
            die(f"{err}\n  fix: ollama pull {MODEL}")
        die(err)
    except urllib.error.URLError as e:
        die(f"no ollama server on 127.0.0.1:11434 ({e.reason})\n  fix: ollama serve")
    with resp:
        for line in resp:
            msg = json.loads(line)
            if "error" in msg:
                die(msg["error"])
            yield msg.get("message", {}).get("content", "")


class Progress:
    def __init__(self, name, total, n_chunks):
        self.name, self.total, self.n = name, max(total, 1), n_chunks
        self.tty = sys.stderr.isatty()

    def draw(self, done, chunk):
        if not self.tty:
            return
        frac = min(done / self.total, 1.0)
        bar = "#" * int(frac * 30)
        sys.stderr.write(f"\r{self.name} [{bar:<30}] {frac:4.0%}  chunk {chunk}/{self.n} ")
        sys.stderr.flush()

    def finish(self):
        if self.tty:
            sys.stderr.write("\n")


def anonymize_texts(texts, name):
    chunked = [split_chunks(t) for t in texts]
    bar = Progress(name, sum(map(len, texts)), sum(map(len, chunked)))
    results, done, i = [], 0, 0
    for chunks in chunked:
        out = []
        for chunk in chunks:
            i += 1
            size = len(chunk)
            body = chunk.strip()
            if body:
                lead = chunk[: len(chunk) - len(chunk.lstrip())]
                trail = chunk[len(chunk.rstrip()):]
                got = ""
                for piece in stream_chunk(body):
                    got += piece
                    bar.draw(done + min(len(got), size), i)
                chunk = lead + got.strip() + trail
            out.append(chunk)
            done += size
            bar.draw(done, i)
        results.append("".join(out))
    bar.finish()
    return results


def anonymize_json(text, name, field):
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        die(f"{name}: invalid JSON ({e})")
    *parents, key = field.split(".")
    records = data if isinstance(data, list) else [data]
    holders = []
    for n, obj in enumerate(records):
        for k in parents:
            obj = obj.get(k) if isinstance(obj, dict) else None
        if not isinstance(obj, dict) or not isinstance(obj.get(key), str):
            where = f"{name} record {n}" if isinstance(data, list) else name
            die(f"{where}: no string at {field}")
        holders.append(obj)
    for obj, t in zip(holders, anonymize_texts([h[key] for h in holders], name)):
        obj[key] = t
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def main():
    p = argparse.ArgumentParser(
        prog="anonymize",
        description="De-identify a clinical text file with a local ollama model.",
        epilog="OUTPUT defaults to INPUT with .anon before the extension "
        "(note.txt -> note.anon.txt). OUTPUT may be INPUT itself to rewrite it "
        "in place; it is replaced only after every chunk has succeeded.",
    )
    p.add_argument("input", type=Path, metavar="INPUT")
    p.add_argument("output", type=Path, nargs="?", metavar="OUTPUT")
    p.add_argument(
        "--field",
        metavar="PATH",
        help="treat INPUT as JSON and anonymize only the string at this dotted "
        "path (e.g. note.text), in the top-level object or in each "
        "object of a top-level array; everything else is kept as is",
    )
    args = p.parse_args()
    src = args.input
    dst = args.output or src.with_name(f"{src.stem}.anon{src.suffix}")
    try:
        text = src.read_text()
    except OSError as e:
        die(e)

    if args.field:
        result = anonymize_json(text, src.name, args.field)
    elif src.suffix.lower() == ".json":
        die(f"{src.name}: anonymizing raw JSON would mangle it; pass --field PATH")
    else:
        result = anonymize_texts([text], src.name)[0]

    fd, tmp = tempfile.mkstemp(dir=dst.resolve().parent, prefix=f".{dst.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(result)
        os.replace(tmp, dst)
    except BaseException:
        os.unlink(tmp)
        raise
    print(f"wrote {dst}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
