// Shared site controls; gallery and FAQ behavior activate only where those elements exist.
const localeBaseURL = new URL('locales/', document.currentScript.src);

// Enable active state on iOS
document.addEventListener('touchstart', () => { }, { passive: true });

// Remove preload class to enable transitions after first paint
requestAnimationFrame(() => {
    requestAnimationFrame(() => {
        document.body.classList.remove('preload');
    });
});

const html = document.documentElement;
const themeToggle = document.getElementById('theme-toggle');
const themeSystem = document.getElementById('theme-system');
const preferences = window.ShortcutCyclePreferences;
const themeAnnouncement = document.getElementById('theme-announcement');
const prefersDarkMedia = window.matchMedia('(prefers-color-scheme: dark)');
const screenshotThemeBtns = {
    light: document.getElementById('screenshot-btn-light'),
    dark: document.getElementById('screenshot-btn-dark')
};
const screenshotThemeAnnouncement = document.getElementById('screenshot-theme-announcement');
const screenshotVariantFrames = Array.from(document.querySelectorAll('.screenshot-variant'));
const desktopHoverMedia = window.matchMedia('(hover: hover) and (pointer: fine)');
const languageSelect = document.getElementById('language-select');
const languageAnnouncement = document.getElementById('language-announcement');
const languageStatus = document.getElementById('language-status');

function showLanguageStatus(message = '', loading = false) {
    languageStatus.textContent = message;
    languageStatus.hidden = !message;
    languageSelect.setAttribute('aria-busy', String(loading));
    languageSelect.closest('.language-selector').classList.toggle('is-loading', loading);
}
const languageStorageKey = 'shortcutcycle-language';
let isScreenshotThemeOverridden = false;
let currentLanguage = 'en';
let languageRequest = 0;
const pendingLanguages = new Map();

const translations = {};
const initialLanguagePreference = html.dataset.language || 'en';
languageSelect.replaceChildren(...Object.entries(preferences.languages).map(([code, name]) => {
    const option = new Option(name, code);
    option.lang = code;
    option.dir = code === 'ar' ? 'rtl' : 'ltr';
    return option;
}));

async function loadLanguage(language) {
    if (translations[language]) return translations[language];
    if (!pendingLanguages.has(language)) {
        const controller = new AbortController();
        const timeout = window.setTimeout(() => controller.abort(), 10000);
        const request = fetch(new URL(`${language}.json`, localeBaseURL), { signal: controller.signal }).then(response => {
            if (!response.ok) throw new Error(`Language unavailable: ${language}`);
            return response.json();
        }).then(strings => {
            translations[language] = strings;
            return strings;
        }).finally(() => {
            window.clearTimeout(timeout);
            pendingLanguages.delete(language);
        });
        pendingLanguages.set(language, request);
    }
    return pendingLanguages.get(language);
}

function saveLanguage(language) {
    try {
        localStorage.setItem(languageStorageKey, language);
    } catch (error) {
        // Preference persistence is best-effort when storage is unavailable.
    }
}

function clearSavedLanguage() {
    try {
        localStorage.removeItem(languageStorageKey);
    } catch (error) {
        // Ignore storage failures.
    }
}

const normalizeLanguage = preferences.normalizeLanguage;

function getTranslationValue(key, language = currentLanguage) {
    return translations[language]?.[key] ?? translations.en?.[key];
}

function translateText(key) {
    const value = getTranslationValue(key);
    return typeof value === 'string' ? value : '';
}

function updateFaqToggleLabel() {
    const btn = document.getElementById('faq-toggle-btn');
    if (!btn) return;
    const isExpanded = btn.dataset.expanded === 'true';
    btn.textContent = translateText(isExpanded ? 'faq.collapseAll' : 'faq.expandAll');
}

function updateScreenshotLabels() {
    document.querySelectorAll('[data-screenshot-key]').forEach((frame) => {
        const key = frame.dataset.screenshotKey;
        const labels = key === 'menuBar' ? getTranslationValue('screenshots.menuBar') : {
            light: translateText(`screenshots.${key}.light`),
            dark: translateText(`screenshots.${key}.dark`)
        };
        const image = frame.querySelector('img');

        if (!labels) return;

        if (typeof labels === 'string') {
            frame.dataset.title = labels;
            frame.setAttribute('data-title', labels);
            if (image) image.setAttribute('alt', labels);
            return;
        }

        frame.dataset.lightTitle = labels.light;
        frame.dataset.lightAlt = labels.light;
        frame.dataset.darkTitle = labels.dark;
        frame.dataset.darkAlt = labels.dark;
    });
}

function getActiveScreenshotTheme() {
    const activeButton = document.querySelector('.screenshot-theme-btn.active');
    return activeButton?.dataset.screenshotTheme || getResolvedTheme();
}

function applyTranslations() {
    document.title = translateText(document.querySelector('title').dataset.i18n || 'meta.title');

    document.querySelectorAll('[data-i18n]').forEach((element) => {
        element.textContent = translateText(element.dataset.i18n);
    });

    document.querySelectorAll('[data-i18n-html]').forEach((element) => {
        element.innerHTML = translateText(element.dataset.i18nHtml);
    });

    document.querySelectorAll('[data-i18n-content]').forEach((element) => {
        element.setAttribute('content', translateText(element.dataset.i18nContent));
    });

    document.querySelectorAll('[data-i18n-aria-label]').forEach((element) => {
        element.setAttribute('aria-label', translateText(element.dataset.i18nAriaLabel));
    });

    document.querySelectorAll('[data-i18n-title]').forEach((element) => {
        element.setAttribute('title', translateText(element.dataset.i18nTitle));
    });

    document.querySelectorAll('[data-i18n-alt]').forEach((element) => {
        element.setAttribute('alt', translateText(element.dataset.i18nAlt));
    });

    document.querySelectorAll('[data-i18n-data-tooltip]').forEach((element) => {
        element.setAttribute('data-tooltip', translateText(element.dataset.i18nDataTooltip));
    });

    updateFaqToggleLabel();
    updateControls(html.dataset.theme || 'system');
    updateScreenshotLabels();
    if (isScreenshotThemeOverridden) {
        applyScreenshotTheme(getActiveScreenshotTheme());
    } else {
        syncScreenshotThemeWithPage();
    }
}

async function setLanguage(language, options = {}) {
    let normalizedLanguage = normalizeLanguage(language) || 'en';
    const { persist = false, announce = false } = options;
    const request = ++languageRequest;
    const needsLoading = !translations.en || !translations[normalizedLanguage];
    let failureMessage = '';
    showLanguageStatus(needsLoading ? translateText('language.loading') || 'Loading translation…' : '', needsLoading);
    if (needsLoading) languageAnnouncement.textContent = languageStatus.textContent;
    try {
        try {
            await Promise.all([loadLanguage('en'), loadLanguage(normalizedLanguage)]);
        } catch (error) {
            if (request !== languageRequest) return false;
            failureMessage = translateText('language.loadFailed') || 'This language could not be loaded. Please try again.';
            if (persist) {
                languageSelect.value = currentLanguage;
                languageAnnouncement.textContent = failureMessage;
                return false;
            }
            // Keep the readable English HTML if a first-visit language cannot load.
            normalizedLanguage = 'en';
            try { await loadLanguage('en'); } catch { /* Static English content remains usable. */ }
        }
        if (request !== languageRequest) return false;
        currentLanguage = normalizedLanguage;
        html.lang = normalizedLanguage;
        html.dir = normalizedLanguage === 'ar' ? 'rtl' : 'ltr';
        html.setAttribute('data-language', normalizedLanguage);
        languageSelect.value = normalizedLanguage;
        if (persist) saveLanguage(normalizedLanguage);
        if (translations.en) applyTranslations();
        if (announce || needsLoading) languageAnnouncement.textContent = failureMessage || translateText('language.changed');
        document.dispatchEvent(new CustomEvent('language-updated', { detail: normalizedLanguage }));
        return true;
    } finally {
        // An older request must not clear the latest choice's loading feedback.
        if (request === languageRequest) showLanguageStatus(failureMessage);
    }
}

function getStoredTheme() {
    try {
        return preferences.normalizeTheme(localStorage.getItem('theme'));
    } catch (error) {
        return 'system';
    }
}

function getResolvedTheme(theme = html.getAttribute('data-theme') || 'system') {
    return preferences.resolveTheme(theme, prefersDarkMedia.matches);
}

function announceTheme(theme) {
    if (!themeAnnouncement) return;
    themeAnnouncement.textContent = translateText(`theme.${theme}Selected`);
}

function announceScreenshotTheme(theme) {
    if (!screenshotThemeAnnouncement) return;
    screenshotThemeAnnouncement.textContent = translateText(`gallery.${theme}Selected`);
}

function updateScreenshotControls(activeTheme) {
    Object.entries(screenshotThemeBtns).forEach(([theme, btn]) => {
        if (!btn) return;
        const isActive = theme === activeTheme;
        btn.classList.toggle('active', isActive);
        btn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    });
}

function applyScreenshotTheme(theme, options = {}) {
    if (theme !== 'light' && theme !== 'dark') return;

    const { lock = false, announce = false } = options;

    screenshotVariantFrames.forEach((frame) => {
        const image = frame.querySelector('img');
        const href = frame.dataset[`${theme}Href`];
        const src = frame.dataset[`${theme}Src`];
        const srcset = frame.dataset[`${theme}Srcset`];
        const title = frame.dataset[`${theme}Title`];
        const alt = frame.dataset[`${theme}Alt`];

        if (href) frame.setAttribute('href', href);
        if (title) frame.setAttribute('data-title', title);

        if (!image) return;
        if (src) image.setAttribute('src', src);
        if (srcset) image.setAttribute('srcset', srcset);
        if (alt) image.setAttribute('alt', alt);
    });

    updateScreenshotControls(theme);

    if (lock) isScreenshotThemeOverridden = true;
    if (announce) announceScreenshotTheme(theme);
    document.dispatchEvent(new CustomEvent('screenshots-theme-updated'));
}

function syncScreenshotThemeWithPage() {
    if (isScreenshotThemeOverridden) return;
    applyScreenshotTheme(getResolvedTheme());
}

function setTheme(theme, shouldAnnounce = true) {
    theme = preferences.normalizeTheme(theme);
    html.setAttribute('data-theme', theme);
    try {
        localStorage.setItem('theme', theme);
    } catch (error) {
        // Theme persistence is best-effort when storage is unavailable.
    }
    updateControls(theme);
    syncScreenshotThemeWithPage();
    if (shouldAnnounce) announceTheme(theme);
}

function updateControls(activeTheme) {
    const dark = getResolvedTheme(activeTheme) === 'dark';
    const label = translateText(dark ? 'theme.switchToLight' : 'theme.switchToDark') ||
        (dark ? 'Switch to light mode' : 'Switch to dark mode');
    themeToggle.setAttribute('aria-label', label);
    themeToggle.title = label;
    themeToggle.dataset.resolvedTheme = dark ? 'dark' : 'light';
    themeSystem.disabled = activeTheme === 'system';
    themeSystem.textContent = translateText(activeTheme === 'system' ? 'theme.usingSystem' : 'theme.useSystem') ||
        (activeTheme === 'system' ? 'Following device appearance' : 'Use device appearance');
}

themeToggle.addEventListener('click', () => setTheme(getResolvedTheme() === 'dark' ? 'light' : 'dark'));
themeSystem.addEventListener('click', () => setTheme('system'));

function toggleAllFAQ() {
    const btn = document.getElementById('faq-toggle-btn');
    const details = document.querySelectorAll('details.faq-item');

    const isExpanding = btn.dataset.expanded !== 'true';

    details.forEach(detail => {
        if (isExpanding) {
            detail.setAttribute('open', '');
        } else {
            detail.removeAttribute('open');
        }
    });

    btn.dataset.expanded = isExpanding ? 'true' : 'false';
    updateFaqToggleLabel();
}

async function copyTextToClipboard(text) {
    if (!text) return false;

    if (navigator.clipboard && window.isSecureContext) {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch (error) {
            // Fall through to legacy copy method.
        }
    }

    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.setAttribute('readonly', '');
    textArea.style.position = 'fixed';
    textArea.style.top = '-9999px';
    textArea.style.opacity = '0';
    document.body.appendChild(textArea);
    textArea.select();
    textArea.setSelectionRange(0, textArea.value.length);

    let copied = false;
    try {
        copied = document.execCommand('copy');
    } catch (error) {
        copied = false;
    }

    document.body.removeChild(textArea);
    return copied;
}

document.querySelectorAll('.copy-command-btn').forEach((button) => {
    button.addEventListener('click', async () => {
        const command = button.dataset.copyText;
        if (!command) return;

        const defaultLabel = translateText('actions.copy');
        button.dataset.defaultLabel = defaultLabel;

        const copied = await copyTextToClipboard(command);
        button.textContent = copied ? translateText('actions.copied') : translateText('actions.copyFailed');

        if (button._copyResetTimer) {
            window.clearTimeout(button._copyResetTimer);
        }

        button._copyResetTimer = window.setTimeout(() => {
            button.textContent = translateText('actions.copy');
        }, 1400);
    });
});

// Initialize Language
setLanguage(initialLanguagePreference, { persist: false, announce: false });

if (languageSelect) {
    languageSelect.addEventListener('change', () => {
        setLanguage(languageSelect.value, { persist: true, announce: true });
    });
}

window.ShortcutCycleI18n = {
    setLanguage: (language) => setLanguage(language, { persist: true, announce: false }),
    getLanguage: () => currentLanguage,
    clearSavedLanguage,
    normalizeLanguage
};

// Initialize Theme
const initialTheme = getStoredTheme();
setTheme(initialTheme, false);

Object.entries(screenshotThemeBtns).forEach(([theme, btn]) => {
    if (!btn) return;

    btn.addEventListener('click', () => {
        applyScreenshotTheme(theme, { lock: true, announce: true });
    });

    btn.addEventListener('mouseenter', () => {
        if (!desktopHoverMedia.matches) return;
        applyScreenshotTheme(theme, { lock: true, announce: false });
    });
});

function handleSystemThemeChange() {
    updateControls(html.dataset.theme || 'system');
    syncScreenshotThemeWithPage();
}

if (typeof prefersDarkMedia.addEventListener === 'function') {
    prefersDarkMedia.addEventListener('change', handleSystemThemeChange);
} else if (typeof prefersDarkMedia.addListener === 'function') {
    prefersDarkMedia.addListener(handleSystemThemeChange);
}

// --- Gallery Buttons Interaction ---
const galleryScroller = document.querySelector('.gallery-scroller');
const prevBtn = document.getElementById('gallery-prev');
const nextBtn = document.getElementById('gallery-next');

if (galleryScroller && prevBtn && nextBtn) {
    const screenshots = Array.from(galleryScroller.querySelectorAll('.screenshot-frame'));

    function getCurrentIndex() {
        const scrollLeft = galleryScroller.scrollLeft;
        const scrollerRect = galleryScroller.getBoundingClientRect();
        const scrollerCenter = scrollerRect.left + scrollerRect.width / 2;

        let closestIndex = 0;
        let minDistance = Infinity;

        screenshots.forEach((screenshot, index) => {
            const rect = screenshot.getBoundingClientRect();
            const center = rect.left + rect.width / 2;
            const distance = Math.abs(center - scrollerCenter);

            if (distance < minDistance) {
                minDistance = distance;
                closestIndex = index;
            }
        });

        return closestIndex;
    }

    prevBtn.addEventListener('click', () => {
        const currentIndex = getCurrentIndex();
        const prevIndex = currentIndex === 0 ? screenshots.length - 1 : currentIndex - 1;

        screenshots[prevIndex].scrollIntoView({
            behavior: 'smooth',
            block: 'nearest',
            inline: 'center'
        });
    });

    nextBtn.addEventListener('click', () => {
        const currentIndex = getCurrentIndex();
        const nextIndex = currentIndex === screenshots.length - 1 ? 0 : currentIndex + 1;

        screenshots[nextIndex].scrollIntoView({
            behavior: 'smooth',
            block: 'nearest',
            inline: 'center'
        });
    });
}

// --- Back to Top Button ---
const backToTopBtn = document.getElementById('backToTop');

window.addEventListener('scroll', () => {
    if (window.scrollY > 300) {
        backToTopBtn.classList.add('visible');
    } else {
        backToTopBtn.classList.remove('visible');
    }
});

backToTopBtn.addEventListener('click', () => {
    window.scrollTo({
        top: 0,
        behavior: 'smooth'
    });
});
