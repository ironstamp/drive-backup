# Setting up your own Google Cloud client ID

## Why this is needed

rclone is the program that does the copying, but Google requires every program that uses the Drive API to be **registered** and to identify itself with a **client ID**. Google uses that registration to show the sign-in screen ("rclone wants to access your Google Drive"), to track what the program may do, and to apply a usage limit.

By default rclone uses one client ID shared by every rclone user in the world. That shared ID:

- is often overloaded, giving errors like `Quota exceeded … RATE_LIMIT_EXCEEDED` (the error names rclone's project number, not yours), and
- is being **retired during 2026**, after which it stops working.

Creating your own registers *your copy* of rclone with Google, so it has its own (very generous) limit. Think of rclone as the car and the client ID as its registration: same car, but now it has its own plates instead of sharing one set with thousands of other drivers.

What it **doesn't** do:

- It doesn't see or store your files. They still go straight from Drive to your computer.
- The client ID and secret aren't your password. Your Google sign-in in the browser is what grants access.
- It doesn't cost anything at this scale.

Google's settings for this (testing, test users, publishing, verification) exist for developers releasing apps to the public. For an app only you use, most of it is paperwork you can skip.

---

## Steps (about 10 minutes)

Google renames these menus from time to time. If a name doesn't match exactly, look for the closest equivalent. The OAuth pages are now grouped under **Google Auth Platform** (previously **APIs & Services → OAuth consent screen**).

### 1. Choose which Google account owns the project

The project can belong to any Google account. It **doesn't** have to be the account you're backing up.

- **Personal Gmail account (recommended):** works everywhere, and the project survives if you leave a school or job. You'll add your work/school address as a test user in step 5.
- **Your work/school account:** lets you choose **Internal** in step 4, which skips test users, the unverified-app warning and the 7-day expiry. But many organisations block creating Cloud projects, and the project disappears when the account is closed.

### 2. Create a project

1. Go to <https://console.cloud.google.com> and sign in with the account from step 1. Accept the terms if asked.
2. Click the project picker at the top → **New project**.
3. Name it `rclone` (anything is fine) → **Create**, then make sure it's selected in the project picker.

### 3. Enable the Google Drive API

1. Menu ☰ → **APIs & Services → Library**.
2. Search for **Google Drive API**, open it, click **Enable**.

### 4. Configure the consent screen

1. Menu ☰ → **Google Auth Platform** (or **APIs & Services → OAuth consent screen**) → **Get started**.
2. **App information:** App name `rclone`; user support email: your address. → **Next**.
3. **Audience:**
   - **External** if the project is in a personal account (or you'll back up an account outside your organisation).
   - **Internal** only if the project is in the same Google Workspace organisation as the account you're backing up.
   
   → **Next**.
4. **Contact information:** your email → **Next**.
5. Agree to the policy → **Continue** → **Create**.

You'll see an **App domain** section (home page, privacy policy, terms of service). **Leave it all blank.** It's optional for a personal app.

### 5. Add scopes and test users

1. **Data Access** → **Add or remove scopes**. In *Manually add scopes*, paste:
   ```
   https://www.googleapis.com/auth/drive
   ```
   → **Add to table** → **Update** → **Save**.
   
   This one scope covers both read-only use and the read-write connection used for fixing duplicate names. rclone still only asks for read-only access when you choose scope `2` in `rclone config`.
2. **Audience** (External only) → **Test users** → **Add users** → enter the email address of the account you'll back up (e.g. your school address) → **Save**.

### 6. Create the client ID

1. **Clients** (or **Overview → Create OAuth client**, or **APIs & Services → Credentials → Create credentials → OAuth client ID**).
2. Application type: **Desktop app**. Name: `rclone`. → **Create**.
3. Copy the **Client ID** (ends in `.apps.googleusercontent.com`) and the **Client secret**. You can see them again later under **Clients**.

Now go back to the [README, step 3](../README.md#3-connect-rclone-to-google-drive) and paste them into `rclone config`.

**Already set up rclone with the shared ID?** Update it instead of starting again:

```
rclone config
```

Choose `e` (edit) → `gdrive` → paste the client ID and secret → accept the other defaults → when asked to refresh the token, answer `y` and sign in again. Repeat for any other remote (e.g. `gdrive-rw`). Check with:

```
rclone config show gdrive
```

which should show your `client_id = ….apps.googleusercontent.com`.

### 7. (Optional) Stop the 7-day sign-in expiry

While an **External** app is in **Testing**, Google expires the sign-in after 7 days. You then see `invalid_grant` or "token expired" errors. Two options:

**A. Just reconnect when needed** (simplest for occasional backups):

```
rclone config reconnect gdrive:
```

Answer `y`, sign in in the browser, done (about 30 seconds). Then run the backup.

**B. Publish the app** so sign-ins don't expire:

1. **Google Auth Platform → Audience → Publish app** → **Confirm**.
2. Run `rclone config reconnect gdrive:` once more. Sign-ins made after publishing don't expire after 7 days.

You'll still see an "unverified app" warning at sign-in. That's fine for an app only you use, and Google doesn't require verification for it. If **Publish app** is greyed out, Google is asking for a home page and privacy policy link. Option A is easier than providing those.

**Internal** apps don't have the 7-day limit at all.

---

## If sign-in is blocked

Some school or work Google Workspace domains block apps that the administrator hasn't approved. If the browser shows **"Access blocked"** or **"This app is blocked"** when you sign in, either:

- ask your IT administrator to allow your client ID (they'll need the client ID from step 6), or
- use **Google Takeout** (<https://takeout.google.com>) instead. It converts Docs/Sheets/Slides to Office formats too, but covers My Drive only, not shared drives.
