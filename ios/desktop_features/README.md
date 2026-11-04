# Desktop features to build on iOS

Each file here describes a feature that was built in the desktop app
([`../../browser`](../../browser)) but isn't in the iPhone and iPad app yet.
Whoever builds a feature on desktop writes the spec (see
[`browser/AGENTS.md`](../../browser/AGENTS.md#ios-parity-required)), and the
iOS work builds the Swift version from it.

## Workflow

1. **Desktop:** copy [`_TEMPLATE.md`](_TEMPLATE.md) to
   `<feature-name>.md` (lowercase kebab case) and fill in every section.
   Set **iOS status** to `Not started`.
2. **iOS:** when you start the Swift version, set the status to
   `In progress`. Use **Desktop implementation** to read the Rust code and
   **Acceptance criteria** to test your build.
3. **iOS:** when it ships, set the status to `Built on iOS`, add the Swift
   files, and add the feature to the Features list in
   [`../README.md`](../README.md). Keep the file as a record, or delete it
   if the team prefers.

## Specs

| Feature | iOS status |
| --- | --- |
| [Media from the user's folders](media-from-user-folders.md) | Not started |

Add a row when you add a spec, and keep its status in step with the file.
