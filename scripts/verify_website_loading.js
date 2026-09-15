// Run in a freshly loaded English page with agent-browser eval --stdin.
(async () => {
    const originalFetch = window.fetch;
    const select = document.getElementById('language-select');
    const status = document.getElementById('language-status');
    const gates = new Map();
    const requests = [];
    const check = (condition, message) => { if (!condition) throw new Error(message); };
    const choose = language => {
        select.value = language;
        select.dispatchEvent(new Event('change', { bubbles: true }));
    };
    const settle = async () => {
        const deadline = Date.now() + 12000;
        while (select.getAttribute('aria-busy') === 'true' && Date.now() < deadline) {
            await new Promise(resolve => setTimeout(resolve, 20));
        }
        check(select.getAttribute('aria-busy') === 'false', 'Loading state did not finish');
    };
    try {
        await ShortcutCycleI18n.setLanguage('en');
        window.fetch = async (url, options) => {
            const language = String(url).split('/').pop().replace('.json', '');
            requests.push(language);
            const response = await originalFetch(url, options);
            if (['fr', 'de', 'ja'].includes(language)) {
                await new Promise(resolve => gates.set(language, resolve));
            }
            if (language === 'it') {
                await new Promise((resolve, reject) => {
                    options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
                });
            }
            if (language === 'nl') throw new Error('Simulated offline');
            return response;
        };
        const waitForGate = async language => {
            const deadline = Date.now() + 5000;
            while (!gates.has(language) && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
            check(gates.has(language), `No pending request for ${language}`);
        };
        choose('fr');
        check(select.getAttribute('aria-busy') === 'true' && !status.hidden, 'Missing immediate loading feedback');
        check(!select.disabled && document.documentElement.lang === 'en', 'Picker locked or previous copy replaced early');
        check(status.textContent === 'Loading translation…', 'Loading message is not in the current language');
        await waitForGate('fr');
        gates.get('fr')();
        await settle();
        check(status.hidden && document.documentElement.lang === 'fr', 'Successful load did not clear feedback');

        choose('de');
        await waitForGate('de');
        choose('ja');
        await waitForGate('ja');
        gates.get('de')();
        await new Promise(resolve => setTimeout(resolve, 30));
        check(select.getAttribute('aria-busy') === 'true' && !status.hidden, 'Old request cleared newer loading feedback');
        gates.get('ja')();
        await settle();
        check(document.documentElement.lang === 'ja', 'Latest selection did not win');

        choose('it');
        check(status.textContent === '翻訳を読み込み中…', 'Loading text did not follow the current language');
        await settle();
        check(document.documentElement.lang === 'ja' && select.value === 'ja', 'Timeout lost the previous language');
        check(!status.hidden && status.textContent !== '翻訳を読み込み中…', 'Timeout did not show a failure message');
        choose('nl');
        await settle();
        check(select.value === 'ja' && !status.hidden, 'Failed load did not restore selection and show feedback');
        const requestCount = requests.length;
        choose('fr');
        check(select.getAttribute('aria-busy') === 'false' && status.hidden, 'Cached selection shows loading feedback');
        await new Promise(resolve => setTimeout(resolve, 0));
        check(document.documentElement.lang === 'fr' && requests.length === requestCount, 'Cached selection fetched again');
        window.fetch = originalFetch;
        choose('nl');
        await settle();
        check(document.documentElement.lang === 'nl' && status.hidden, 'Retry did not recover after failure');
        return 'PASS: immediate feedback, usable picker, current-language status, success, stale requests, timeout, failure, cache, and retry';
    } finally {
        window.fetch = originalFetch;
        for (const release of gates.values()) release();
    }
})()
