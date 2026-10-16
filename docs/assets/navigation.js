// Progressive enhancement: native links stay available if this script cannot run.
(() => {
    const header = document.querySelector('.site-header');
    const control = header?.querySelector('.menu-toggle');
    const panel = header?.querySelector('.mobile-panel');
    const desktop = header?.querySelector('.desktop-controls, .desktop-nav');
    if (!control || !panel || !desktop) return;
    const compact = window.matchMedia('(max-width: 900px)');
    const listeners = new AbortController();
    const options = { signal: listeners.signal };
    let lastHeaderFocus = null;

    function close(returnFocus = false) {
        const wasOpen = !panel.hidden;
        panel.hidden = true;
        control.setAttribute('aria-expanded', 'false');
        if (wasOpen && returnFocus) control.focus();
    }

    function sync() {
        // Chromium can blur a control as CSS hides it before the media event runs.
        const active = document.activeElement === document.body ? lastHeaderFocus : document.activeElement;
        const inPanel = panel.contains(active);
        const inDesktop = desktop.contains(active);
        const href = active?.getAttribute('href');
        const languageFocused = active?.matches('select');
        const menuFocused = active === control;
        close();
        control.hidden = !compact.matches;
        if (compact.matches && (inPanel || inDesktop)) control.focus();
        else if (!compact.matches && (inPanel || menuFocused)) {
            const destination = languageFocused ? desktop.querySelector('select') :
                [...desktop.querySelectorAll('a')].find(link => link.getAttribute('href') === href);
            (destination || desktop.querySelector('a'))?.focus();
        }
    }

    control.addEventListener('click', () => {
        panel.hidden = !panel.hidden;
        control.setAttribute('aria-expanded', String(!panel.hidden));
    }, options);
    document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && !panel.hidden) {
            event.preventDefault();
            close(true);
        }
    }, options);
    document.addEventListener('click', event => {
        if (!header.contains(event.target)) {
            lastHeaderFocus = null;
            close();
        }
    }, options);
    header.addEventListener('focusin', event => { lastHeaderFocus = event.target; }, options);
    document.addEventListener('focusin', event => {
        if (event.target !== document.body && !header.contains(event.target)) lastHeaderFocus = null;
    }, options);
    header.addEventListener('focusout', event => {
        if (event.relatedTarget && !header.contains(event.relatedTarget)) close();
    }, options);
    panel.addEventListener('click', event => {
        if (!(event.target instanceof Element)) return;
        const link = event.target.closest('a');
        if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button) return;
        const target = new URL(link.href);
        close(link.target === '_blank' || target.origin !== location.origin);
        if (target.origin === location.origin && target.pathname === location.pathname &&
            target.search === location.search && target.hash) {
            const destination = document.getElementById(target.hash.slice(1));
            if (destination) {
                destination.tabIndex = -1;
                destination.focus({ preventScroll: true });
            }
        }
    }, options);
    compact.addEventListener('change', sync, options);
    window.addEventListener('popstate', sync, options);
    window.addEventListener('pageshow', event => { if (event.persisted) sync(); }, options);
    sync();

    return () => {
        listeners.abort();
        control.hidden = true;
        panel.hidden = false;
    };
})();
