const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const preferencesPath = path.join(root, 'docs/assets/site-preferences.js');
const preferences = require(preferencesPath);
const localesPath = path.join(root, 'docs/assets/locales');
const html = fs.readFileSync(path.join(root, 'docs/index.html'), 'utf8');
const locales = Object.fromEntries(Object.keys(preferences.languages).map(language => [language,
    JSON.parse(fs.readFileSync(path.join(localesPath, `${language}.json`), 'utf8'))]));

test('website languages match the app resources exactly', () => {
    const appLanguages = fs.readdirSync(path.join(root, 'ShortcutCycle/ShortcutCycle/Resources'))
        .filter(name => name.endsWith('.lproj')).map(name => name.replace('.lproj', '')).sort();
    assert.deepEqual(Object.keys(locales).sort(), appLanguages);
    assert.deepEqual(fs.readdirSync(localesPath).filter(name => name.endsWith('.json')).sort(),
        appLanguages.map(language => `${language}.json`).sort());
});

test('every language has complete copy and preserves markup, links, and literal shortcuts', () => {
    const keys = Object.keys(locales.en).sort();
    const markup = value => value.match(/<[^>]+>/g) || [];
    const literals = value => [...value.matchAll(/<code>(.*?)<\/code>/g)].map(match => match[1]);
    for (const [language, strings] of Object.entries(locales)) {
        assert.deepEqual(Object.keys(strings).sort(), keys, language);
        for (const key of keys) {
            assert.equal(typeof strings[key], 'string', `${language}: ${key}`);
            assert.ok(strings[key].trim(), `${language}: ${key}`);
            assert.deepEqual(markup(strings[key]), markup(locales.en[key]), `${language}: markup in ${key}`);
            assert.deepEqual(literals(strings[key]), literals(locales.en[key]), `${language}: command in ${key}`);
        }
    }
    for (const [, key] of html.matchAll(/data-i18n(?:-[\w-]+)?="([^"]+)"/g)) {
        assert.ok(Object.hasOwn(locales.en, key), `Missing HTML translation: ${key}`);
    }
});

test('language detection handles regional variants and explicit script tags', () => {
    for (const [input, output] of Object.entries({
        'de-AT': 'de', 'fr-CA': 'fr', 'es-MX': 'es', 'pt-PT': 'pt-BR',
        'pt_BR': 'pt-BR', 'zh-TW': 'zh-Hant', 'zh-HK': 'zh-Hant',
        'zh-MO': 'zh-Hant', 'zh-CN': 'zh-Hans', 'zh-Hans-TW': 'zh-Hans',
        'zh-Hant-CN': 'zh-Hant', 'ar-EG': 'ar', 'EN-us': 'en'
    })) assert.equal(preferences.normalizeLanguage(input), output, input);
    assert.equal(preferences.normalizeLanguage('english'), null);
    assert.equal(preferences.detectLanguage('ja', ['de-DE']), 'ja');
    assert.equal(preferences.detectLanguage('invalid', ['sv-SE', 'nl-BE', 'fr']), 'nl');
    assert.equal(preferences.detectLanguage(null, ['sv-SE']), 'en');
    assert.equal(preferences.detectLanguage(null, []), 'en');
});

test('appearance follows the device unless a valid explicit theme is chosen', () => {
    for (const theme of [null, undefined, '', 'invalid', 'system']) {
        assert.equal(preferences.normalizeTheme(theme), 'system');
        assert.equal(preferences.resolveTheme(theme, true), 'dark');
        assert.equal(preferences.resolveTheme(theme, false), 'light');
    }
    assert.equal(preferences.resolveTheme('light', true), 'light');
    assert.equal(preferences.resolveTheme('dark', false), 'dark');
});

test('first paint survives blocked storage and sets Arabic direction before rendering', () => {
    const htmlElement = { dataset: {} };
    const context = {
        document: { documentElement: htmlElement }, navigator: { languages: ['ar-SA'] },
        localStorage: { getItem() { throw new Error('Storage blocked'); } }
    };
    vm.runInNewContext(fs.readFileSync(preferencesPath, 'utf8'), context);
    assert.equal(htmlElement.lang, 'ar');
    assert.equal(htmlElement.dir, 'rtl');
    assert.equal(htmlElement.dataset.theme, 'system');
    context.localStorage.getItem = key => key === 'theme' ? 'dark' : 'zh-Hant';
    vm.runInNewContext(fs.readFileSync(preferencesPath, 'utf8'), context);
    assert.equal(htmlElement.lang, 'zh-Hant');
    assert.equal(htmlElement.dir, 'ltr');
    assert.equal(htmlElement.dataset.theme, 'dark');
});
