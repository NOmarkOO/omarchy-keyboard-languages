# Screenshot harness

`capture.sh` renders the installed plugin in four stock Quattro themes on a temporary empty workspace. A shell trap restores both the previous workspace and theme. Its dedicated IPC target can only navigate among panel views; it cannot invoke Add, Apply, Remove, or any keyboard helper action.

Run it from a live Quattro session after installing the current checkout:

```bash
./demo/capture.sh
```

The harness selects an unused workspace from 10–99, verifies that it contains no application windows, and captures only the rightmost 520 pixels of the focused monitor. This keeps the wallpaper, language label, tray context, and anchored panel while excluding unrelated windows. Output replaces the four optimized PNGs in `docs/screenshots/`. Layout names come from the current read-only plugin state; the harness never rewrites them.
