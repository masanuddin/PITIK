// ============================================================
//  Rekam event stream /controls di FIREBASE EMULATOR (lokal) — bukti TRANSPORT.
//  BUKAN untuk produksi: skrip menolak host selain 127.0.0.1/localhost dan
//  hanya memakai namespace demo-* (tanpa kredensial, tanpa internet).
//
//  Jalankan (setelah disetujui):
//    firebase emulators:start --only database --project demo-pitik \
//      --config firmware/tools/firebase.emulator.json
//    node firmware/tools/verify_stream_events.mjs [output.json]
//
//  Skrip HANYA merekam event SSE yang diterima listener /controls (seperti
//  ESP32) — eventType, path, data. Skrip TIDAK meniru parser firmware.
//  Kebijakan C++ diuji terpisah: event terekam → gen_policy_asserts.py →
//  static_assert terhadap control_stream_policy.h asli.
//
//  Catatan: REST PATCH/PUT di server = operasi merge/set yang sama dengan
//  Flutter update()/set(); SDK Flutter sendiri memakai WebSocket, bukan REST.
// ============================================================

import { writeFileSync } from 'node:fs';

const HOST = process.env.RTDB_EMULATOR_HOST ?? '127.0.0.1:9000';
const NS = process.env.RTDB_NAMESPACE ?? 'demo-pitik';
const OUT = process.argv[2];

if (!/^(127\.0\.0\.1|localhost):\d+$/.test(HOST) || !NS.startsWith('demo-')) {
  console.error('Ditolak: hanya emulator lokal (127.0.0.1/localhost) & namespace demo-*.');
  process.exit(2);
}

const url = (path) => `http://${HOST}/${path}.json?ns=${NS}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- Listener SSE /controls (meniru stream ESP32) ---
async function openStream(sink) {
  const ctrl = new AbortController();
  const res = await fetch(url('controls'), {
    headers: { Accept: 'text/event-stream' },
    signal: ctrl.signal,
  });
  if (!res.ok) throw new Error(`stream: HTTP ${res.status}`);
  const reader = res.body.getReader();
  const dec = new TextDecoder();
  let buf = '';
  (async () => {
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const block = buf.slice(0, i);
          buf = buf.slice(i + 2);
          const ev = /^event: (.*)$/m.exec(block)?.[1];
          const raw = /^data: (.*)$/m.exec(block)?.[1];
          if (!ev || raw === undefined) continue;
          if (ev === 'keep-alive') { sink.push({ eventType: ev }); continue; }
          const payload = JSON.parse(raw);
          sink.push({ eventType: ev, path: payload?.path, data: payload?.data });
        }
      }
    } catch (_) { /* aborted */ }
  })();
  return () => ctrl.abort();
}

async function write(method, path, body) {
  const res = await fetch(url(path), { method, body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`${method} ${path}: HTTP ${res.status} ${await res.text()}`);
}

const live = [];
const steps = [];
async function step(id, label, request, fn) {
  live.length = 0;
  await fn();
  await sleep(500);
  steps.push({ id, label, request, events: live.filter((e) => e.eventType !== 'keep-alive') });
}

// Seed: /controls "kotor" seperti setelah app menulis saat ESP32 mati.
await write('PUT', 'controls', {
  fan: true, pump: true, auto_mode: true, feed_now: true,
  thi_normal: 72, thi_danger: 78, feed_hour1: 7, feed_min1: 0,
});

let close = await openStream(live);
await sleep(700);
steps.push({ id: 'initial_snapshot', label: 'Snapshot awal (stream dibuka)',
  request: 'GET (SSE) /controls', events: live.filter((e) => e.eventType !== 'keep-alive') });

await step('root_update_fan', 'Root update fan', 'PATCH /controls {"fan":false}',
  () => write('PATCH', 'controls', { fan: false }));
await step('root_update_pump', 'Root update pump', 'PATCH /controls {"pump":false}',
  () => write('PATCH', 'controls', { pump: false }));
await step('preset_atomic', 'Preset atomik fan + pump', 'PATCH /controls {"fan":true,"pump":true}',
  () => write('PATCH', 'controls', { fan: true, pump: true }));
await step('auto_mode', 'auto_mode', 'PATCH /controls {"auto_mode":false}',
  () => write('PATCH', 'controls', { auto_mode: false }));
await step('child_set', 'Child set', 'PUT /controls/fan false',
  () => write('PUT', 'controls/fan', false));
await step('root_put_after_initial', 'Root put setelah snapshot awal',
  'PUT /controls {fan:true,pump:true,auto_mode:true,thi_normal:72,...}',
  () => write('PUT', 'controls', {
    fan: true, pump: true, auto_mode: true, feed_now: false,
    thi_normal: 72, thi_danger: 78, feed_hour1: 7, feed_min1: 0,
  }));
await step('null_value', 'Payload null (hapus kunci)', 'PATCH /controls {"fan":null}',
  () => write('PATCH', 'controls', { fan: null }));
await step('invalid_type', 'Tipe tidak valid', 'PATCH /controls {"pump":"yes","thi_normal":"abc"}',
  () => write('PATCH', 'controls', { pump: 'yes', thi_normal: 'abc' }));
await step('unknown_key', 'Kunci tidak dikenal', 'PATCH /controls {"foo":1}',
  () => write('PATCH', 'controls', { foo: 1 }));
await step('same_payload_repeat', 'Payload identik diulang', 'PATCH /controls {"foo":1} (ulang)',
  () => write('PATCH', 'controls', { foo: 1 }));

close();
await sleep(300);
live.length = 0;
close = await openStream(live);
await sleep(700);
steps.push({ id: 'reconnect', label: 'Reconnect (stream dibuka ulang)',
  request: 'GET (SSE) /controls', events: live.filter((e) => e.eventType !== 'keep-alive') });
close();

for (const s of steps) {
  console.log(`\n# ${s.label}\n  request: ${s.request}`);
  if (s.events.length === 0) console.log('  (tidak ada event diterima)');
  for (const e of s.events) {
    const d = e.data;
    const shape = d === null ? 'null'
      : typeof d === 'object' ? `{${Object.keys(d).join(',')}}` : `${typeof d}:${JSON.stringify(d)}`;
    console.log(`  event=${e.eventType} path=${e.path} data=${shape}`);
  }
}
if (OUT) {
  writeFileSync(OUT, JSON.stringify({ host: HOST, namespace: NS, steps }, null, 2));
  console.log(`\nTersimpan: ${OUT}`);
}
process.exit(0);
