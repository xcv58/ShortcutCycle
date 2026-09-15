/* Shared by first-paint setup, the language picker, and the preference tests. */
(function (root) {
    'use strict';
    const languages = {
        en: 'English', de: 'Deutsch', fr: 'Français', es: 'Español', ja: '日本語',
        'pt-BR': 'Português (Brasil)', 'zh-Hans': '简体中文', 'zh-Hant': '繁體中文',
        it: 'Italiano', ko: '한국어', ar: 'العربية', nl: 'Nederlands', pl: 'Polski',
        tr: 'Türkçe', ru: 'Русский'
    };
    function normalizeLanguage(language) {
        const parts = String(language || '').toLowerCase().replaceAll('_', '-').split('-');
        const base = parts[0];
        if (base === 'zh') {
            if (parts.includes('hant')) return 'zh-Hant';
            if (parts.includes('hans')) return 'zh-Hans';
            return parts.some(part => ['tw', 'hk', 'mo'].includes(part)) ? 'zh-Hant' : 'zh-Hans';
        }
        if (base === 'pt') return 'pt-BR';
        return Object.hasOwn(languages, base) ? base : null;
    }
    function detectLanguage(saved, browserLanguages) {
        return normalizeLanguage(saved) || browserLanguages.map(normalizeLanguage).find(Boolean) || 'en';
    }
    function normalizeTheme(theme) {
        return ['light', 'dark'].includes(theme) ? theme : 'system';
    }
    function resolveTheme(theme, prefersDark) {
        return normalizeTheme(theme) === 'system' ? (prefersDark ? 'dark' : 'light') : theme;
    }
    function readStorage(key) {
        try { return root.localStorage.getItem(key); } catch { return null; }
    }
    const api = { languages, normalizeLanguage, detectLanguage, normalizeTheme, resolveTheme, readStorage };
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    root.ShortcutCyclePreferences = api;
    if (root.document) {
        const html = root.document.documentElement;
        const language = detectLanguage(readStorage('shortcutcycle-language'), root.navigator.languages || [root.navigator.language || 'en']);
        html.lang = language;
        html.dir = language === 'ar' ? 'rtl' : 'ltr';
        html.dataset.language = language;
        html.dataset.theme = normalizeTheme(readStorage('theme'));
    }
})(globalThis);
