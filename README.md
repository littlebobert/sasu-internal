# Sasu

Sasu is a macOS app that explains Japanese websites, forms, and other on-screen content without changing the page layout.

It captures only when you ask. Depending on your settings, Sasu can send a screenshot, selected text, clipboard text, or Safari page context to OpenAI directly with your own API key, or through the hosted invite backend.

## Build

```sh
swift build
./Scripts/build-app.sh
open "Build/Sasu.app"
```

## Backend

The `backend/` directory contains the invite-only hosted access proxy.

## Privacy

API keys and invite tokens are stored in macOS Keychain. Request bodies are not logged by the backend.
