# Terra Cognita — Privacy Policy

**Last updated:** 2026-06-08
**Effective:** when you install Terra Cognita and use the app

This policy describes how **Terra Cognita** (the "app"), published by **Frostfyre Studios** ("we", "us"), handles your information. We've designed the app so that we collect nothing — this policy spells out what that means in practice and what data flows do exist.

If you would prefer the short version: **we don't collect, transmit, or have access to anything about you or your atlas**. Read on for the longer version.

---

## 1. What We Collect

**Nothing.** The app does not collect or transmit personal information, usage analytics, crash reports, device identifiers, advertising IDs, location, contacts, or any other data about you or your device to us or any third party for our benefit.

We have no accounts, no logins, no servers that store your data. We do not know who installed the app, how often you use it, or what is in your atlas.

## 2. Your Files

Terra Cognita stores your atlas as **plain Markdown files** in a folder you choose on your device. Those files are **yours**:

- You retain all ownership and copyright in the content.
- The app does not upload, copy, transmit, or remotely analyze your atlas.
- You are responsible for your own backups (e.g., Git, iCloud Drive, Time Machine).

If we ever introduce optional sync or cloud-storage features, they will be **opt-in**, clearly disclosed, and never enabled silently.

## 3. AI Features (On-Device)

The app's AI features — text generation, summarization, link suggestion, era inference, and similar — run **entirely on your device** through Apple's Foundation Models framework. Your prompts, the model's responses, and any intermediate state stay on your device. We do not see them, and Apple's Foundation Models terms govern that on-device processing.

## 4. Speech-to-Text (On-Device)

When you use dictation in the app, transcription uses Apple's `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. **Audio does not leave your device.** The app requests microphone access only when you initiate dictation.

## 5. Network Requests

The app is **offline-first**. The only outbound network requests are ones you explicitly invoke:

- **Wikipedia enrichment** — when you paste a Wikipedia URL or use the Capture flow with a Wikipedia URL, your device fetches the corresponding article from Wikipedia's public API.
- **Generic web fetches** — when you paste a non-Wikipedia URL, your device fetches the page's HTML so it can be summarized on-device.

These requests go **directly from your device** to the relevant third-party server. We don't proxy, log, or see them. They are subject to those servers' own terms and privacy policies (e.g., Wikipedia's Privacy Policy).

The app contains **no analytics SDKs, no crash reporters that phone home, and no telemetry of any kind.**

## 6. Permissions We Request

| Permission | Why | When asked |
|---|---|---|
| Folder access (user-selected) | To read and write the atlas folder you pick | When you pick a folder |
| Microphone | For on-device dictation in note input | When you first tap a dictation control |
| Speech recognition | For on-device transcription | Same as microphone |

You can revoke any of these in your device's Settings at any time. The app degrades gracefully — features that need a revoked permission stop working, but the app does not crash or surface aggressive re-prompts.

## 7. Children's Privacy

The app is not directed to children under 13, and we do not knowingly collect information from anyone (children included) — see Section 1.

## 8. Your Rights

Because we do not collect or store your information, requests under privacy frameworks like the GDPR or CCPA — to access, correct, delete, or export your data — have nothing on our end to act on.

Your atlas content lives on your device under your control. You can delete it, copy it, sync it, or back it up at any time, using your operating system's tools.

## 9. Changes to This Policy

We may update this policy. When we do, we will revise the "Last updated" date above and post the new version in our repository and at `terra-cognita.app/privacy`. Material changes will be announced in-app or by email to anyone who has voluntarily contacted us.

## 10. Contact

Questions about this policy: `info@terra-cognita.app`

---

*Companion to [`BETA-EULA.md`](BETA-EULA.md). For commercial-use terms of the source code itself, see [`LICENSE`](../../LICENSE) (PolyForm Noncommercial 1.0.0).*
