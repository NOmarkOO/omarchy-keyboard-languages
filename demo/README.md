# Screenshot harness

`capture.sh` renders the installed plugin in four stock Quattro themes and restores the previous theme through a shell trap. Its dedicated IPC target can only navigate among panel views; it cannot invoke Add, Apply, Remove, or any keyboard helper action.

Run it from a live Quattro session after installing the current checkout:

```bash
./demo/capture.sh
```

The harness captures only the rightmost 520 pixels of the focused monitor, including the language label, tray context, and anchored panel. Output replaces the four optimized PNGs in `docs/screenshots/`. Layout names come from the current read-only plugin state; the harness never rewrites them.
