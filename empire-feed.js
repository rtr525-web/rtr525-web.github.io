/* Empire live feed loader.
 *
 * The GitHub Pages HTML carries a baked-in snapshot of every dynamic
 * region (the static fallback). This script fetches the live feed JSON
 * and, only on success, swaps each region's content for the feed's
 * version. If the fetch fails for any reason, the page simply keeps
 * showing the baked snapshot — nothing breaks, nothing blanks.
 *
 * Feed URL resolution:
 *   1. window.EMPIRE_FEED_URL — set by an inline config script on the
 *      page (production: the Dropbox direct-download URL).
 *   2. 'empire-feed.json' relative to the site root — local testing and
 *      same-host fallback.
 * A cache-busting query is appended so a refreshed feed is never served
 * stale by a CDN cache.
 */
(function () {
  var ROOT_REL = (window.EMPIRE_FEED_ROOT || '');
  var url = window.EMPIRE_FEED_URL || (ROOT_REL + 'empire-feed.json');
  url += (url.indexOf('?') === -1 ? '?' : '&') + 'v=' + Date.now();

  function setHTML(id, html) {
    var el = document.getElementById(id);
    if (el && typeof html === 'string') el.innerHTML = html;
  }
  function setText(id, text) {
    var el = document.getElementById(id);
    if (el && typeof text === 'string') el.textContent = text;
  }

  fetch(url, { cache: 'no-store' }).then(function (r) {
    if (!r.ok) throw new Error('feed status ' + r.status);
    return r.json();
  }).then(function (feed) {
    var rg = feed.regions || {};
    // Hub regions (ids added by the page conversion; absent ids are
    // skipped, so this same file is safe on every page).
    setHTML('feedStatusbar', rg.statusbar);
    setHTML('feedTicker', rg.ticker);
    setHTML('feedTotals', rg.totals);
    setHTML('top-movers', rg.movers);
    setHTML('daily-updates', rg.daily_updates);
    setHTML('cardsView', rg.directory);
    setHTML('recent-changes', rg.changes);
    setHTML('rawView', rg.raw);
    setText('feedHeroline', feed.hero_line);
    setText('feedFooterline', feed.footer_line);
    // Root front door: only its status line is dynamic.
    setText('feedRootStatus', feed.status_line ? '● ' + feed.status_line : null);
    document.documentElement.setAttribute('data-feed-applied', feed.generated_at || 'yes');
  }).catch(function () {
    /* Static fallback stays in place. */
    document.documentElement.setAttribute('data-feed-applied', 'fallback');
  });
})();
