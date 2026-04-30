# Audio assets

`alarm.wav` and `heart.wav` are wired into the app via `pubspec.yaml`
and played by `just_audio` during a session.

These files are NOT committed — drop in your own:

* `alarm.wav` — short, attention-getting, 1–2 s, looped during an
  active alarm condition. Anything under 200 KB.
* `heart.wav` — a soft tick used to mirror the device's pulse beep
  bit; ≈100 ms.

A common choice is the BSD-licensed
[KDE soundscapes](https://invent.kde.org/system/oxygen/-/tree/master/sounds)
or any royalty-free clinical-monitor tone.
