# Archiving a Google Classroom course

`classroom_archive.py` takes a course export from the [Classroom Manager](https://github.com/ironstamp/classroom-tool) tool and downloads every attachment into a folder that can rebuild the course later, on any Google account, without the original Drive files.

It uses the same rclone setup as the backup, so complete [README steps 1–3](../README.md#quick-start) first. You also need Python 3.

## What it produces

```
ClassroomArchive/
└── 12 MATHS L2 Statistics 2026/
    ├── course_local.csv   the course: topics, posts, descriptions, dates, with links pointing to files/
    ├── manifest.csv       every link and what happened to it (OK / FAILED / LINK / FORM)
    └── files/
        └── <Topic>/<Post title>/
            ├── <attachments>          Docs → .docx, Sheets → .xlsx, Slides → .pptx, PDFs as-is
            ├── _description.txt       the post's instructions
            └── LINKS.txt              any web links (YouTube, Education Perfect, Kahoot…)
```

The course folder is self-contained: copy it anywhere (thumb drive, another computer) and it still works, as long as `course_local.csv` and `files/` stay together.

## Steps

1. **Export the course.** In Classroom Manager → **Download Course**, select the class and download it. This creates a Google Sheet.
2. **Save it as CSV.** Open the Sheet → **File → Download → Comma-separated values (.csv)**. Rename it to something short without spaces, e.g. `L2Stats.csv`, and put it in the same folder as `classroom_archive.py`.
3. **Open a terminal in that folder** (see README [step 5](../README.md#5-run-the-backup)).
4. **If it's been more than a week** since you signed in: `rclone config reconnect gdrive:`
5. **Dry run** (lists what it would do, downloads nothing):
   ```
   python classroom_archive.py L2Stats.csv --dry-run
   ```
   (Mac: `python3`. Windows alternative: `py`.)
6. **Real run:**
   ```
   python classroom_archive.py L2Stats.csv
   ```
   To save somewhere else, add e.g. `--dest "E:\Classroom"` (Windows) or `--dest "/Volumes/THUMB/Classroom"` (Mac). The default is `ClassroomArchive` in your home folder.
7. **Check the summary** at the end, e.g. `OK: 92, LINK: 5`. If anything says **FAILED**, open `manifest.csv` and read the **NOTE** column. Running the command again **retries only the failures**; everything already downloaded is skipped.

Keep the computer awake while it runs. Sleep interrupts downloads, which then show as FAILED (just run it again).

## Rebuilding the course

In Classroom Manager → **Upload Course**:

1. Choose **🆕 New course** (or **➕ Add to existing course**).
2. Choose **📁 Archive folder**, then pick the **course folder itself** (the one containing `course_local.csv`), not `ClassroomArchive` above it.
3. Check the preview: number of files to upload, web links, and any missing-file warnings.
4. Click **Create Course**.

The tool uploads the files into a new Drive folder, *"<course name> - course files"* (converting Word/Excel/PowerPoint back to Google formats unless you untick that option), then creates the course with every post as a **draft with no due date**, ready to publish and date as you teach. The new class is activated so it appears in your Classroom list.

If an upload is interrupted, run it again **with the same course name**: files already in Drive are found and reused rather than uploaded twice. Don't delete the "course files" folder: the class's attachments live there.

## Limitations

- **Google Forms** can't be exported. They're listed in `manifest.csv` and `LINKS.txt`, so recreate any you need.
- **External links** (Education Perfect, Kahoot, NZQA papers, YouTube) are recorded, not downloaded. Download any public PDFs yourself if you want copies.
- **Files owned by colleagues** download only if you can still open them; otherwise they show as FAILED.
- **Student submissions** are not included.
- **YouTube attachments** only appear if the course was exported with a version of Classroom Manager from October 2026 or later.
