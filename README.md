# wranglv0

> **An intent-based launcher for Android.** Stop navigating apps — just say what you want done. 

---

## The Problem

Every smartphone still works like a filing cabinet. You know what you want to *do*, but you're forced to remember *which app*, *which menu*, *which flow* gets

WranglHarness flips this. You express intent. The system handles the rest.

---

## What It Does

WranglHarness sits as a decision layer on top of Android. Instead of launching apps, you state a goal — typed or spoken — and WranglHarness routes it to the right app, screen, and context automatically.

| You say | WranglHarness does |
|---|---|
| `"Order food"` | Opens the right delivery app with your saved address and recent order |
| `"Call mom"` | Dials immediately — no contacts app, no searching |
| `"Continue my work"` | Resumes the last relevant file, tab, or workflow |
| `"Play something relaxing"` | Picks app and content based on your listening history |

---

## How It Works

```
User input (text / voice / signal)
        ↓
  Context engine  ←  time, location, usage history
        ↓
   Intent parser
        ↓
  Action router  →  app + deeplink + context
```

**Four layers:**

- **Input** — text, voice, or passive signals (time of day, connected device, etc.)
- **Context** — usage history, current session state, ambient signals
- **Intent parsing** — maps natural language to structured goals
- **Action routing** — resolves the best app + entry point + pre-filled context

---

## Status

`wranglv0` is an experimental prototype. APIs, architecture, and behaviour are all subject to change.

---

## Getting Started

_Setup instructions coming soon._

---

## Contributing

Pull requests are welcome. For significant changes, open an issue first to discuss the approach.
