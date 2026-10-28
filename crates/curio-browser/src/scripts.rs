//! JavaScript injected into web pages.
//!
//! Pages are untrusted. The bridge script runs before page scripts in the
//! main frame only. It captures `ipc.postMessage` and `JSON.stringify` at
//! startup, so a page cannot intercept later calls, and tags every message
//! with a per-session random token. The native side drops messages without the
//! token and validates every field, so a page can at most send the same
//! benign messages its user could trigger (open a link, report a selection).

/// Builds the bridge script for a session token and the keystrokes that
/// should be forwarded to Curio when the page has keyboard focus.
#[must_use]
pub fn bridge_script(token: &str, forwarded_keys: &[String]) -> String {
    let keys = serde_json::to_string(forwarded_keys).unwrap_or_else(|_| "[]".to_owned());
    let token = serde_json::to_string(token).unwrap_or_else(|_| "\"\"".to_owned());
    BRIDGE_TEMPLATE
        .replace("__CURIO_TOKEN__", &token)
        .replace("__CURIO_KEYS__", &keys)
}

const BRIDGE_TEMPLATE: &str = r#"
(() => {
  if (window.__curioBridgeInstalled) return;
  Object.defineProperty(window, '__curioBridgeInstalled', { value: true });
  const TOKEN = __CURIO_TOKEN__;
  const KEYS = new Set(__CURIO_KEYS__);
  const ipc = window.ipc;
  const post = ipc && typeof ipc.postMessage === 'function' ? ipc.postMessage.bind(ipc) : null;
  const stringify = JSON.stringify;
  const send = (type, payload) => {
    if (!post) return;
    try { post(stringify(Object.assign({ token: TOKEN, type }, payload || {}))); } catch (_) {}
  };

  // Links opened with Cmd/Ctrl-click or the middle button go to a new tab.
  const linkFrom = (event) => {
    const path = event.composedPath ? event.composedPath() : [];
    for (const node of path) {
      if (node && node.tagName === 'A' && node.href) return node;
    }
    return null;
  };
  const openLink = (event, background) => {
    const link = linkFrom(event);
    if (!link || !/^https?:/i.test(link.href)) return;
    event.preventDefault();
    event.stopPropagation();
    send('open', { url: link.href, background });
  };
  document.addEventListener('click', (e) => {
    if (e.button === 0 && (e.metaKey || e.ctrlKey)) openLink(e, !e.shiftKey);
  }, true);
  document.addEventListener('auxclick', (e) => {
    if (e.button === 1) openLink(e, true);
  }, true);

  // Text selection, for "Ask Curio" actions.
  let selectionTimer = 0;
  let lastSelection = '';
  document.addEventListener('selectionchange', () => {
    clearTimeout(selectionTimer);
    selectionTimer = setTimeout(() => {
      const selection = window.getSelection();
      const text = selection ? String(selection).trim().slice(0, 20000) : '';
      if (text === lastSelection) return;
      lastSelection = text;
      let rect = null;
      if (text && selection.rangeCount) {
        const r = selection.getRangeAt(0).getBoundingClientRect();
        rect = { x: r.left, y: r.top, width: r.width, height: r.height };
      }
      send('selection', { text, rect });
    }, 220);
  });

  // Favicon and theme color.
  const reportMeta = () => {
    const icons = Array.from(document.querySelectorAll(
      'link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="shortcut icon"]'));
    const score = (l) => {
      const size = parseInt((l.getAttribute('sizes') || '0').split('x')[0], 10) || 0;
      const svg = (l.type || '').includes('svg') || /\.svg(\?|$)/i.test(l.href) ? 1000 : 0;
      return svg + Math.min(size, 128);
    };
    icons.sort((a, b) => score(b) - score(a));
    const theme = document.querySelector('meta[name="theme-color"]');
    send('meta', {
      favicon: icons.length ? icons[0].href : null,
      themeColor: theme ? theme.content : null,
    });
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', reportMeta, { once: true });
  } else {
    reportMeta();
  }
  window.addEventListener('load', reportMeta, { once: true });

  // Scroll position, so sleeping tabs can be restored where they were.
  let scrollTimer = 0;
  window.addEventListener('scroll', () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => send('scroll', { y: window.scrollY }), 500);
  }, { passive: true });

  // URL changes in single-page apps.
  const reportUrl = () => send('url', { url: location.href, title: document.title });
  for (const name of ['pushState', 'replaceState']) {
    const original = history[name];
    history[name] = function (...args) {
      const result = original.apply(this, args);
      setTimeout(reportUrl, 0);
      return result;
    };
  }
  window.addEventListener('popstate', reportUrl);
  window.addEventListener('hashchange', reportUrl);

  // Browser shortcuts pressed while the page has focus.
  const KEY_NAMES = {
    BracketLeft: '[', BracketRight: ']', Comma: ',', Period: '.', Slash: '/',
    Backslash: '\\', Semicolon: ';', Quote: "'", Minus: '-', Equal: '=',
    ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down',
    Enter: 'enter', Tab: 'tab', Escape: 'escape', Backquote: '`',
  };
  document.addEventListener('keydown', (e) => {
    if (!(e.metaKey || e.ctrlKey || e.altKey) && e.key !== 'Escape') return;
    let key = KEY_NAMES[e.code];
    if (!key && e.code.startsWith('Key')) key = e.code.slice(3).toLowerCase();
    if (!key && e.code.startsWith('Digit')) key = e.code.slice(5);
    if (!key) return;
    const stroke = (e.ctrlKey ? 'ctrl-' : '') + (e.altKey ? 'alt-' : '') +
      (e.shiftKey ? 'shift-' : '') + (e.metaKey ? 'cmd-' : '') + key;
    if (KEYS.has(stroke)) {
      e.preventDefault();
      e.stopPropagation();
      send('key', { keystroke: stroke });
    }
  }, true);
})();
"#;

/// Extracts readable page content for the AI assistant. Evaluated on demand
/// (only when the user shares the page), never in the background. Returns a
/// JSON string matching `curio_ai::PageContext`.
pub const EXTRACT_CONTENT: &str = r#"
(() => {
  const clean = (s) => (s || '').replace(/[ \t ]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  const meta = (sel) => { const m = document.querySelector(sel); return m ? (m.content || '').trim() : ''; };
  const description = meta('meta[name="description"]') || meta('meta[property="og:description"]');
  const metadata = [];
  const add = (k, v) => { if (v) metadata.push([k, v.slice(0, 300)]); };
  add('Site', meta('meta[property="og:site_name"]'));
  add('Author', meta('meta[name="author"]') || meta('meta[property="article:author"]'));
  add('Published', meta('meta[property="article:published_time"]') || meta('meta[name="date"]'));
  add('Language', document.documentElement.lang || '');

  // Pick the most content-like container: an <article>/<main> or the element
  // with the most paragraph text.
  const candidates = Array.from(document.querySelectorAll('article, main, [role="main"]'));
  let root = candidates.sort((a, b) => b.innerText.length - a.innerText.length)[0];
  if (!root || root.innerText.length < 400) {
    let best = document.body, bestScore = 0;
    for (const el of document.querySelectorAll('div, section')) {
      const ps = el.querySelectorAll(':scope > p, :scope > pre, :scope > ul, :scope > ol, :scope > h2, :scope > h3');
      let score = 0;
      for (const p of ps) score += (p.innerText || '').length;
      if (score > bestScore) { best = el; bestScore = score; }
    }
    root = bestScore > 400 ? best : document.body;
  }
  const clone = root ? root.cloneNode(true) : document.createElement('div');
  for (const el of clone.querySelectorAll(
    'script, style, noscript, template, svg, canvas, iframe, nav, footer, form, button, input, select, textarea, [aria-hidden="true"], [hidden]')) {
    el.remove();
  }
  // innerText needs layout; attach the clone off-screen to measure it.
  const holder = document.createElement('div');
  holder.style.cssText = 'position:fixed;left:-99999px;top:0;width:900px;visibility:hidden;';
  holder.appendChild(clone);
  (document.body || document.documentElement).appendChild(holder);
  let text = clone.innerText || clone.textContent || '';
  holder.remove();
  if (clean(text).length < 200 && document.body) text = document.body.innerText || '';

  const selection = window.getSelection ? String(window.getSelection()).trim() : '';
  return JSON.stringify({
    title: document.title || '',
    url: location.href,
    description,
    text: clean(text).slice(0, 400000),
    selection: selection.slice(0, 20000),
    metadata,
  });
})()
"#;

/// Builds a find-in-page script. Highlights all matches of `query` with
/// overlay marks, scrolls to the active one and returns
/// `{"matches":n,"active":i}` as a JSON string.
#[must_use]
pub fn find_script(query: &str, forward: bool, case_sensitive: bool) -> String {
    let query = serde_json::to_string(query).unwrap_or_else(|_| "\"\"".to_owned());
    format!(
        r#"(() => {{
  const query = {query};
  const forward = {forward};
  const caseSensitive = {case_sensitive};
  const state = window.__curioFind || (window.__curioFind = {{ query: null, ranges: [], index: -1, marks: [] }});
  const clearMarks = () => {{ for (const m of state.marks) m.remove(); state.marks = []; }};
  clearMarks();
  if (!query) {{ state.query = null; state.ranges = []; state.index = -1; return JSON.stringify({{ matches: 0, active: 0 }}); }}
  if (state.query !== query || state.caseSensitive !== caseSensitive) {{
    state.query = query; state.caseSensitive = caseSensitive; state.ranges = []; state.index = -1;
    const needle = caseSensitive ? query : query.toLowerCase();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {{
      acceptNode(node) {{
        const p = node.parentElement;
        if (!p || /^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA)$/.test(p.tagName)) return NodeFilter.FILTER_REJECT;
        const cs = getComputedStyle(p);
        return cs.display === 'none' || cs.visibility === 'hidden' ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }}
    }});
    let node;
    while ((node = walker.nextNode()) && state.ranges.length < 1000) {{
      const hay = caseSensitive ? node.data : node.data.toLowerCase();
      let i = hay.indexOf(needle);
      while (i !== -1 && state.ranges.length < 1000) {{
        const r = document.createRange();
        r.setStart(node, i); r.setEnd(node, i + query.length);
        state.ranges.push(r);
        i = hay.indexOf(needle, i + needle.length);
      }}
    }}
  }}
  const n = state.ranges.length;
  if (n === 0) return JSON.stringify({{ matches: 0, active: 0 }});
  state.index = forward ? (state.index + 1) % n : (state.index - 1 + n) % n;
  const active = state.ranges[state.index];
  const el = active.startContainer.parentElement;
  if (el && el.scrollIntoView) el.scrollIntoView({{ block: 'center', inline: 'nearest' }});
  const draw = () => {{
    clearMarks();
    const sx = window.scrollX, sy = window.scrollY;
    state.ranges.forEach((r, i) => {{
      for (const rect of r.getClientRects()) {{
        const m = document.createElement('div');
        m.style.cssText = 'position:absolute;pointer-events:none;z-index:2147483647;border-radius:3px;' +
          'left:' + (rect.left + sx - 1) + 'px;top:' + (rect.top + sy - 1) + 'px;' +
          'width:' + (rect.width + 2) + 'px;height:' + (rect.height + 2) + 'px;' +
          (i === state.index ? 'background:rgba(255,150,30,.55);box-shadow:0 0 0 1px rgba(200,100,0,.6);'
                             : 'background:rgba(255,220,60,.38);');
        document.documentElement.appendChild(m);
        state.marks.push(m);
      }}
    }});
  }};
  requestAnimationFrame(draw);
  return JSON.stringify({{ matches: n, active: state.index + 1 }});
}})()"#
    )
}

/// Removes find-in-page highlights.
pub const CLEAR_FIND: &str = r"(() => { const s = window.__curioFind; if (s) { for (const m of s.marks) m.remove(); s.marks = []; s.query = null; s.ranges = []; s.index = -1; } })()";

/// Restores a saved scroll offset once the document has laid out.
#[must_use]
pub fn restore_scroll_script(y: f64) -> String {
    let y = if y.is_finite() { y.max(0.0) } else { 0.0 };
    format!(
        "(() => {{ const go = () => window.scrollTo(0, {y}); \
         if (document.readyState === 'complete') go(); else window.addEventListener('load', go, {{ once: true }}); }})()"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_embeds_token_and_keys_as_json() {
        let script = bridge_script("abc\"def", &["cmd-t".into()]);
        assert!(script.contains(r#"const TOKEN = "abc\"def";"#));
        assert!(script.contains(r#"new Set(["cmd-t"])"#));
        assert!(!script.contains("__CURIO_"));
    }

    #[test]
    fn find_script_escapes_query() {
        let script = find_script("</script>\"'", true, false);
        assert!(script.contains(r#"const query = "</script>\"'";"#));
    }

    #[test]
    fn restore_scroll_ignores_non_finite_values() {
        assert!(restore_scroll_script(f64::NAN).contains("scrollTo(0, 0)"));
        assert!(restore_scroll_script(-5.0).contains("scrollTo(0, 0)"));
    }
}
