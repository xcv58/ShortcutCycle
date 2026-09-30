# Website language and appearance maintenance

The homepage, Privacy page, and Support page support the same 15 languages as the
Mac app. Copy lives in
`assets/locales/<language>.json`; the language catalog and first-paint preference
logic live in `assets/site-preferences.js`. Shared styling and runtime controls live
in `assets/site.css` and `assets/site.js`; `assets/content-pages.css` styles the
reading layout on `/privacy/` and `/support/`.

## Writing and terminology

Translate the intent of a sentence, not its English word order. Headlines may be
rewritten entirely. Keep feature behavior, prices, compatibility, and commands
accurate. Use the Mac app's translated labels when explaining its controls.

| Language | Voice and conventions |
| --- | --- |
| English | Direct, concise instructions; familiar Mac terminology. |
| German | Informal **du**, concise headings, Tastenkürzel and Apps. |
| French | **Vous**, typographic apostrophes, Réglages and raccourcis. |
| Spanish | **Tú**, atajos and ajustes; avoid region-specific slang. |
| Japanese | Polite explanatory prose, familiar Mac terms, Japanese punctuation. |
| Brazilian Portuguese | **Você**, apps and Ajustes; Apple Shortcuts is Atalhos. |
| Simplified Chinese | Direct, natural task descriptions; 分组 and 快捷键. |
| Traditional Chinese | Taiwan usage: 群組, 捷徑, 清單, 隱私權. |
| Italian | **Tu**, scorciatoie; Apple Shortcuts is Comandi Rapidi. |
| Korean | Consistent polite endings and familiar 앱 / 단축키 terminology. |
| Arabic | Modern Standard Arabic, right-to-left layout, readable line spacing. |
| Dutch | **Je**, sneltoetsen and reservekopieën; Apple Shortcuts is Opdrachten. |
| Polish | Direct instructions, skróty and kopie zapasowe. |
| Turkish | Polite plural imperatives, kısayol; Apple Shortcuts is Kestirmeler. |
| Russian | Consistent **вы**, conventional desktop terms such as сочетания клавиш. |

The two `hero.benefit…` sentence fragments must be edited together. The suffix
includes its leading space for languages that use one; Japanese and Chinese do
not. Keep literal shortcut names, URL schemes, and shell commands unchanged.

The displayed price is explicitly in US dollars, using local decimal conventions;
these translations do not invent local App Store prices. Brand names remain
unchanged. Screenshots, videos, and the original Apple badge artwork remain the
shared English assets, with translated captions and accessible labels. Privacy and
Support navigation stays on this site and uses the selected language.
The Support page clearly labels its external GitHub Issues reporting destination;
GitHub and source-code destinations retain their own languages.

The Privacy page translates `PRIVACY_POLICY.md`. Keep `PRIVACY_POLICY_ZH_HANS.md`,
the HTML fallback, and all locale files in sync when updating the policy or its date.
Support reuses the homepage FAQ keys
and adds menu bar help, shortcut troubleshooting, and the existing reporting channel.
When changing header/footer markup, update all three HTML pages together.

## Preference behavior

- A saved language wins over the browser's language list. Unsupported languages
  fall back to English. Chinese script tags take precedence over region tags;
  Portuguese variants use the supported Brazilian Portuguese translation.
- Only English and the selected locale are fetched initially. Subsequent choices
  are cached for the current page. A failed user selection preserves the previous
  language and shows/announces the failure. A failed initial load retains English HTML.
  Uncached choices immediately show a spinner and localized loading text, while
  the picker remains usable. Requests time out after 10 seconds; stale requests
  cannot clear feedback for a newer choice. Cached choices skip loading feedback.
- The page sets `lang` and Arabic `dir="rtl"`. Navigation follows reading direction;
  code remains left-to-right. UI copy, accessibility labels, captions, and browser
  metadata update together. This is a client-side language picker, not separate
  localized URLs for search engines or social crawlers.
- Appearance initially follows the device. The header button selects the opposite
  appearance and remembers it. The footer resets to device appearance. Storage
  failures do not prevent changing language or appearance for the current page.
- The screenshot gallery can still have a separate light/dark preview selection.

## Validation

Run `node --test scripts/test_website.cjs`. CI checks locale parity with the app,
complete keys, preserved markup/links/commands, language matching, theme defaults,
and first-paint behavior with unavailable storage. These checks do not establish
translation fluency; review the rendered copy as well.

For browser verification, serve `docs/` over HTTP. Check navigation among the
homepage, `/privacy/`, and `/support/`, including saved language/theme and direct
visits. Check all languages at
320, 390, 768, and 1440 pixels in light and dark modes. Keep navigation accessible
on small screens. Inspect Arabic navigation, gallery arrows, code blocks, and
mixed-direction text, plus Japanese/Chinese sentence spacing and long headings.
Test reload persistence, device appearance changes, footer reset, gallery theme
override, failed locale loads, rapid language changes, and blocked storage.

To reproduce slow-request regressions, open a fresh English page in an isolated
browser and run `scripts/verify_website_loading.js` with
`agent-browser eval --stdin < scripts/verify_website_loading.js`. It checks immediate
feedback, changing choices mid-load, localized status, timeout, failure, cached
selection, and retry. The timeout test takes 10 seconds.
