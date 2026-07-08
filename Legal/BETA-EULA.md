# Terra Cognita — Beta End User License Agreement

**Last updated:** 2026-05-31
**Effective:** when you install the beta build and use the software

This is the agreement between **Frostfyre Studios** ("we", "us", "Frostfyre") and **you** ("you", "the beta tester") covering your use of the **Terra Cognita beta** (the "Beta Software"). By installing the Beta Software through TestFlight or any other distribution channel we provide, you accept these terms. If you don't accept them, don't install the Beta Software.

This is a **draft**. We may revise it before opening the beta more widely; the latest version always lives in our repository and on `terra-cognita.app`.

---

## 1. What This Beta Is

Terra Cognita is a markdown-atlas workbench for the Apple ecosystem. The Beta Software is **pre-release** — it is unfinished, may change without notice, may contain bugs, may lose data, and may stop working at any time. We do our best to avoid those outcomes but cannot guarantee against them.

Things you should expect from a beta:
- Features may appear, change, or be removed between builds.
- Build numbers reset or roll forward unpredictably.
- We may publish a new build at any time and previous builds may stop being supported.
- We may end the beta program at any time, with or without notice.

Things you should not expect from a beta:
- Long-term stability of file formats. We try not to break atlases between builds, but we reserve the right to change the on-disk format and to provide (or not provide) migration tooling.
- Service-level commitments. There is no support SLA. We will read feedback sent to `info@terra-cognita.app` and respond when we can.

## 2. Your Data, Your Files

Terra Cognita stores your atlas as **plain Markdown files** in a folder you choose on your device. Those files are **yours**:

- You retain all ownership, copyright, and intellectual-property rights in the content you create with the Beta Software, including notes, edges, metadata, and any text generated with the help of on-device AI features at your direction.
- The Beta Software does not upload your atlas, does not analyze it remotely, does not share it with us, and does not require an account.
- We do not collect, retain, or have access to any of your atlas contents.
- You are responsible for your own backups. We recommend keeping the atlas folder under version control (git) or in a cloud-synced location of your choosing (iCloud Drive, Dropbox, etc.).

If we ever change this position — for example, by introducing an optional cloud-sync feature in a future version — we will do so **opt-in**, with clear disclosure, and never silently.

## 3. AI Features (Foundation Models)

The Beta Software's AI features run **on-device** through Apple's Foundation Models framework. Specifically:

- Text generation, summarization, link suggestion, era inference, and similar AI operations happen entirely on your device.
- Speech-to-text (dictation) uses Apple's `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` — audio does not leave the device.
- We do not see your prompts, the AI's responses, or any intermediate state.

Apple's own terms govern Foundation Models behavior; using AI features in the Beta Software constitutes use of those underlying Apple services.

You are responsible for the use you make of AI-generated text — including verifying factual claims, respecting copyrights, and exercising judgment before publishing or relying on outputs.

## 4. Network Usage

The Beta Software is **offline-first**. The only outbound network requests are ones you explicitly invoke:

- **Wikipedia enrichment** — when you paste a Wikipedia URL or use the Capture flow with a URL, the app fetches the corresponding article from Wikipedia's public API to enrich a node.
- **Generic web fetches** — when you paste a non-Wikipedia URL into Capture, the app fetches the page's HTML so it can be summarized on-device.

These requests are made directly from your device to the relevant third-party server. They are subject to those servers' terms and privacy policies. We don't proxy them, log them, or see them.

The Beta Software contains no analytics SDKs, no crash reporters that phone home, and no telemetry of any kind.

## 5. Acceptable Use

Don't use the Beta Software to:
- Violate any applicable law.
- Infringe anyone's intellectual property.
- Distribute the Beta Software or its build artifacts outside the channels we approve (i.e., don't repackage the `.ipa` and hand it around).
- Reverse-engineer the Beta Software except where local law explicitly grants that right and we cannot contract around it.

You may freely view and share **your own** atlases — including ones you create with the Beta Software's assistance. The files belong to you.

## 6. Feedback

If you send us feedback (bug reports, feature ideas, screenshots, etc.), you grant us a **non-exclusive, royalty-free, worldwide license to use that feedback** to improve the Beta Software and any future versions, without compensation or attribution. You retain ownership of the underlying feedback content. You can ask us to remove identifiable information you've sent (by emailing `info@terra-cognita.app`); we will do so within a reasonable timeframe.

## 7. No Warranties

THE BETA SOFTWARE IS PROVIDED **"AS IS"** AND **"AS AVAILABLE"**, WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, OR THAT THE SOFTWARE WILL BE ERROR-FREE OR UNINTERRUPTED.

Some jurisdictions don't allow exclusion of certain implied warranties. In those jurisdictions, the exclusions above apply only to the maximum extent permitted by law.

## 8. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT WILL FROSTFYRE BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES — INCLUDING LOST PROFITS, LOST DATA, OR LOST GOODWILL — ARISING FROM OR RELATED TO YOUR USE OF THE BETA SOFTWARE, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. FROSTFYRE'S TOTAL CUMULATIVE LIABILITY UNDER OR RELATED TO THIS AGREEMENT WILL NOT EXCEED **ONE HUNDRED U.S. DOLLARS ($100)** OR THE AMOUNT YOU PAID FOR THE BETA SOFTWARE, WHICHEVER IS GREATER. (You probably paid nothing for the beta. We're acknowledging the cap clearly.)

This section reflects the bargain we're striking: the Beta Software is provided to you for free, on the basis that we are not signing up for unbounded financial exposure if it does something unexpected. If that is not an acceptable bargain in your jurisdiction or for your use case, please do not install the Beta Software.

## 9. Termination

You may stop using the Beta Software at any time by deleting it from your device. We may end your access to the Beta Software at any time, with or without cause, by revoking your TestFlight invitation or distributing a build that requires re-acceptance of updated terms.

Sections 2, 6, 7, 8, and 10 survive termination.

## 10. Governing Law

This Agreement is governed by the laws of the **State of California, U.S.A.**, without regard to its conflict-of-laws principles. Disputes will be resolved in the state or federal courts located in California.

If you reside in a jurisdiction whose consumer-protection law gives you a non-waivable right to resolve disputes in your local courts, those rights are preserved.

## 11. Changes to This Agreement

We may revise this Agreement. When we do, we'll update the "Last updated" date at the top, post the new version in our repository and at `terra-cognita.app`, and — for material changes — notify beta participants by email or in-app. Continued use of the Beta Software after a change is your acceptance of the revised Agreement.

## 12. Contact

`info@terra-cognita.app`

---

*This is a draft prepared by the development team and is not legal advice. Before distributing the Beta Software publicly, review and finalize with qualified counsel in the applicable jurisdiction(s). Sections 7 (no warranties), 8 (limitation of liability), and 10 (governing law) in particular have jurisdiction-specific enforceability nuances that benefit from professional review.*
