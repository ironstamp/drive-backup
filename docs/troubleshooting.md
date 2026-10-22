# Troubleshooting

Every run writes a log to `DriveBackup/backup_YYYYMMDD_HHMMSS.log`. Search it for `ERROR` first.

- Mac/Linux: `grep ERROR ~/DriveBackup/backup_*.log`
- Windows: `Select-String ERROR $HOME\DriveBackup\backup_*.log`

---

## Setup and running

### `"gdrive" refers to a local folder … directory not found`
You left the colon off. Use `gdrive:` (with a colon) to mean the Google Drive connection.

### `didn't find section in config file`
The connection has a different name. `rclone listremotes` shows what it's called; use that name, or set `REMOTE` / `$Remote` at the top of the script to match.

### `rclone` or `python` isn't recognised / command not found
1. **Close the terminal and open a new one.** A terminal that was open before you installed something can't see it.
2. Windows: try `py` instead of `python` (e.g. `py classroom_archive.py …`).
3. Windows: if `python` opens the Microsoft Store, go to **Settings → Apps → Advanced app settings → App execution aliases** and turn off the two "python" entries.
4. Windows: reinstall Python with **"Add python.exe to PATH"** ticked.
5. Mac: the command is `python3`, not `python`.

### The script can't find `shared_items.txt` or `excludes.txt`, or "No such file"
Your terminal isn't in the scripts folder. See the README, [step 5](../README.md#5-run-the-backup), for opening a terminal in the right place. Then `dir` (Windows) / `ls` (Mac) should list the scripts.

### Windows: "running scripts is disabled on this system"
Run it with `powershell -ExecutionPolicy Bypass -File .\backup_drive.ps1` as shown in the README.

---

## Google errors

### `Quota exceeded … RATE_LIMIT_EXCEEDED` (mentioning `project_number:202264815644`)
That's rclone's **shared** client ID, overloaded by other users. Set up your own: [google-cloud-setup.md](google-cloud-setup.md). As a stopgap, adding `--tpslimit 2` to an rclone command may help.

### `This remote uses rclone's shared Google Drive client_id, which is being retired`
Same fix: [create your own client ID](google-cloud-setup.md).

### `invalid_grant`, `Token has been expired or revoked`, or "token expired"
Your sign-in has lapsed. This usually happens after 7 days with a Cloud app in Testing mode. Run:

```
rclone config reconnect gdrive:
```

then run the backup again. To stop it recurring, see [Stop the 7-day sign-in expiry](google-cloud-setup.md#7-optional-stop-the-7-day-sign-in-expiry).

### "Access blocked" / "This app is blocked" in the browser
Your organisation blocks unapproved apps. See [If sign-in is blocked](google-cloud-setup.md#if-sign-in-is-blocked).

---

## Log messages

### `Skipped copy as --dry-run is set`
Normal. A dry run lists what *would* be copied without copying it.

### `Dangling shortcut "…" detected`
Harmless. A shortcut points to a file that has been deleted or is no longer shared with you, so there's nothing to copy.

### `Duplicate object found in source - ignoring`
Google Drive allows two files with the **same name in the same folder**; your computer doesn't. rclone copies one and skips the rest. Often these are identical copies (Classroom re-posting the same attachment), but `Untitled document`-type clashes are usually different files.

Fix by renaming the duplicates in Drive (adds `-1`, `-2`, …; nothing is deleted). This needs a **read-write** connection:

1. `rclone config` → new remote `gdrive-rw`, same answers as `gdrive` (including your client ID) but **scope `1`** (full access).
2. Preview, skipping Classroom:
   ```
   rclone dedupe --dedupe-mode rename gdrive-rw: --exclude "/Classroom/**" --dry-run
   ```
3. If it looks right, run it again without `--dry-run`. Folders with the same name are merged into one.
4. Run the backup again.

**Don't** run dedupe across `Classroom` (thousands of student files) or on a **shared drive** (it would rename files your colleagues use).

### `Duplicate directory found in source`
Two folders with the same name. Their contents are merged by the dedupe step above.

---

## Odd behaviour

### Re-running copies some files again
Re-runs should only copy new or changed files. To see how many were copied again:

- Mac/Linux: `grep -c "replaced existing" ~/DriveBackup/backup_*.log`
- Windows: `(Select-String "replaced existing" $HOME\DriveBackup\backup_*.log).Count`

**A few dozen, mostly spreadsheets:** normal. Google updates the "modified" date of Sheets with live formulas (`NOW()`, `TODAY()`, `IMPORTRANGE`) and after sharing or comment changes, even without edits.

**Hundreds, or the same untouched files every time:** ask rclone why, for one of them:

```
rclone copy "gdrive:Path/To/File.pdf" "<DEST>/My Drive/Path/To" --drive-export-formats docx,xlsx,pptx,svg -vv --dry-run
```

- `Modification times differ by` *a second or two, or milliseconds*: usually a FAT32/exFAT thumb drive storing times less precisely. Add `--modify-window 2s` to the `COMMON` options in the script.
- `Modification times differ by` *hours or days*: the file really changed in Drive.
- `Sizes differ`: changed, or a duplicate-name clash (see above).

### The backup is in the wrong place after switching to a thumb drive
On a Mac, if the drive isn't mounted when you run the script, it creates an ordinary folder under `/Volumes` and fills your internal disk. Plug the drive in first. Delete the stray folder in `/Volumes` if one was created.

### Will links in Classroom/Drive break if I reorganise my Drive?
No, as long as you **move** files (drag-and-drop or **Move**) rather than copy them. Drive keeps a file's ID when it's moved or renamed. Links break if you copy and delete the original, or delete the file.
