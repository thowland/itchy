<!--
Draft. Intended for the disk image as well as the repository.

To confirm before it ships, because none has been exercised on a real login or
from a real keyboard since the features landed:
- Itchy starting at login from /Applications.
- ⌘Z, ⌘C, ⌘V and Paste and Match Style (⌥⇧⌘V) inside a pad. Itchy has no menu
  bar of its own, and ⌘B only worked once the pad handled it directly.
- The Gatekeeper wording for an unsigned download on current macOS.
Screenshots, when added, should include the formatting buttons.
-->

# Itchy User Guide

Itchy is a scratchpad that lives in your menubar. It gives you a handful of
pads, each a small window that floats over whatever you are working in. Type or
paste into one, close it, and everything is still there next time. There is
nothing to save, name or file.

It is meant for things that are passing through: a tracking number, a block of
JSON, a paragraph you are still working on, a screenshot you need for an hour.

## Getting started

1. Drag **Itchy** into your **Applications** folder, then open it.
2. A welcome window explains the basics. Click **Start Scratching** to close it.
3. Look for the **cat** in the menubar at the top of the screen.

Itchy has no Dock icon and no main window. Everything starts from the cat. If
you cannot see it, your menubar may be full: on a Mac with a camera notch, icons
that do not fit are hidden, so try quitting another menubar app.

## Pads

Click the cat to see your pads. Choose one to open it.

- **A pad floats.** It stays above other windows, including fullscreen
  applications, so you can keep it beside your work.
- **It stays where you put it.** Move and resize a pad and it reopens in the
  same place.
- **Closing puts it away.** Click the close button. Nothing is lost, and there is
  no prompt.
- **Everything saves as you type.**

To make a new pad, choose **New Pad** from the menu. It opens ready to type in.
You can have up to nine pads to begin with; see *Settings* to change that.

The first nine pads have keyboard shortcuts, shown beside them in the menu. A 📌
beside a pad means it reopens when Itchy starts. A size beside a pad means it has
grown past 32 MB, usually from images.

## The hotkey

Press **⌃⌥Space** (Control, Option, Space) from anywhere to bring back the pad
you used last. Press it again to put the pad away. If you have no pads, it makes
one.

You can choose a different combination in Settings.

## Writing in a pad

Each pad is either **styled** or **plain**. The pad's mode is shown at the bottom
of its window.

**Styled** pads keep formatting. Paste from a web page or a document and the
bold, lists and tables come with it. Paste or drag in a picture and it appears
in the pad. Large pictures, such as a full-screen screenshot, are reduced when
they arrive so a pad does not grow out of hand.

**Bold, italic and underline** are the **B**, *I* and U buttons at the bottom of
a styled pad, or **⌘B**, **⌘I** and **⌘U**. Select some text first, or turn one
on before you type. The buttons light up to show what the selected text has.

**Plain** pads hold text only, which is what you want for code, JSON or a SQL
query. They never change quotes into curly quotes or dashes into long dashes, and
anything you paste arrives without formatting.

Switching a styled pad to plain removes its formatting and pictures. If that was
a mistake, **Undo** straight away brings them back.

The **⋯** button at the bottom right of every pad has:

- **Pad Settings…**, described below.
- **Copy All as Plain Text**, for when you need the words without the formatting.
- **Switch to Plain** or **Switch to Styled**.
- **Empty Pad**, which clears it. While the pad is open, Undo restores what was
  there.

## Transforms

The wand button beside **⋯** applies an operation to a pad's text. If some text
is selected it acts on the selection; otherwise it acts on the whole pad. Either
way it counts as a single step, so one Undo puts back exactly what was there.

- **Flatten Styling**, on a styled pad — keeps the words, drops the formatting.
- **Upper Case**, **Lower Case**, **Title Case**. Title case raises the first
  letter of each word and leaves the rest alone, so `JSON` stays `JSON`.
- **Pretty-print JSON** and **Minify JSON**. Your keys stay in the order you
  wrote them and your numbers keep the form you wrote them in.
- **Encode Base64** and **Decode Base64**.
- **Encode URL Component** and **Decode URL Component** — for a value that goes
  inside a URL, so characters like `&` and `=` are encoded.
- **Trim Whitespace** — trailing spaces on each line, and blank space at the
  very start and end.
- **Sort Lines**, ascending.

An entry is greyed out when it does not apply to what is in front of it: **Decode
Base64** stays grey until the text really is base64 that decodes to text. Hover
over a grey entry to see why. If something goes wrong, the pad is left exactly as
it was and the reason appears in the pad's status line for a few seconds.

## Pad settings

Choose **Pad Settings…** from a pad's **⋯** menu to change that pad alone:

- **Name.** Pads are named automatically, and you never have to change it. A name
  helps you find a pad in the menu. Press Return or close the sheet to keep it.
  A pad always has a name, so clearing the field keeps the old one.
- **Mode.** Styled or plain, as above.
- **Reopen this pad when Itchy starts.** For a pad you want on screen all the
  time.

If another pad already has the same name, Itchy tells you. Both pads still work
normally.

## Managing pads

Choose **Pads…** from the menu to see every pad in one list. There you can:

- Rename a pad by editing its name.
- Pin a pad with the pin button, so it reopens when Itchy starts.
- Change a pad's mode.
- Drag pads into a different order. The menu follows the same order.
- Add a pad with **+**, or delete the selected pad with **−**.

Deleting is the only thing in Itchy that asks first, because it cannot be undone.

## Settings

Choose **Settings…** from the menu.

**General**

- **Start Itchy at login.** On by default. This only takes effect when Itchy is in
  your Applications folder.
- **Global hotkey.** Click the recorder and press a new combination. If another
  application already uses it, Settings says so.
- **Pads.** How many pads you can have, from 1 to 20. Lowering the number never
  deletes or hides pads you already have; it only stops new ones being made.

**Editor**

- **New pads start as** styled or plain.
- **Font** and **Size** for the text in your pads. The change applies to what is
  already in them, not only to new typing. Text you pasted in a font of its own
  keeps that font.

**Backups**

- **Backups to keep.** How many copies to keep. **Zero turns backups off.**
- **Also keep a daily backup.**
- **Show in Finder** and **Delete All Backups**.

## Backups

Itchy keeps a copy of all your pads when it starts and when it quits, and once a
day if you ask it to, but only when something has actually changed. Old copies
are removed once you have more than you chose to keep.

A backup includes pads you have since deleted. If you would rather no copies of
deleted pads existed, set **Backups to keep** to zero, or use **Delete All
Backups**.

### Restoring from a backup

1. Quit Itchy: click the cat, then **Quit Itchy**.
2. In **Settings → Backups**, click **Show in Finder**, or open
   `~/Library/Application Support/Itchy/archives.noindex/`. Each folder is named
   with the date and time it was taken.
3. Open the backup you want. Copy the pads inside its `pads` folder into
   `~/Library/Application Support/Itchy/pads.noindex/`, and copy its `index.json`
   into `~/Library/Application Support/Itchy/`, replacing what is there.
4. Open Itchy again.

To be safe, copy the current `pads.noindex` folder somewhere else first.

## Privacy

- Your pads stay on your Mac. Itchy makes no network connections. The only link
  it contains, on the welcome screen, opens in your browser.
- Pads are kept out of Spotlight, so their contents do not appear in searches.
- Pads are ordinary files in `~/Library/Application Support/Itchy/`, readable with
  any text editor.
- Backups contain pads you have deleted, as described above.

## Letting an agent use your pads

A coding agent can read and write pads, over the Model Context Protocol. None of
it happens until you switch it on, and then only for the pads you choose.

**Switch the server on.** **Settings → Agents**, then *Let agents read and write
exposed pads*. The line beneath says what it is doing: listening on
`127.0.0.1`, and on which port. That address means this machine and no other —
nothing on your network can reach it, and neither can anything on the internet.
The menubar says so too while it is running.

**Give the agent the token.** Beside the switch is a token. Press **Show** to
read it or **Copy** to put it on the clipboard, and give it to the agent as a
bearer token. A request without it is refused, and told nothing about what pads
exist. **Regenerate** makes a new one and stops the old one working straight
away, which is what to do if you have pasted it somewhere you should not have.

**Expose the pads you want it to see.** A pad is private until you say
otherwise. Open the pad's own settings — the **⋯** menu on the pad — and turn on
*Let agents read and write this pad*. An exposed pad says **exposed** at the
bottom of its window, so you can tell at a glance.

A pad you have not exposed is not merely hidden: an agent asking for it by name
is told there is no such pad, which is the same answer it gets for a pad that
does not exist. It cannot use the tools to find out what you have.

**What an agent can do.** Five things: list the exposed pads, read one, append
to one, replace one, and create a new pad. That is the whole of it. A pad an
agent creates is exposed to it — otherwise it could not read back what it just
wrote — and it appears in your menu like any other pad, marked exposed, and you
can turn that off or delete it.

**What you will see.** A pad something other than you wrote to shows a banner
saying who wrote, how much, and when. If the pad was open at the time, the
banner's **Undo** reverts that write and nothing else, and the Edit menu names
it. If the pad was closed, there is nothing to undo — the pad's undo history
starts when you open it — so the banner says so, and the menubar marks the pad
until you look at it.

**Images.** An agent reads plain text, so a picture in a pad comes through as a
line reading `[image 1240×820]`. It is told something is there rather than being
quietly given a pad with a hole in it.

## Help

**Itchy Help**, from the menubar or from the **Help** button on the About
screen, covers all of this in more detail: getting started, working with pads,
transforms, agents, backups, and where your files are. ⌘? opens it.

## If something is misbehaving

**Settings → General** has a switch for a diagnostic log. It is off by default.
When you turn it on, Itchy writes what it is doing to `/tmp/itchy.log` — which
backups it took and which it skipped and why, which agent requests arrived and
what came of them, which transforms ran. It is the quickest way to find out why
something did not happen.

It records what happened, to which pad by name, and how many characters were
involved. It does not contain the text of your pads, anything an agent wrote, or
the agent token. Anyone with an account on your Mac can read `/tmp`, so switch
the log off and delete the file when you are done with it.

## About

Choose **About Itchy** from the menu to see which version you have. Include it
if you report a problem.

## Troubleshooting

**I can't find Itchy after opening it.** It has no Dock icon. Look for the cat
in the menubar, and if the menubar is crowded, quit another menubar app to make
room.

**The hotkey does nothing.** Another application is probably using the same
combination. **Settings → General** says so under the hotkey; choose a different
one.

**Itchy doesn't start at login.** Check that it is in your **Applications**
folder, that **Start Itchy at login** is on, and that Itchy is allowed in
**System Settings → General → Login Items**.

**The agent server says a port is already in use.** Something else on your Mac
is on that port. Change it in **Settings → Agents** — any number will do — and
the server restarts on the new one.

**My agent stopped working.** Check that the server is still switched on, that
the pad is still exposed, and that the agent has the current token. Regenerating
the token stops the old one working immediately, including for agents already
connected.

**An agent says a pad is open in Itchy.** Only tools that cannot reach an open
window say this, `itchyctl` among them. Close the pad and try again.

**A pad says its content is unreadable.** Itchy found something wrong with that
pad's files and will not open an empty pad over them, because saving would
destroy what is left. Use **Reveal in Finder** to look at the files, or restore
the pad from a backup.

**macOS says Itchy can't be opened, or is damaged.** Current builds are not yet
signed for distribution, so macOS is cautious about a copy downloaded from the
internet. If you trust where your copy came from, open **System Settings →
Privacy & Security** and choose **Open Anyway** for Itchy.

## Removing Itchy

1. Quit Itchy.
2. Delete **Itchy** from your Applications folder.
3. To remove your pads and backups too, delete
   `~/Library/Application Support/Itchy/`.
4. If it still appears in **System Settings → General → Login Items**, remove it
   there.
