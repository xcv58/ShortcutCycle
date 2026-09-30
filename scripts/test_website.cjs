const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const preferencesPath = path.join(root, 'docs/assets/site-preferences.js');
const preferences = require(preferencesPath);
const localesPath = path.join(root, 'docs/assets/locales');
const pages = Object.fromEntries(['index.html', 'privacy/index.html', 'support/index.html'].map(file => [file,
    fs.readFileSync(path.join(root, 'docs', file), 'utf8')]));
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
    for (const [file, page] of Object.entries(pages)) {
        for (const [, key] of page.matchAll(/data-i18n(?:-[\w-]+)?="([^"]+)"/g)) {
            assert.ok(Object.hasOwn(locales.en, key), `${file}: missing translation ${key}`);
        }
    }
});

test('Privacy and Support navigation stays on the site from every page', () => {
    for (const [file, page] of Object.entries(pages)) {
        const links = [...page.matchAll(/<a\b([^>]+)>/g)].map(match => match[1]);
        for (const [key, destination] of Object.entries({
            'nav.privacy': 'privacy', 'footer.privacyPolicy': 'privacy', 'nav.support': 'support'
        })) {
            const matching = links.filter(attributes => attributes.includes(`data-i18n="${key}"`));
            assert.ok(matching.length, `${file}: missing ${key} link`);
            for (const attributes of matching) {
                const href = attributes.match(/href="([^"]+)"/)[1];
                assert.equal(path.resolve(root, 'docs', path.dirname(file), href),
                    path.join(root, 'docs', destination), `${file}: ${key} destination`);
                assert.ok(!attributes.includes('target='), `${file}: internal navigation opens a new tab`);
            }
        }
    }
});

test('nested pages have valid assets, page metadata, and readable English without JavaScript', () => {
    for (const name of ['privacy', 'support']) {
        const page = pages[`${name}/index.html`];
        assert.match(page, new RegExp(`<title data-i18n="${name}\\.meta\\.title">`));
        assert.ok(page.includes(`href="https://s.jenny.media/${name}/"`));
        assert.ok(page.includes(`data-i18n="${name}.title">${locales.en[`${name}.title`]}</h1>`));
        assert.ok(page.includes('aria-current="page"'));
        for (const [, asset] of page.matchAll(/(?:src|href)="(\.\.\/assets\/[^"]+)"/g)) {
            assert.ok(fs.existsSync(path.resolve(root, 'docs', name, asset)), `${name}: missing ${asset}`);
        }
    }
    assert.ok(pages['privacy/index.html'].includes(locales.en['privacy.collection.summary']));
    assert.ok(pages['privacy/index.html'].includes(locales.en['privacy.updated']));
    assert.match(pages['support/index.html'], /aria-describedby="report-destination"/);
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
