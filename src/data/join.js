// Join screen: each player picks a name and a few settings before the game
// starts. Everything is stored in this browser only (localStorage), so
// players never affect each other. Values are passed to the engine as
// +set arguments ahead of +connect.
(function () {
  'use strict';
  var KEY = 'cz-quake3-player';
  var COLORS = [
    ['', 'Default (white)'], ['1', 'Red'], ['2', 'Green'], ['3', 'Yellow'],
    ['4', 'Blue'], ['5', 'Cyan'], ['6', 'Magenta'],
  ];

  function load() {
    try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; }
  }
  function save(p) {
    try { localStorage.setItem(KEY, JSON.stringify(p)); } catch (e) { /* private mode */ }
  }
  // Quake names: printable ASCII, no quotes/semicolons/backslashes/percent
  // (userinfo and command separators), no color codes typed by hand.
  function cleanName(s) {
    return String(s || '').replace(/[^\x20-\x7e]/g, '').replace(/["\\;%^]/g, '')
      .replace(/\s+/g, ' ').trim().slice(0, 28);
  }
  function num(v, lo, hi) {
    var n = parseFloat(v);
    return isFinite(n) && n >= lo && n <= hi ? String(Math.round(n * 100) / 100) : null;
  }
  function el(tag, attrs, kids) {
    var e = document.createElement(tag);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    (kids || []).forEach(function (c) { e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c); });
    return e;
  }

  function show() {
    var p = load();
    var name = el('input', { id: 'j-name', maxlength: '28', autocomplete: 'off', placeholder: 'Your name' });
    name.value = p.name || '';
    var color = el('select', { id: 'j-color' });
    COLORS.forEach(function (c) {
      var o = el('option', { value: c[0] }, [c[1]]);
      if ((p.color || '') === c[0]) o.selected = true;
      color.appendChild(o);
    });
    var sens = el('input', { id: 'j-sens', type: 'number', min: '0.5', max: '20', step: '0.5' });
    sens.value = p.sens || '5';
    var fov = el('input', { id: 'j-fov', type: 'number', min: '80', max: '130', step: '5' });
    fov.value = p.fov || '100';
    var err = el('div', { id: 'j-err' });
    var go = el('button', { type: 'submit' }, ['Play']);

    var form = el('form', { id: 'j-form' }, [
      el('h1', {}, ['Quake 3 Arena']),
      el('label', { for: 'j-name' }, ['Player name']), name,
      el('label', { for: 'j-color' }, ['Name color']), color,
      el('div', { class: 'j-row' }, [
        el('div', {}, [el('label', { for: 'j-sens' }, ['Mouse sensitivity']), sens]),
        el('div', {}, [el('label', { for: 'j-fov' }, ['Field of view']), fov]),
      ]),
      err, go,
      el('p', { class: 'j-note' }, [
        'Saved in this browser only. Esc opens the game menu for more settings; ',
        'the ` key opens the console.',
      ]),
    ]);
    var overlay = el('div', { id: 'j-overlay' }, [form]);
    document.body.appendChild(overlay);
    name.focus();

    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      var n = cleanName(name.value);
      if (!n) { err.textContent = 'Enter a name (letters, numbers, spaces).'; return; }
      var s = num(sens.value, 0.5, 20), f = num(fov.value, 80, 130);
      var player = { name: n, color: color.value, sens: s || '5', fov: f || '100' };
      save(player);
      var args = ['+set', 'name', (player.color ? '^' + player.color : '') + n];
      if (s) args.push('+set', 'sensitivity', s);
      if (f) args.push('+set', 'cg_fov', f);
      go.disabled = true;
      // Start the client in the server's game dir (see web.js).
      fetch('/server.json', { cache: 'no-store' }).then(function (r) { return r.json(); })
        .catch(function () { return {}; })
        .then(function (info) {
          if (info && /^[a-z0-9_]+$/.test(info.game || '')) args.unshift('+set', 'fs_game', info.game);
          overlay.parentNode.removeChild(overlay);
          window.q3launch(args);
        });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', show);
  } else {
    show();
  }
})();
