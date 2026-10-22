# Drive Backup

Back up a Google Drive to your own computer (or a thumb drive) as ordinary files you can open without Google.

- **Google Docs → Word (.docx), Sheets → Excel (.xlsx), Slides → PowerPoint (.pptx), Drawings → .svg.** PDFs, images and other files are copied as they are.
- **All of My Drive**, keeping the folder structure. You can skip folders you don't want, such as `Classroom`.
- **Selected folders or files from shared drives**, listed in a simple text file.
- **Safe to re-run.** Only new or changed files are downloaded, and nothing on your computer is ever deleted.
- **Read-only access to Drive.** The backup can't change anything in your Drive.

There's also **`classroom_archive.py`**, which turns a Google Classroom course export (from the [Classroom Manager](https://github.com/ironstamp/classroom-tool) tool) into a folder of real files that can rebuild the course on another account. See [docs/classroom-archive.md](docs/classroom-archive.md).

Everything runs on [rclone](https://rclone.org), a free, widely used command-line tool for cloud storage.

---

## Quick start

If this is your first time, work through the steps in order. Steps 1–3 only need to be done once.

| Step | What | Guide |
|---|---|---|
| 1 | Install rclone (and Python, if you want the Classroom archive) | [below](#1-install-rclone) |
| 2 | Create your own Google Cloud "app" so rclone can sign in | [docs/google-cloud-setup.md](docs/google-cloud-setup.md) |
| 3 | Connect rclone to your Google account | [below](#3-connect-rclone-to-google-drive) |
| 4 | Choose what to skip and which shared-drive items to include | [below](#4-choose-what-to-back-up) |
| 5 | Run a dry run, then the real backup | [below](#5-run-the-backup) |

Something not working? See [docs/troubleshooting.md](docs/troubleshooting.md).

---

### 1. Install rclone

| Computer | Command |
|---|---|
| Windows | `winget install Rclone.Rclone` |
| Mac | `brew install rclone` (needs [Homebrew](https://brew.sh)) |
| Linux | `sudo -v ; curl https://rclone.org/install.sh \| sudo bash` |

**Close the terminal and open a new one** afterwards, or it won't find `rclone`. Check it with `rclone version`.

For the Classroom archive script you also need Python 3. On Windows use `winget install Python.Python.3.12` (or python.org, ticking **"Add python.exe to PATH"**). Macs normally have `python3` already.

### 2. Create a Google Cloud client ID

rclone needs to identify itself to Google. Its built-in shared identity is being retired during 2026 and is often overloaded ("Quota exceeded" errors), so you create your own. It's free, takes about 10 minutes, and involves no code. **Follow [docs/google-cloud-setup.md](docs/google-cloud-setup.md)**, then come back here with your **client ID** and **client secret**.

### 3. Connect rclone to Google Drive

Run `rclone config` and answer:

| Prompt | Answer |
|---|---|
| New remote | `n` |
| name | `gdrive` |
| Storage | `drive` (Google Drive) |
| client_id | paste your client ID |
| client_secret | paste your client secret |
| scope | `2` (read-only: the backup can't change your Drive) |
| service_account_file | leave blank |
| Edit advanced config | `n` |
| Use web browser to authenticate | `y`, then sign in with the Google account you're backing up |
| Configure this as a Shared Drive | `n` (the script handles shared drives itself) |
| Keep this remote | `y` |

If Google warns that the app is unverified, click **Advanced → Go to … (unsafe)**. It's your own app, so that's expected.

Check it works:

```
rclone lsd gdrive:
```

You should see your top-level folders. **Don't forget the colon** — without it, rclone looks for a local folder called `gdrive`.

> **Sign-in expires after 7 days** while your Cloud app is in "Testing" mode. If a run fails with `invalid_grant` or "token expired", run `rclone config reconnect gdrive:` and sign in again. To stop this, publish the app — see [docs/google-cloud-setup.md](docs/google-cloud-setup.md#7-optional-stop-the-7-day-sign-in-expiry).

### 4. Choose what to back up

Keep these files in the same folder as the scripts.

**`excludes.txt`** lists folders in My Drive to skip. It skips `Classroom` by default, because Classroom folders are full of student submissions, duplicates and other teachers' classes. One rclone filter pattern per line:

```
/Classroom/**
/Old Stuff/**
```

**`shared_items.txt`** lists shared-drive items to include, one per line:

```
SharedDriveID | Label for local folder | Path inside that shared drive
```

Find your shared drives and their IDs:

```
rclone backend drives gdrive:
```

See what's inside one (and how big things are):

```
rclone lsf "gdrive,team_drive=THE_ID:" --dirs-only
rclone lsf "gdrive,team_drive=THE_ID:Some Folder" --drive-export-formats docx,xlsx,pptx,svg
rclone ncdu "gdrive,team_drive=THE_ID:"
```

`ncdu` is an interactive size browser: arrow keys and Enter to move around, `q` to quit. Google Docs/Sheets/Slides show as 0 bytes or "unknown size" until they're exported, so totals are slight underestimates.

Examples:

```
0AbCdEfGhIjKlUk9PVA | Maths Department | Year 12/Calculus
0AbCdEfGhIjKlUk9PVA | Maths Department | Assessments/2026/L2 Internal.docx
0AbCdEfGhIjKlUk9PVA | Maths Department |
mydrive             | Classroom        | Classroom/MATHS Y12 Calculus 2026
```

- Leave the path empty to copy a whole shared drive.
- A Google Doc must be written **with its converted extension**, e.g. `Unit Plan.docx`.
- Use `mydrive` as the ID to bring back one folder from your own Drive that `excludes.txt` skips (such as a single Classroom class).

### 5. Run the backup

Open a terminal **in the scripts folder**:

- **Windows 11:** right-click inside the folder in File Explorer → **Open in Terminal**. (Or copy the folder path from the address bar and type `cd "` + paste + `"`.)
- **Mac:** type `cd ` (with a space), drag the folder onto the Terminal window, press Enter.

Type `dir` (Windows) or `ls` (Mac) and check you can see `backup_drive.ps1` / `backup_drive.sh`.

**Always do a dry run first.** It lists what would be copied without copying anything:

| | Windows (PowerShell) | Mac / Linux |
|---|---|---|
| Dry run | `powershell -ExecutionPolicy Bypass -File .\backup_drive.ps1 -DryRun` | `./backup_drive.sh --dry-run` |
| Real run | `powershell -ExecutionPolicy Bypass -File .\backup_drive.ps1` | `./backup_drive.sh` |
| Shared items only | add `-SharedOnly` | add `--shared-only` |

(On Mac/Linux, run `chmod +x backup_drive.sh` once first.)

In the dry-run log, lines saying `Skipped copy as --dry-run is set` are fine. Look for lines containing **`ERROR`** and **`Duplicate`** (see [Duplicate names](docs/troubleshooting.md#duplicate-object-found-in-source---ignoring)).

The backup goes to **`DriveBackup`** in your home folder:

```
DriveBackup/
├── My Drive/                     everything in My Drive (minus excludes.txt)
├── Shared drives/
│   └── <Label>/<path>/           what you listed in shared_items.txt
└── backup_YYYYMMDD_HHMMSS.log    one log per run
```

If a run is interrupted, just run it again: it carries on where it stopped. Keep the computer awake while it runs.

### Backing up to a thumb drive

Change the destination line near the top of the script:

- Mac: `DEST="/Volumes/THUMBDRIVE/DriveBackup"` (the drive's name as shown in Finder)
- Windows: `$Dest = "E:\DriveBackup"` (the drive's letter)

Tips:

- **Format the drive as exFAT.** Most thumb drives come as FAT32, which can't hold files over 4 GB. Reformatting erases the drive.
- **Copy your existing `DriveBackup` folder across first**, then point the script at it. Future runs only top up what's changed.
- **Plug the drive in before running.** On a Mac, if it isn't mounted the backup quietly goes to your internal disk instead.

---

## What doesn't come across

- **Google Forms, Sites, Apps Script, Jamboards** have no Office equivalent and are skipped (they're named in the log). Export Form responses to a Sheet first if you want them.
- **Comments, suggested edits and version history.**
- **"Shared with me" files** that aren't in a shared drive, and shortcuts. Make a copy into My Drive first if you want them.
- **Two files with exactly the same name in the same folder:** only one is copied. See [Duplicate names](docs/troubleshooting.md#duplicate-object-found-in-source---ignoring).

## Files in this repo

| File | What it is |
|---|---|
| `backup_drive.sh` | Backup script for Mac / Linux |
| `backup_drive.ps1` | Backup script for Windows (PowerShell) |
| `excludes.txt` | Folders in My Drive to skip |
| `shared_items.txt` | Shared-drive (and `mydrive`) items to include |
| `classroom_archive.py` | Download a Classroom course's attachments into a reusable archive |
| `docs/google-cloud-setup.md` | Creating your own Google Cloud client ID |
| `docs/classroom-archive.md` | Using the Classroom archive script |
| `docs/troubleshooting.md` | Errors and odd behaviour, and what to do |
