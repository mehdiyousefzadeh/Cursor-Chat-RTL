# Cursor chat direction

Windows installer that sets the direction of each Cursor chat paragraph from its first letter. Persian and Arabic paragraphs start on the right. English paragraphs start on the left. The change stays after Cursor is closed.

The install folder does not matter. `apply.bat` finds Cursor in Program Files, in your user folder, from the Start menu shortcut, and from the Windows install list. If none of those match, it asks you for the folder that contains `Cursor.exe`.

## What it does

- A paragraph that starts with Persian or Arabic is right-aligned.
- A paragraph that starts with English is left-aligned.
- A mixed sentence follows the first letter of that paragraph. `سلام Hello` is right-aligned. `Hello سلام` is left-aligned.
- The chat input box uses the same rule.
- Code blocks stay left-aligned.
- The code editor, terminal, and menus are not changed.

Windows only.

## Get the folder

Download **Code → Download ZIP** on this page, then extract the zip. Do not run `apply.bat` from inside the zip.

Or clone it:

```bash
git clone https://github.com/mehdiyousefzadeh/Cursor-Chat-RTL.git
```

## Install

1. In Cursor, choose **File → Exit**.
2. Open Task Manager and confirm `Cursor.exe` is not running. Closing the window is not enough. Cursor often stays open in the background.
3. Double-click `apply.bat`.
4. If Windows asks for administrator permission, click **Yes**. That prompt appears only when Cursor is in a protected folder such as `Program Files`. A copy in your user folder does not need it.
5. Wait until the window lists the install paths it updated. Check that the path matches the Cursor shortcut you open.
6. Press **Enter**, then open Cursor again.

If the installer cannot find Cursor, it asks for a folder. Right-click the Cursor shortcut, choose **Open file location**, and paste that folder. It must contain `Cursor.exe`.

You can also pass the folder yourself:

```bat
apply.bat "D:\Apps\Cursor"
```

Every Cursor install that is found gets updated, so it does not matter which shortcut you open afterward.

The result is written to `install-log.txt` in this folder. Original files are backed up here:

```text
%APPDATA%\Cursor\User\cursor-chat-bidi\backup
```

## Try it

Send these as two separate paragraphs:

```text
سلام. این جمله باید از راست شروع شود.
Hello. This paragraph should start on the left.
```

Assistant replies follow the same rule, one paragraph at a time.

## After a Cursor update

An update replaces files inside the Cursor folder and removes this behavior. Quit Cursor completely, then run `apply.bat` again.

## Restore

1. Quit Cursor completely.
2. Double-click `restore.bat`. Click **Yes** if Windows asks for administrator permission.
3. Open Cursor again.

Restore works only after `apply.bat` has created a backup.

## If the installer reports an error

- `Cursor is still open`: end every `Cursor.exe` in Task Manager, then run `apply.bat` again.
- Administrator permission was refused: run `apply.bat` again and click **Yes**. This is only required for a copy in a folder such as `Program Files`.
- Cursor was not found: paste the folder from **Open file location** on the Cursor shortcut.

If Cursor will not open after installing, end it in Task Manager and run `restore.bat`.

## Files that change

You do not need to edit these yourself. For each Cursor install it finds, `apply.bat`:

1. Copies `chat-bidi.js` into `resources\app\out\vs\code\electron-sandbox\workbench`.
2. Inserts these lines in `workbench.html`, directly before `workbench.js`:

```html
<!-- CURSOR_CHAT_BIDI -->
<script src="./cursor-chat-bidi.js"></script>
```

3. Updates the `workbench.html` checksum in `product.json` so Cursor does not warn that the install is corrupt.
4. Appends a short snippet to `main.js` so another Cursor window runs the same script.

Do not calculate the checksum by hand. If you edit the HTML yourself, run `apply.bat` again.
