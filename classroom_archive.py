#!/usr/bin/env python3
"""
classroom_archive.py - turn a Classroom-tool course export (CSV) into a local
folder of real files, so the course can be rebuilt later without Google.

For every ASSIGNMENT / MATERIAL row it:
  * downloads each Google Drive attachment with rclone (Docs -> .docx,
    Sheets -> .xlsx, Slides -> .pptx, Drawings -> .svg; PDFs etc. as-is)
  * saves the post's description as _description.txt
  * records non-Drive links (Education Perfect, NZQA, Kahoot...) in LINKS.txt
Folder layout:
  <dest>/<Course>/files/<Topic>/<Post title>/...

It also writes, in <dest>/<Course>/:
  manifest.csv      - every link: what it was, where it went, OK / FAILED / LINK
  course_local.csv  - your original CSV with Drive links swapped for the local
                      file paths (relative to the course folder)
  _state.json       - progress record, so a re-run skips finished downloads

Usage:
  python3 classroom_archive.py "12 MATHS L2 Statistics.csv"
  python3 classroom_archive.py COURSE.csv --dest "/Volumes/THUMB/Classroom"
  python3 classroom_archive.py COURSE.csv --dry-run      (list only, no downloads)

Needs rclone set up with a remote called "gdrive" (change with --remote).
"""
import argparse, csv, json, os, re, shutil, subprocess, sys
from pathlib import Path

FORMATS = "docx,xlsx,pptx,svg"
POST_TYPES = {"ASSIGNMENT", "MATERIAL", "QUESTION", "ANNOUNCEMENT"}

DRIVE_PATTERNS = [
    (re.compile(r"docs\.google\.com/forms/d/(?:e/)?([\w-]+)"), "form"),
    (re.compile(r"drive\.google\.com/drive/(?:u/\d+/)?folders/([\w-]+)"), "folder"),
    (re.compile(r"(?:docs|drive)\.google\.com/(?:file|document|spreadsheets|presentation|drawings)/d/([\w-]+)"), "file"),
    (re.compile(r"drive\.google\.com/(?:open|uc)\?(?:.*&)?id=([\w-]+)"), "file"),
]


def classify(url):
    for pat, kind in DRIVE_PATTERNS:
        m = pat.search(url)
        if m:
            return kind, m.group(1)
    return "link", None


def safe(name, limit=80):
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", name or "").strip()
    name = re.sub(r"\s+", " ", name).strip(" .")
    return (name[:limit].rstrip(" .")) or "Untitled"


def unique(path: Path) -> Path:
    if not path.exists():
        return path
    stem, suf, i = path.stem, path.suffix, 2
    while (path.with_name(f"{stem} ({i}){suf}")).exists():
        i += 1
    return path.with_name(f"{stem} ({i}){suf}")


def run_rclone(args):
    try:
        r = subprocess.run(["rclone", *args], capture_output=True, text=True)
    except FileNotFoundError:
        sys.exit("rclone not found - install it and make sure it's on your PATH.")
    msg = (r.stderr or r.stdout).strip().splitlines()
    return r.returncode == 0, (msg[-1] if msg else "")


def download_file(remote, file_id, post_dir: Path, tmp_root: Path):
    """Download one Drive file by ID into post_dir. Returns (ok, path or error)."""
    tmp = tmp_root / file_id
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    ok, msg = run_rclone(["backend", "copyid", f"{remote}:", file_id, str(tmp) + os.sep,
                          "--drive-export-formats", FORMATS])
    got = [p for p in tmp.iterdir() if p.is_file()]
    if not ok or not got:
        shutil.rmtree(tmp, ignore_errors=True)
        return False, msg or "nothing downloaded (no access, deleted, or not exportable)"
    post_dir.mkdir(parents=True, exist_ok=True)
    target = unique(post_dir / got[0].name)
    shutil.move(str(got[0]), str(target))
    shutil.rmtree(tmp, ignore_errors=True)
    return True, target


def download_folder(remote, folder_id, post_dir: Path):
    target = post_dir / f"folder-{folder_id[:8]}"
    ok, msg = run_rclone(["copy", f"{remote},root_folder_id={folder_id}:", str(target),
                          "--drive-export-formats", FORMATS])
    return (True, target) if ok else (False, msg or "folder copy failed")


def main():
    ap = argparse.ArgumentParser(description="Download a Classroom course export's Drive files.")
    ap.add_argument("csv", help="course CSV exported by the Classroom tool")
    ap.add_argument("--dest", default=str(Path.home() / "ClassroomArchive"),
                    help="where to create the course folder (default ~/ClassroomArchive)")
    ap.add_argument("--remote", default="gdrive", help="rclone remote name (default gdrive)")
    ap.add_argument("--dry-run", action="store_true", help="list what would happen, download nothing")
    a = ap.parse_args()

    with open(a.csv, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames
        rows = list(reader)
    if not fields or "LINKS" not in fields:
        sys.exit("This doesn't look like a Classroom tool export (no LINKS column).")

    course = next((r["TITLE"] for r in rows if r.get("TYPE") == "COURSE"), Path(a.csv).stem)
    base = Path(a.dest).expanduser() / safe(course, 100)
    files_root, tmp_root = base / "files", base / ".tmp"
    state_path = base / "_state.json"
    state = {}
    if state_path.exists():
        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
        except Exception:
            state = {}

    print(f"Course: {course}\nFolder: {base}\n" + ("DRY RUN - nothing will be downloaded\n" if a.dry_run else ""))
    manifest, counts = [], {"OK": 0, "SKIPPED (done before)": 0, "FAILED": 0, "LINK": 0, "FORM": 0}
    out_rows = []

    for n, row in enumerate(rows, 1):
        out = dict(row)
        out_rows.append(out)
        if row.get("TYPE") not in POST_TYPES:
            continue
        topic = safe(row.get("TOPIC") or "No topic")
        title = row.get("TITLE") or "Untitled"
        post_dir = files_root / topic / safe(title)
        links = [u.strip() for u in (row.get("LINKS") or "").split(",") if u.strip()]
        new_links, ext_links = [], []

        if not a.dry_run and (row.get("DESCRIPTION") or "").strip():
            post_dir.mkdir(parents=True, exist_ok=True)
            (post_dir / "_description.txt").write_text(row["DESCRIPTION"].strip() + "\n", encoding="utf-8")

        for url in links:
            kind, fid = classify(url)
            key = f"{n}|{url}"
            status, local, note = "", "", ""

            if kind == "link":
                status, note = "LINK", "external link - not downloadable"
                ext_links.append(url)
                new_links.append(url)
            elif kind == "form":
                status, note = "FORM", "Google Form - can't be exported; rebuild or copy manually"
                ext_links.append(url)
                new_links.append(url)
            elif key in state and (base / state[key]).exists():
                status, local = "SKIPPED (done before)", state[key]
                new_links.append(local)
            elif a.dry_run:
                status, note = "WOULD DOWNLOAD", kind
                new_links.append(url)
            else:
                print(f"  {topic} / {title[:50]} ... ", end="", flush=True)
                ok, res = (download_folder(a.remote, fid, post_dir) if kind == "folder"
                           else download_file(a.remote, fid, post_dir, tmp_root))
                if ok:
                    status, local = "OK", res.relative_to(base).as_posix()
                    state[key] = local
                    state_path.write_text(json.dumps(state, indent=1), encoding="utf-8")
                    new_links.append(local)
                    print(Path(local).name)
                else:
                    status, note = "FAILED", res
                    new_links.append(url)
                    print("FAILED")
            counts[status] = counts.get(status, 0) + 1
            manifest.append({"TOPIC": row.get("TOPIC", ""), "TYPE": row["TYPE"], "TITLE": title,
                             "ORIGINAL_LINK": url, "STATUS": status, "LOCAL_PATH": local, "NOTE": note})

        if ext_links and not a.dry_run:
            post_dir.mkdir(parents=True, exist_ok=True)
            (post_dir / "LINKS.txt").write_text("\n".join(ext_links) + "\n", encoding="utf-8")
        out["LINKS"] = ", ".join(new_links)

    if a.dry_run:
        for m in manifest:
            print(f"  [{m['STATUS']}] {m['TOPIC']} / {m['TITLE'][:45]}  {m['ORIGINAL_LINK'][:60]}")
    else:
        base.mkdir(parents=True, exist_ok=True)
        with open(base / "manifest.csv", "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=list(manifest[0].keys()) if manifest else ["STATUS"])
            w.writeheader(); w.writerows(manifest)
        with open(base / "course_local.csv", "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader(); w.writerows(out_rows)
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("\nSummary: " + ", ".join(f"{k}: {v}" for k, v in counts.items() if v))
    if not a.dry_run:
        print(f"Details in {base / 'manifest.csv'}")
    if counts.get("FAILED"):
        print("Some downloads failed - see the NOTE column in manifest.csv. Re-running retries only those.")


if __name__ == "__main__":
    main()
