# Cursor Chat RTL

Align each Cursor chat paragraph by its **first letter**. Persian and Arabic start on the right, English on the left. The change stays after you close Cursor.

`apply.bat` finds Cursor on its own — Program Files, your user folder, the Start menu, or the Windows install list. If it cannot, it asks for the folder that contains `Cursor.exe`.

**Windows only.**

## ✨ What it does

- Persian or Arabic first letter → right
- English first letter → left
- Mixed lines follow the first letter: `سلام Hello` is right, `Hello سلام` is left
- The chat box uses the same rule
- Code blocks stay left
- The editor, terminal, and menus are left alone

## 🚀 Install

1. In Cursor, choose **File → Exit**. Confirm `Cursor.exe` is gone in Task Manager.
2. Download **Code → Download ZIP**, extract it, and double-click `apply.bat`. Do not run it from inside the zip.
3. If Windows asks for administrator permission, click **Yes**. That prompt only appears for a protected folder such as `Program Files`.
4. Press **Enter**, then open Cursor.

Or clone and run it from the folder:

```bash
git clone https://github.com/mehdiyousefzadeh/Cursor-Chat-RTL.git
```

Cursor in a custom folder:

```bat
apply.bat "D:\Apps\Cursor"
```

Every install that is found gets updated. A backup is saved at `%APPDATA%\Cursor\User\cursor-chat-bidi\backup`.

## ✅ Try it

Send these as two separate paragraphs:

```text
سلام. این جمله باید از راست شروع شود.
Hello. This paragraph should start on the left.
```

## 🔁 Update and restore

After a Cursor update, quit Cursor and run `apply.bat` again.

To undo: quit Cursor, double-click `restore.bat`, then open Cursor. Restore only works after a successful `apply.bat`.

## ⚠️ If it fails

| Message | What to do |
| --- | --- |
| Cursor is still open | End every `Cursor.exe` in Task Manager, then run `apply.bat` again |
| Administrator permission | Run `apply.bat` again and click **Yes** |
| Cursor was not found | Right-click the Cursor shortcut → **Open file location**, and paste that folder |

If Cursor will not open afterward, end it in Task Manager and run `restore.bat`.
