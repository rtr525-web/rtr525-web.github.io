# Jayhil Bridge — Windows (Alienware)

1. Download this folder (`JayhilBridge.ps1`, `StartBridge.bat`, `BridgeMenu.bat`) anywhere, e.g. your Desktop.
2. Double-click **StartBridge.bat**. If Windows SmartScreen warns, choose **More info → Run anyway**.
3. It creates `%USERPROFILE%\JayhilBridge\` with `tasks\`, `results\`, `logs\` and watches `tasks\` every 15 s.
4. Muse (or Claude, via the Claude desktop app's Remote Control on that folder) drops a task `.json` into `tasks\`; the result appears in `results\`.

Allowed task types: `open_urls`, `open_folder`, `google_photos_assist`, `set_wallpaper`, `empty_trash` (asks first), `write_status`.
Everything else is refused. No passwords, no arbitrary commands — same rules as the Mac Bridge.
Mac-only jobs (Apple Photos import, Dock cleanup, Instagram archive automation) are not available on Windows.

`status.txt` also shows whether the Empire site is LIVE (read from the Connection Spooler's `ai-sync/status.json`).
