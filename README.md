# Humm

Dictation for macOS. Hold two keys or click the pill, speak, and Humm types what you said wherever you are typing. It learns the words it gets wrong, expands snippets, keeps a searchable history, can write British spelling and keeps count of what it costs.

Humm uses OpenAI's transcription API with your own API key: about $0.003 a minute of speech with the default model, so an hour of dictation costs about $0.18.

## Quick start

You need macOS 14 or later and an [OpenAI API key](https://platform.openai.com/api-keys) on an account with billing set up.

1. **Install Humm**, in either of two ways.
   - **Download it.** Get the latest `Humm-x.y.z.dmg` from [Releases](https://github.com/hngpt52/humm/releases/latest), open it and drag **Humm** onto **Applications**. Humm isn't notarised by Apple, so the first time you open it macOS says it can't check it for malicious software. Open **System Settings → Privacy & Security**, find the message about Humm near the bottom and click **Open Anyway**. You only need to do this once.
   - **Or build it.** With the Xcode Command Line Tools (run `xcode-select --install` if you don't have them):
     ```
     git clone https://github.com/hngpt52/humm.git
     cd humm
     scripts/build.sh --install
     ```
     This builds Humm, copies it to `/Applications` and opens it.
2. **Add your API key.** Humm asks for it the first time it opens; to change it later, choose **Change API Key…** in its menu. It is saved on your Mac in `~/.config/humm/.env`, readable only by you. From a terminal, `scripts/install-key.sh` does the same.
3. **Allow what macOS asks for.**
   - **Microphone:** macOS asks the first time you dictate.
   - **Accessibility:** Humm needs it to type into other apps and to see the keyboard shortcut. Click the waveform icon in the menu bar, choose **Grant Accessibility…** and switch Humm on in System Settings.
4. **Dictate.** Click into any text box, hold **⌃ Control + ⌥ Option**, speak, and let go.

Humm lives in the menu bar (a waveform icon) and as a small wave on the edge of your screen. To start it with your Mac, tick **Open at Login** in its menu; otherwise open it from Spotlight like any app.

## Using Humm

- **Hold to talk.** Hold **⌃ Control + ⌥ Option** while you speak and let go to finish. For longer dictation, press **Space** while holding them: recording then carries on after you let go, until you press ⌃ Control + ⌥ Option again or click the pill. **Esc** cancels. Holding ⌃⌥ with any other key, or with a click, counts as an ordinary shortcut and does not record.
- **The pill.** When not in use it is a small wave on the edge of your screen; point at it and it grows into a pill of sound-wave bars. Click it to start listening and click again to finish. Drag it anywhere along the edges of your screen: it lies along the top and bottom and stands upright on the sides. With more than one display, it moves to whichever one your mouse is on and keeps its place on the edge (switch this off with **Pill Follows Mouse Between Displays**). If you lose it, choose **Reset Pill Position** in the menu.
- **Types where you are.** The text goes into the app you are using, and your clipboard is put back afterwards. If no text box is selected when the transcript is ready, Humm shows it in a card by the pill with a **Copy** button instead.
- **Learns your words.** If Humm mishears a word, just fix it where it was typed (for example "super base" to "Supabase"). A few seconds after you stop typing, a card by the pill says it was added to your dictionary, with **Undo**. Humm then sends your words to OpenAI as spelling hints and swaps misheard versions for yours. Where the misheard version is an ordinary word ("planner" for "Plannr"), it waits until you have fixed it twice; if you change a replacement back, it stops making it. Review words under **Dictionary** in the menu. Learning works in native apps and most browsers, but not every Electron app or custom editor.
- **Snippets.** A snippet is a phrase you say and the text Humm types instead: say "my calendar link" and it types the link itself, or "sign off" for your signature. Said on its own, the phrase becomes just its text; said within a sentence, it is replaced where it stands. Add them under **Snippets…** in the menu.
- **History.** The ten latest transcripts are under **History** in the menu (click one to copy it). **Show All History…** opens a window with search, **Copy** on each one, and **Delete** in its context menu.
- **British spelling.** Colour, organise, centre: the models write American spelling, so Humm converts it. On by default on Macs set to the UK, Ireland, Australia, New Zealand or South Africa; switch it under **British Spelling** in the menu.
- **Two models.** `gpt-4o-mini-transcribe` (the default, about $0.003 a minute) or `whisper-1` ($0.006 a minute), chosen in the menu.
- **Costs.** Humm works out what each dictation cost from the usage OpenAI reports with it, at OpenAI's published prices. **Costs** in the menu shows today, yesterday, this month and the total so far, and History shows what each transcript cost. Your OpenAI bill is the final word: **Open OpenAI Usage…** opens it. Dictionary words are sent with every recording, so a long dictionary adds a little to each one (about $0.0002 for a full one).

## Keep permissions across rebuilds

macOS ties the Microphone and Accessibility permissions to the app's code signature. Without a signing certificate, `scripts/build.sh` signs Humm ad hoc, which changes with every build, so macOS asks again after each rebuild. To avoid that, create a self-signed certificate once:

1. Run `open "/System/Library/CoreServices/Certificate Assistant.app"` and choose **Create a Certificate**.
2. Name it `Humm Dev`, with Identity Type **Self Signed Root** and Certificate Type **Code Signing**. It does not need to be trusted.

`scripts/build.sh` uses a `Humm Dev` certificate automatically when there is one.

## Update and uninstall

- **Update:** download the new disk image and drag Humm onto Applications again, or, if you built it, run `git pull && scripts/build.sh --install`.
- **Uninstall:** choose **Quit Humm** in its menu, then run `rm -rf /Applications/Humm.app ~/.config/humm` and `defaults delete com.kyser.humm`, and remove Humm from **System Settings → Privacy & Security → Accessibility** and **Microphone**.

## Troubleshooting

- **Holding ⌃ Control + ⌥ Option does nothing.** Humm needs Accessibility to see those keys (⌃⌥ Space works without it). If another app, such as another dictation app, uses the same keys, only one of them gets them: quit the other.
- **macOS won't open Humm.** Downloaded apps that aren't notarised need your say-so once: **System Settings → Privacy & Security → Open Anyway**. Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Humm.app`.
- **The text is copied, not typed.** Humm has no Accessibility permission: choose **Grant Accessibility…** in its menu.
- **macOS asks for permissions after every build.** See [Keep permissions across rebuilds](#keep-permissions-across-rebuilds).
- **"Heard nothing to transcribe."** The recording was silent. Check the input device under **System Settings → Sound → Input**.
- **The pill has gone.** Choose **Reset Pill Position** in the menu, and check that **Show Floating Pill** is ticked.
- **Logs:** `/usr/bin/log stream --predicate 'subsystem == "com.kyser.humm"'`. They never include your transcripts or your key.

## Privacy

- Audio is recorded to a temporary file, sent to OpenAI and then deleted.
- The API key is read only from `~/.config/humm/.env`. Humm never writes the key or your transcripts to its logs.
- Your dictionary, snippets, history and costs stay in `~/.config/humm/` (`dictionary.json`, `snippets.json`, `history.json`, `costs.json`), readable only by you. `costs.json` holds only numbers for each day: dictations, seconds, tokens and dollars. Dictionary words are sent to OpenAI with each recording as spelling hints. History keeps the latest 1,000 transcripts; turn it off with **Keep History**, or delete it with **Clear History…**.
- Accessibility is used to type into the app you are using, to see ⌃ Control + ⌥ Option and Esc, and to learn words. For learning, Humm reads the text box it typed into for up to two minutes afterwards, only around what it typed where the app allows, and keeps nothing it reads except the corrected words. Turn it off with **Learn from My Corrections**.

## Development

Humm is a Swift package (`Humm/`) built into an app bundle by `scripts/build.sh`. `scripts/build.sh` alone builds `build/Humm.app` without installing it, and `scripts/make-dmg.sh` packs it into `build/Humm-<version>.dmg` for a release, built for both Apple silicon and Intel (that needs Xcode).

- **Checks without the network:** `build/Humm.app/Contents/MacOS/Humm --selftest-dictionary`, `--selftest-snippets`, `--selftest-history`, `--selftest-spelling`, `--selftest-costs` and `--selftest-key`.
- **Transcription:** `build/Humm.app/Contents/MacOS/Humm --selftest <audio-file> [runs] [--prompt <text>]` transcribes a file with both models and prints how long each run took, the usage OpenAI reported and what it cost.
- **Learning, end to end:** `--selftest-corrections <file>` and `--selftest-paste <file>` test against a TextEdit document named `humm-learn-test`, with `<file>` as a scratch dictionary. Launch them with `open build/Humm.app --args ...` so Humm's own Accessibility permission applies.
- **Looks:** `open build/Humm.app --args --preview recording` shows a state (`recording`, `transcribing`, `done`, `notice`, `error`, `learned` or `card`) without recording. `--preview-rail bottom` (or `right`, `top`, `left`) holds the pill on one edge; `--preview-screen 2` uses another display and `--preview-hover` shows the pointed-at look. `--preview-history` and `--preview-snippets` open those windows, `--preview-key-prompt` shows the API key prompt, with `--history-file`, `--snippets-file` or `--costs-file` for sample data.
- **Focus:** `open -g build/Humm.app --args --probe-focus 8` prints, for eight seconds, the role of the focused element in the app in front and whether Humm would type there or show the copy card. It never reads text.
- **Icon:** drawn in code: `swift scripts/make-icon.swift Humm.iconset && iconutil -c icns Humm.iconset -o Humm/Resources/Humm.icns`.

## Why an API key?

Humm began as a test of whether a ChatGPT subscription could pay for transcription from a separate app. It cannot: the documented Sign in with ChatGPT route does not accept audio, and the ChatGPT apps' own dictation service is not open to other apps. So Humm uses the public API.

## Licence

MIT. See [LICENSE](LICENSE).
