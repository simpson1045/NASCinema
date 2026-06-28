'use strict';

const context = cast.framework.CastReceiverContext.getInstance();
const pm = context.getPlayerManager();

// Custom control channel — the phone remote toggles the TV stats overlay here.
const NS = 'urn:x-cast:com.nascinema.control';

const $ = (id) => document.getElementById(id);
const els = {
  backdrop: $('backdrop'),
  overlay: $('overlay'),
  clearlogo: $('clearlogo'),
  title: $('title'),
  meta: $('meta'),
  fill: $('fill'),
  elapsed: $('elapsed'),
  remaining: $('remaining'),
  eta: $('eta'),
  pausedTag: $('paused-tag'),
  pausedLogo: $('paused-logo'),
  pausedTitle: $('paused-title'),
  stats: $('stats'),
  clock: $('clock'),
  idle: $('idle'),
  idleBg: $('idle-bg'),
};

let lastBackdrop = '';

// On-screen debug log (temporary). Newest line on top.
const _dbg = [];
function dbg(msg) {
  _dbg.unshift(msg);
  if (_dbg.length > 14) _dbg.pop();
  const el = document.getElementById('debug');
  if (el) el.textContent = _dbg.join('\n');
  try { console.log('[NASC]', msg); } catch (e) {}
  // Ship it back to the backend so the TV's log is readable remotely.
  try {
    fetch('/cast/log', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ msg: msg }),
    }).catch(function () {});
  } catch (e) {}
}
dbg('receiver loaded');

// Surface any startup crash (the receiver currently dies before context.start)
// to the on-screen log + backend so we can see exactly what throws.
window.addEventListener('error', function (e) {
  dbg('JSERR: ' + (e.message || e) +
      (e.lineno ? ' @' + e.lineno + ':' + (e.colno || '') : ''));
});
window.addEventListener('unhandledrejection', function (e) {
  var r = e.reason;
  dbg('REJECT: ' + ((r && r.message) ? r.message : r));
});

function fmt(sec) {
  if (!isFinite(sec) || sec < 0) sec = 0;
  sec = Math.round(sec);
  const h = (sec / 3600) | 0;
  const m = ((sec % 3600) / 60) | 0;
  const s = sec % 60;
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

// Read metadata + customData from the LOAD and paint the overlay.
function applyMeta(media) {
  const md = media.metadata || {};
  const cd = media.customData || {};
  const title = md.title || 'Now Playing';

  els.title.textContent = title;
  els.pausedTitle.textContent = title;

  if (cd.logo) {
    els.clearlogo.src = cd.logo;
    els.clearlogo.style.display = 'block';
    els.title.style.display = 'none';
    els.pausedLogo.src = cd.logo;
    els.pausedLogo.style.display = 'block';
    els.pausedTitle.style.display = 'none';
  } else {
    els.clearlogo.style.display = 'none';
    els.title.style.display = 'block';
    els.pausedLogo.style.display = 'none';
    els.pausedTitle.style.display = 'inline';
  }

  els.meta.textContent = cd.meta || '';

  const bg = cd.backdrop || (md.images && md.images[0] && md.images[0].url) || '';
  if (bg) {
    lastBackdrop = bg;
    els.backdrop.style.backgroundImage = `url("${bg}")`;
  }

  renderStats(cd.source || {}, cd);
}

function renderStats(src, cd) {
  const rows = [];
  const v = [];
  if (src.video_codec) v.push(String(src.video_codec).toUpperCase());
  if (src.width && src.height) v.push(`${src.width}×${src.height}`);
  if (src.hdr) v.push('HDR');
  rows.push(['Stream', cd.stream || 'HLS · server transcode']);
  if (v.length) rows.push(['Source video', v.join(' · ')]);
  if (src.audio_codec) rows.push(['Source audio', String(src.audio_codec).toUpperCase()]);
  if (src.container) rows.push(['Container', String(src.container).toUpperCase()]);
  els.stats.innerHTML =
    '<div class="hdr">STATS FOR NERDS</div>' +
    rows.map((r) => `<div><span class="lbl">${r[0]}</span> &nbsp; ${r[1]}</div>`).join('');
}

function toggleStats(show) {
  els.stats.classList.toggle('hidden', !show);
}

function updateProgress() {
  const cur = pm.getCurrentTimeSec();
  const dur = pm.getDurationSec();
  if (!dur || !isFinite(dur)) return;
  els.fill.style.width = `${Math.min(100, (cur / dur) * 100)}%`;
  els.elapsed.textContent = fmt(cur);
  els.remaining.textContent = '-' + fmt(dur - cur);
  const end = new Date(Date.now() + (dur - cur) * 1000);
  const hh = end.getHours();
  const mm = String(end.getMinutes()).padStart(2, '0');
  const ampm = hh >= 12 ? 'PM' : 'AM';
  const h12 = ((hh + 11) % 12) + 1;
  els.eta.textContent = `Ends at ${h12}:${mm} ${ampm}`;
}

let _lastLoggedState = null;
function setState(state) {
  if (state !== _lastLoggedState) {
    dbg('state=' + state);
    _lastLoggedState = state;
  }
  const S = cast.framework.messages.PlayerState;
  const idle = state === S.IDLE || !state;
  els.idle.classList.toggle('hidden', !idle);
  // The clock is an art-mode touch — only show it on the idle screen, never
  // over the movie during playback.
  els.clock.classList.toggle('hidden', !idle);
  document.body.classList.toggle('paused', state === S.PAUSED || state === S.BUFFERING);
  // Park the clearlogo/title in the corner only while paused.
  els.pausedTag.classList.toggle('hidden', state !== S.PAUSED);
  if (idle && lastBackdrop) {
    els.idleBg.style.backgroundImage = `url("${lastBackdrop}")`;
    els.idleBg.classList.add('show');
  }
}

function tickClock() {
  const now = new Date();
  const hh = now.getHours();
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ampm = hh >= 12 ? 'PM' : 'AM';
  const h12 = ((hh + 11) % 12) + 1;
  els.clock.textContent = `${h12}:${mm} ${ampm}`;
}
// Wrapped in try/catch with step markers: a cross-origin throw from the CAF
// SDK shows only "Script error." in window.onerror, but a local catch gives us
// the real message — and the markers pinpoint which call throws.
try {
  dbg('init: clock');
  tickClock();
  setInterval(tickClock, 15000);

  dbg('init: interceptor');
  pm.setMessageInterceptor(cast.framework.messages.MessageType.LOAD, (req) => {
    const cid = (req.media && req.media.contentId) || '?';
    dbg('LOAD ' + String(cid).slice(0, 64));
    if (req.media) {
      applyMeta(req.media);
      // Match the web player's subtitle look: no black box, white text with a
      // black outline for readability (colors are #RRGGBBAA).
      req.media.textTrackStyle = {
        backgroundColor: '#00000000',
        foregroundColor: '#FFFFFFFF',
        edgeType: 'OUTLINE',
        edgeColor: '#000000FF',
        fontScale: 1.0,
        fontGenericFamily: 'SANS_SERIF',
      };
    }
    toggleStats(false);
    // Reliably drop the idle screen the moment media loads — otherwise the
    // opaque "Ready to cast" overlay sits on top of the video (audio plays,
    // nothing visible). Don't depend on a player-state event for this.
    setState(cast.framework.messages.PlayerState.PLAYING);
    return req;
  });

  dbg('init: listeners');
  const ET = cast.framework.events.EventType;
  dbg('evtypes PSC=' + typeof ET.PLAYER_STATE_CHANGED +
      ' TU=' + typeof ET.TIME_UPDATE + ' ERR=' + typeof ET.ERROR);
  // Defensive: an undefined EventType constant makes addEventListener throw and
  // kills the whole receiver. Skip-and-log instead so playback still works.
  function on(type, label, fn) {
    if (type === undefined || type === null) {
      dbg('listener SKIPPED (undefined type): ' + label);
      return;
    }
    pm.addEventListener(type, fn);
  }
  const PS = cast.framework.messages.PlayerState;
  dbg('media evtypes PLAYING=' + typeof ET.PLAYING + ' PAUSE=' + typeof ET.PAUSE +
      ' ENDED=' + typeof ET.ENDED + ' MEDIA_STATUS=' + typeof ET.MEDIA_STATUS);
  // PLAYER_STATE_CHANGED doesn't exist in this SDK; drive the overlay from the
  // real media-element events (and MEDIA_STATUS if present) instead.
  on(ET.MEDIA_STATUS, 'MEDIA_STATUS', (e) => {
    const s = e && e.mediaStatus && e.mediaStatus.playerState;
    if (s) setState(s);
  });
  on(ET.PLAYING, 'PLAYING', () => setState(PS.PLAYING));
  on(ET.PAUSE, 'PAUSE', () => setState(PS.PAUSED));
  on(ET.ENDED, 'ENDED', () => setState(PS.IDLE));
  on(ET.TIME_UPDATE, 'TIME_UPDATE', updateProgress);
  on(ET.ERROR, 'ERROR', (e) =>
    dbg('ERR code=' + (e.detailedErrorCode || '?') +
        (e.error ? ' ' + JSON.stringify(e.error).slice(0, 80) : '')));

  dbg('init: custom msg listener');
  context.addCustomMessageListener(NS, (e) => {
    const d = e.data || {};
    if (d.type === 'STATS') toggleStats(!!d.show);
  });

  dbg('init: setState idle');
  setState(cast.framework.messages.PlayerState.IDLE);

  dbg('init: context.start');
  context.start();
  dbg('context started (ready for LOAD)');
} catch (err) {
  dbg('INIT THREW: ' + (err && err.message ? err.message : err) +
      (err && err.stack ? ' || ' + String(err.stack).slice(0, 160) : ''));
}
