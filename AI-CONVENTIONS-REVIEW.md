# MohoScripts Conventions Review: Moho Power Launcher

> ⚠️ **AI-written review.** Written by Claude (AI, Anthropic) for Cheesoid on 28 Nov 2026, checking this code against the [MohoScripts Scripting Conventions](https://mohoscripts.com/help/scripting-conventions).

Checked: version 1.2.0. The launcher is a Windows program (PowerShell), not a Moho script, so the Lua naming rules don't apply to it. The rules about scripts living together peacefully do apply, because it installs and removes other people's scripts.

## Passes
- Only removes files it recorded installing. Scripts you installed yourself are never touched.
- Uninstalling leaves every script in Moho exactly as it is, and keeps your library.
- An edit you make in Moho's scripts folder is saved into your library (with a backup) instead of being overwritten.
- If Moho already has a different copy of a script that the launcher didn't put there, it asks before replacing it, and backs your copy up first.
- "Not these..." lets you take any script out of the launcher's hands.
- When two packages carry the same file, it's installed once and stays while either package is ticked.
- In `scripts\tool\_tool_list.txt` (shared by every add-on), it only adds and removes its own lines.
- Its program files carry its own prefix (`MPL-...`, `MohoPowerLauncher...`), its program and data folders carry its own name, and the tick lists it adds to Windows Forms are in their own `CheesoidMPL` namespace.

## To note
1. When it picks up a script installed through Moho, it collects that script's pictures from `ScriptResources\<script name>`, the folder the conventions call for. A script whose resource folder is named differently is picked up without its pictures.
2. If two packages carry different copies of the same file, the copy with the newer file date wins, not the higher version. MohoScripts asks that shared utilities stay backward-compatible, so the newer copy should be safe.
3. The library folder it creates in your Moho content folder has a plain name: `scripts master folder` (with `_backups` inside it). Kept for now, because renaming it would mean moving every existing setup.
