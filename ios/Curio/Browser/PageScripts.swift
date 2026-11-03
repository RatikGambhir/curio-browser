import Foundation

/// JavaScript run in pages. Everything here executes in Curio's own isolated
/// content world, so page scripts can neither see nor tamper with it; the
/// page bridge additionally tags every message with a per-session token and
/// the native side validates each field.
nonisolated enum PageScripts {
    /// Reports text selection, favicon/theme color and scroll position.
    static func bridge(token: String) -> String {
        let quoted = (try? String(data: JSONEncoder().encode(token), encoding: .utf8)) ?? "\"\""
        return bridgeTemplate.replacingOccurrences(of: "__CURIO_TOKEN__", with: quoted)
    }

    private static let bridgeTemplate = #"""
    (() => {
      if (window.__curioBridgeInstalled) return;
      window.__curioBridgeInstalled = true;
      const TOKEN = __CURIO_TOKEN__;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.curio;
      const send = (type, payload) => {
        if (!handler) return;
        try { handler.postMessage(Object.assign({ token: TOKEN, type }, payload || {})); } catch (_) {}
      };

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
          send('selection', { text });
        }, 220);
      });

      // Favicon and theme color. SVG icons can't be drawn natively, so the
      // largest bitmap icon wins.
      const reportMeta = () => {
        const icons = Array.from(document.querySelectorAll(
          'link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"], link[rel="shortcut icon"]'));
        const score = (l) => {
          const svg = (l.type || '').includes('svg') || /\.svg(\?|$)/i.test(l.href);
          if (svg) return -1;
          const size = parseInt((l.getAttribute('sizes') || '0').split('x')[0], 10) || 0;
          const touch = /apple-touch-icon/.test(l.rel) ? 180 : 0;
          return Math.min(Math.max(size, touch), 256);
        };
        const usable = icons.filter((l) => l.href && score(l) >= 0).sort((a, b) => score(b) - score(a));
        const theme = document.querySelector('meta[name="theme-color"]');
        send('meta', {
          favicon: usable.length ? usable[0].href : null,
          themeColor: theme ? theme.content : null,
        });
      };
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', reportMeta, { once: true });
      } else {
        reportMeta();
      }
      window.addEventListener('load', reportMeta, { once: true });

      // Scroll position, so sleeping tabs come back where they were.
      let scrollTimer = 0;
      window.addEventListener('scroll', () => {
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(() => send('scroll', { y: window.scrollY }), 500);
      }, { passive: true });
    })();
    """#

    /// Extracts readable page content for the assistant as JSON matching
    /// `PageContext`. Run only when the user shares the page.
    static let extractContent = #"""
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
      const holder = document.createElement('div');
      holder.style.cssText = 'position:absolute;left:-99999px;top:0;width:900px;opacity:0;pointer-events:none;';
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
    """#

    /// Highlights matches of `query`, scrolls to the active one and returns
    /// `{"matches":n,"active":i}` as JSON.
    static func find(_ query: String, forward: Bool) -> String {
        let quoted = (try? String(data: JSONEncoder().encode(query), encoding: .utf8)) ?? "\"\""
        return findTemplate
            .replacingOccurrences(of: "__QUERY__", with: quoted)
            .replacingOccurrences(of: "__FORWARD__", with: forward ? "true" : "false")
    }

    private static let findTemplate = #"""
    (() => {
      const query = __QUERY__;
      const forward = __FORWARD__;
      const state = window.__curioFind || (window.__curioFind = { query: null, ranges: [], index: -1, marks: [] });
      const clearMarks = () => { for (const m of state.marks) m.remove(); state.marks = []; };
      clearMarks();
      if (!query) { state.query = null; state.ranges = []; state.index = -1; return JSON.stringify({ matches: 0, active: 0 }); }
      if (state.query !== query) {
        state.query = query; state.ranges = []; state.index = -1;
        const needle = query.toLowerCase();
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
          acceptNode(node) {
            const p = node.parentElement;
            if (!p || /^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA)$/.test(p.tagName)) return NodeFilter.FILTER_REJECT;
            const cs = getComputedStyle(p);
            return cs.display === 'none' || cs.visibility === 'hidden' ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
          }
        });
        let node;
        while ((node = walker.nextNode()) && state.ranges.length < 1000) {
          const hay = node.data.toLowerCase();
          let i = hay.indexOf(needle);
          while (i !== -1 && state.ranges.length < 1000) {
            const r = document.createRange();
            r.setStart(node, i); r.setEnd(node, i + query.length);
            state.ranges.push(r);
            i = hay.indexOf(needle, i + needle.length);
          }
        }
      }
      const n = state.ranges.length;
      if (n === 0) return JSON.stringify({ matches: 0, active: 0 });
      state.index = forward ? (state.index + 1) % n : (state.index - 1 + n) % n;
      const active = state.ranges[state.index];
      const el = active.startContainer.parentElement;
      if (el && el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'nearest' });
      const draw = () => {
        clearMarks();
        const sx = window.scrollX, sy = window.scrollY;
        state.ranges.forEach((r, i) => {
          for (const rect of r.getClientRects()) {
            const m = document.createElement('div');
            m.style.cssText = 'position:absolute;pointer-events:none;z-index:2147483647;border-radius:3px;' +
              'left:' + (rect.left + sx - 1) + 'px;top:' + (rect.top + sy - 1) + 'px;' +
              'width:' + (rect.width + 2) + 'px;height:' + (rect.height + 2) + 'px;' +
              (i === state.index ? 'background:rgba(255,150,30,.55);box-shadow:0 0 0 1px rgba(200,100,0,.6);'
                                 : 'background:rgba(255,220,60,.38);');
            document.documentElement.appendChild(m);
            state.marks.push(m);
          }
        });
      };
      requestAnimationFrame(draw);
      return JSON.stringify({ matches: n, active: state.index + 1 });
    })()
    """#

    static let clearFind = "(() => { const s = window.__curioFind; if (s) { for (const m of s.marks) m.remove(); s.marks = []; s.query = null; s.ranges = []; s.index = -1; } })()"

    /// Restores a saved scroll offset once the document has laid out.
    static func restoreScroll(_ y: Double) -> String {
        let y = y.isFinite ? max(y, 0) : 0
        return "(() => { const go = () => window.scrollTo(0, \(y)); if (document.readyState === 'complete') go(); else window.addEventListener('load', go, { once: true }); })()"
    }
}
