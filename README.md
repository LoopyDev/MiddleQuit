<img width="256" height="256" alt="App Icon" src="https://github.com/user-attachments/assets/f312eefa-01ee-469d-9c97-7e95fecd8804" />

# MiddleQuit

Quit apps by middle clicking Dock items, or tapping them with three fingers on a trackpad. No other apps needed.

# Help me out - I'm not greedy :)
Build the app yourself, or get it here: https://loopydev.gumroad.com/l/rmmvgk
(and buy me a fraction of a coffee for my efforts ☺️)

# Features
- Regular Quit, Force Quit, or both.
- Three-finger tap on a trackpad, with an optional setting to use it as a middle click everywhere
- Easy 'Launch at Login' setting
- Hide icon from Menu Bar (open the app again to get back to Settings)
- Modifier keys assignable in app settings

## Info
The app lives in the top bar, from where you can enable launch at login, open the accessibility settings (if not enabled - more on that below), open settings, or quit the app.

## Installation
When you first open the app, it will ask you to enable Accessibility permissions. This is standard for apps like these, so they can interfere with regular input processes. MiddleQuit starts working as soon as you enable it.

If you choose to download and run the pre-built app, when initially opening it, you will need to manually allow it to run (Apple could not verify “MiddleQuit.app” is free of malware that may harm your Mac or compromise your privacy.) by going to System Settings -> Privacy & Security -> Scroll down to 'Security' and allow it there. 

I'm not completely familiar with sharing macOS apps, so if you have any issues installing, open an issue and hopefully we can work through it together. 

## Trackpads
Three-finger taps work out of the box, and a short guide shows you how on first launch. Turn on "Use it as a middle click everywhere" to replace apps like MiddleClick. If one is still running, MiddleQuit drops the duplicate click.

Reading trackpad touches relies on a private Apple framework, so a macOS update could stop this working until MiddleQuit is updated. Everything else, including real middle clicks, would carry on as normal.

## Compatibility
- Tahoe 26.1
- Sequoia 15.6.1

**Currently reported not working on Sonoma** (but I am working on it)

(let me know your system and if it works on it, I can add to this list)

## Don't trust me?
I don't blame you! I'm just a random guy on the internet who vibe coded a Mac app. If you prefer, build the app yourself in Xcode after ensuring there is no pesky code inside. 😄

https://github.com/user-attachments/assets/b492be2e-e48f-4cf7-b7c3-b596e24f8a73

# Settings
<img width="566" height="406" alt="settingsPage" src="https://github.com/user-attachments/assets/8567c05d-df59-4693-bf5a-b5687f435c26" />


# License
Copyright (C) 2025-2026 LoopyDev

MiddleQuit is free software, released under the [GNU General Public License v3.0](LICENSE) or any later version.

Versions up to and including 1.0 were released under the MIT License, and that code remains available under those terms. Everything from 1.1 onwards is GPLv3.
