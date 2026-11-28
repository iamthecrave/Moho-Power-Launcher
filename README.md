# Moho Power Launcher

> ⚠️ **AI-written code.** This program was created by CHEESOID, a working partnership between a human animator, Doug Craven, and Claude, an AI model made by Anthropic. Ideas were conceived and evaluated by Doug. **Every line of the launcher's code was written by Claude (AI)**, then directed and tested by hand by Doug Craven. Please read [AI-NOTICE.md](AI-NOTICE.md), and back up your Moho scripts folder before you first use it.

**Download:** [Moho-Power-Launcher-1.2.0.zip](https://github.com/iamthecrave/Moho-Power-Launcher/releases/download/v1.2.0/Moho-Power-Launcher-1.2.0.zip) · [how to install](#installing)


## What It Does
Choose the Moho scripts you want to load at Moho run time. Feature rich and FREE! 
<!-- your text here -->
<img width="1359" height="832" alt="splash screen" src="https://github.com/user-attachments/assets/e7124ab8-315a-4750-b9b5-27ce94374922" />

## Main Features 
<img width="1359" height="832" alt="launcher features" src="https://github.com/user-attachments/assets/eafc0494-d275-4b79-91af-567ae775d515" />

## Complete List of Features (this section written by AI)

- **Only what you need:** tick the scripts you want, click Launch Moho, and Moho starts with exactly those.
- **Columns:** sort scripts into columns (Draw, Rig, Animate...). Tick a column's title to switch it all on.
- **Saved sets:** save a selection as "Rigging" or "Lip Sync" and switch with one pick.
- **Install from a download:** pick the .zip or .lua you downloaded and it's in.
- **Sort the Tools panel:** put add-on tools in Moho's groups or your own, in your order. Rename or delete your own groups, and switch scripts on or off right there.
- **Drag to organise:** drag a script to another column, or right-click > Move to.
- **Safe:** only removes files it installed. Your own scripts are never touched.
- **Clean undo:** untick everything and Moho is back exactly as it was.
- **Easy install:** double-click to install, no admin rights. Uninstall keeps your scripts.
- **Free** for non-commercial use.



## How it works (this section written by AI)

- **Your library.** Every script lives in its own folder in *scripts master folder*, inside your Moho Pro folder. When you click **Launch Moho**, the launcher copies the ticked scripts into Moho's scripts folder and takes the unticked ones out.
- **Installed a script with Moho's own Scripts > Install Script?** Nothing to do. Next time the launcher opens, it adds that script by itself: ticked, in the **Unsorted** column. Drag it to any column. If you'd rather the launcher left a script alone (work in progress, say), click **Not these...** and tick it; it stays in Moho as it is.
- **Downloaded a script?** Click **Install script...**, pick the .zip or .lua, then choose its column and the name to show.
- **Edited a script in Moho's scripts folder?** The next launch saves your edit into your library, so your version is the one that comes back. The old copy goes to *scripts master folder\_backups* first. If the library copy changed too (a newer download), nothing is overwritten: both versions are kept and the launcher tells you where.
- **Columns.** Draw, Rig, Animate, All Purpose and Unsorted are always there. Add up to five of your own with **Columns...**; they sit in a second row. Removing one sends its scripts to Unsorted.
- **A different version already in Moho?** If Moho's scripts folder has a copy the launcher didn't put there, and your library has a different version, the launcher asks once: use the library's version (your copy is backed up first), or keep yours. If you keep yours, it asks again only when the library version changes.
- **Your own scripts are safe.** The launcher only ever removes files it put there itself.

## Requirements
- Moho Pro 14 on Windows 10 or 11 (uses Windows PowerShell, which comes with Windows). Tested on 14.5.1. Mac is not supported.

## Installing
1. Download the zip and unzip it (right-click > **Extract All**).
2. Double-click **Install Moho Power Launcher**.
3. If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.
4. Check the three places it found, then click **Install**.

**Updating:** download the new zip and run its installer the same way; the button says **Update**. Your ticks, saved sets, toolbar groups and library are kept.

**Where it goes:** the program installs to `%LOCALAPPDATA%\Programs\Moho Power Launcher`. In your Moho Custom Content Folder it adds two folders: *scripts master folder* (your library) and *Moho Power Launcher* (your ticks, saved sets and toolbar groups).

**To remove it:** Windows Settings > Apps > Installed apps > **Moho Power Launcher** > Uninstall. Every script stays in Moho exactly as it is, and your library is kept. Want Moho back as it was before the launcher? Untick everything, click **Launch Moho** once, then uninstall.

## Meet Cheesoid
<p align="center"><img src="images/cheesoid.png" alt="Cheesoid: a grey robot pouring cheese onto a plate, shouting CHEESE" width="320"></p>

Moho Power Launcher is made by **Cheesoid**, a team of two:
- **Doug Craven**, who designed it, directed it and tested every feature by hand in Moho.
- **Claude**, an AI model made by Anthropic, who wrote all of the code.

Contact: [mohovibecoding@gmail.com](mailto:mohovibecoding@gmail.com)


## Licence
PolyForm Noncommercial 1.0.0: use it, change it or share it for any noncommercial purpose. Selling it, or using it in a paid product or service, is not allowed. See [LICENSE](LICENSE).

**Conventions review:** checked against the MohoScripts Scripting Conventions; see [AI-CONVENTIONS-REVIEW.md](AI-CONVENTIONS-REVIEW.md).

## More from Cheesoid
- [Moho Flipbook](https://github.com/iamthecrave/Moho-Flipbook): pose-to-pose animation in Moho, laid out like a flipbook of drawings.
