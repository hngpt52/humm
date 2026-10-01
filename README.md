# Humm

Dictation for macOS. Hold two keys or click the pill, speak, and Humm types what you said wherever you are typing. It learns the words it gets wrong, expands snippets, keeps a searchable history and can write British spelling.

Humm uses OpenAI's transcription API with your own API key: about $0.003 a minute of speech with the default model, so an hour of dictation costs about $0.18.

## Quick start

You need macOS 14 or later, the Xcode Command Line Tools (run `xcode-select --install` if you don't have them) and an [OpenAI API key](https://platform.openai.com/api-keys) on an account with billing set up.

1. **Get the code.**
   ```
   git clone https://github.com/hngpt52/humm.git
   cd humm
   ```
2. **Save your API key.** The script asks for the key, hides what you type and saves it to `~/.config/humm/.env`, readable only by you.
   ```
   scripts/install-key.sh
   ```
3. **Build and install.** This builds Humm, copies it to `/Applications` and opens it.
   ```
   scripts/build.sh --install
   ```
4. **Allow what macOS asks for.**
   - **Microphone:** macOS asks the first time you dictate.
   - **Accessibility:** Humm needs it to type into other apps and to see the keyboard shortcut. Click the waveform icon in the menu bar, choose **Grant Accessibility…** and switch Humm on in System Settings.
5. **Dictate.** Click into any text box, hold **⌃ Control + ⌥ Option**, speak, and let go.

Humm lives in the menu bar (a waveform icon) and as a small wave on the edge of your screen. To start it with your Mac, tick **Open at Login** in its menu; otherwise open it from Spotlight like any app.

## Using Humm

- **Hold to talk.** Hold **⌃ Control + ⌥ Option** while you speak and let go to finish. For longer dictation, press **Space** while holding them: recording then carries on after you let go, until you press ⌃ Control + ⌥ Option again or click the pill. **Esc** cancels. Holding ⌃⌥ with any other key, or with a click, counts as an ordinary shortcut and does not record.
- **The pill.** When not in use it is a small wave on the edge of your screen; point at it and it grows into a pill of sound-wave bars. Click it to start listening and click again to finish. Drag it anywhere along the edges of your screen: it lies along the top and bottom and stands upright on the sides. If you lose it on another display, choose **Reset Pill Position** in the menu.
- **Types where you are.** The text goes into the app you are using, and your clipboard is put back afterwards. If no text box is selected when the transcript is ready, Humm shows it in a card by the pill with a **Copy** button instead.
- **Learns your words.** If Humm mishears a word, just fix it where it was typed (for example "super base" to "Supabase"). A few seconds after you stop typing, a card by the pill says it was added to your dictionary, with **Undo**. Humm then sends your words to OpenAI as spelling hints and swaps misheard versions for yours. Where the misheard version is an ordinary word ("planner" for "Plannr"), it waits until you have fixed it twice; if you change a replacement back, it stops making it. Review words under **Dictionary** in the menu. Learning works in native apps and most browsers, but not every Electron app or custom editor.
- **Snippets.** A snippet is a phrase you say and the text Humm types instead: say "my calendar link" and it types the link itself, or "sign off" for your signature. Said on its own, the phrase becomes just its text; said within a sentence, it is replaced where it stands. Add them under **Snippets…** in the menu.
- **History.** The ten latest transcripts are under **History** in the menu (click one to copy it). **Show All History…** opens a window with search, **Copy** on each one, and **Delete** in its context menu.
- **British spelling.** Colour, organise, centre: the models write American spelling, so Humm converts it. On by default on Macs set to the UK, Ireland, Australia, New Zealand or South Africa; switch it under **British Spelling** in the menu.
- **Two models.** `gpt-4o-mini-transcribe` (the default, about $0.003 a minute) or `whisper-1` ($0.006 a minute), chosen in the menu.

## Keep permissions across rebuilds

macOS ties the Microphone and Accessibility permissions to the app's code signature. Without a signing certificate, `scripts/build.sh` signs Humm ad hoc, which changes with every build, so macOS asks again after each rebuild. To avoid that, create a self-signed certificate once:

1. Run `open "/System/Library/CoreServices/Certificate Assistant.app"` and choose **Create a Certificate**.
2. Name it `Humm Dev`, with Identity Type **Self Signed Root** and Certificate Type **Code Signing**. It does not need to be trusted.

`scripts/build.sh` uses a `Humm Dev` certificate automatically when there is one.

## Update and uninstall

- **Update:** `git pull && scripts/build.sh --install`.
- **Uninstall:** choose **Quit Humm** in its menu, then run `rm -rf /Applications/Humm.app ~/.config/humm` and `defaults delete com.kyser.humm`, and remove Humm from **System Settings → Privacy & Security → Accessibility** and **Microphone**.

## Troubleshooting

- **Holding ⌃ Control + ⌥ Option does nothing.** Humm needs Accessibility to see those keys (⌃⌥ Space works without it). If another app, such as another dictation app, uses the same keys, only one of them gets them: quit the other.
- **The text is copied, not typed.** Humm has no Accessibility permission: choose **Grant Accessibility…** in its menu.
- **macOS asks for permissions after every build.** See [Keep permissions across rebuilds](#keep-permissions-across-rebuilds).
- **"Heard nothing to transcribe."** The recording was silent. Check the input device under **System Settings → Sound → Input**.
- **The pill has gone.** Choose **Reset Pill Position** in the menu, and check that **Show Floating Pill** is ticked.
- **Logs:** `/usr/bin/log stream --predicate 'subsystem == "com.kyser.humm"'`. They never include your transcripts or your key.

## Privacy

- Audio is recorded to a temporary file, sent to OpenAI and then deleted.
- The API key is read only from `~/.config/humm/.env`. Humm never writes the key or your transcripts to its logs.
- Your dictionary, snippets and history stay in `~/.config/humm/` (`dictionary.json`, `snippets.json`, `history.json`), readable only by you. Dictionary words are sent to OpenAI with each recording as spelling hints. History keeps the latest 1,000 transcripts; turn it off with **Keep History**, or delete it with **Clear History…**.
- Accessibility is used to type into the app you are using, to see ⌃ Control + ⌥ Option and Esc, and to learn words. For learning, Humm reads the text box it typed into for up to two minutes afterwards, only around what it typed where the app allows, and keeps nothing it reads except the corrected words. Turn it off with **Learn from My Corrections**.

## Development

Humm is a Swift package (`Humm/`) built into an app bundle by `scripts/build.sh`. `scripts/build.sh` alone builds `build/Humm.app` without installing it.

- **Checks without the network:** `build/Humm.app/Contents/MacOS/Humm --selftest-dictionary`, `--selftest-snippets`, `--selftest-history` and `--selftest-spelling`.
- **Transcription:** `build/Humm.app/Contents/MacOS/Humm --selftest <audio-file> [runs] [--prompt <text>]` transcribes a file with both models and prints how long each run took.
- **Learning, end to end:** `--selftest-corrections <file>` and `--selftest-paste <file>` test against a TextEdit document named `humm-learn-test`, with `<file>` as a scratch dictionary. Launch them with `open build/Humm.app --args ...` so Humm's own Accessibility permission applies.
- **Looks:** `open build/Humm.app --args --preview recording` shows a state (`recording`, `transcribing`, `done`, `notice`, `error`, `learned` or `card`) without recording. `--preview-rail bottom` (or `right`, `top`, `left`) holds the pill on one edge; `--preview-screen 2` uses another display and `--preview-hover` shows the pointed-at look. `--preview-history` and `--preview-snippets` open those windows, with `--history-file` or `--snippets-file` for sample data.
- **Focus:** `open -g build/Humm.app --args --probe-focus 8` prints, for eight seconds, the role of the focused element in the app in front and whether Humm would type there or show the copy card. It never reads text.
- **Icon:** drawn in code: `swift scripts/make-icon.swift Humm.iconset && iconutil -c icns Humm.iconset -o Humm/Resources/Humm.icns`.

## Why an API key?

Humm began as a test of whether a ChatGPT subscription could pay for transcription from a separate app. It cannot: the documented Sign in with ChatGPT route does not accept audio, and the ChatGPT apps' own dictation service is not open to other apps. So Humm uses the public API.

## Licence

MIT. See [LICENSE](LICENSE).
