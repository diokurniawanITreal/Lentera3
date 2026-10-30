// Proxy Gemini untuk LENTERA (Cloudflare Worker).
// API key hanya ada di rahasia Worker, TIDAK pernah di aplikasi.
//
// Kontrak:  POST /  {"question": "...", "language": "id"}
//           200 {"answer": "..."} | 401 | 400 | 429 | 502

const SYSTEM = `Kamu adalah asisten suara untuk penyandang tunanetra di aplikasi LENTERA.
Jawab dalam bahasa Indonesia yang jelas, ringkas (maksimal sekitar 120 kata), dan enak
DIDENGAR. Jangan memakai markdown, tabel, daftar bernomor panjang, emoji, tautan,
atau penanda sitasi seperti [1]. Untuk informasi terkini, gunakan hasil pencarian
dan sebutkan bila tidak yakin. Jangan mengaku selalu benar.`;

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return json({ error: 'method' }, 405);

    if (env.CLIENT_TOKEN &&
        request.headers.get('X-Lentera-Token') !== env.CLIENT_TOKEN) {
      return json({ error: 'unauthorized' }, 401);
    }

    let body;
    try { body = await request.json(); } catch { return json({ error: 'bad_request' }, 400); }
    const question = String(body?.question ?? '').trim();
    if (!question || question.length > 600) return json({ error: 'bad_request' }, 400);

    // Coba model utama; bila tidak tersedia lagi (mis. dihentikan Google),
    // jatuh otomatis ke model cadangan agar proxy tidak mati.
    const models = [
      env.GEMINI_MODEL || 'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-2.0-flash',
    ].filter((m, i, a) => a.indexOf(m) === i);

    const payload = {
      systemInstruction: { parts: [{ text: SYSTEM }] },
      contents: [{ role: 'user', parts: [{ text: question }] }],
      generationConfig: { temperature: 0.4, maxOutputTokens: 1024 },
    };
    // Grounding Google Search agar pertanyaan terkini (mis. pejabat) tidak usang.
    if (env.ENABLE_SEARCH !== 'false') payload.tools = [{ google_search: {} }];

    let res = null;
    for (const model of models) {
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
      try {
        res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': env.GEMINI_API_KEY,
          },
          body: JSON.stringify(payload),
        });
      } catch {
        return json({ error: 'upstream' }, 502);
      }
      if (res.status === 404) continue; // model tidak tersedia → coba berikutnya
      break;
    }

    if (res === null) return json({ error: 'upstream' }, 502);
    if (res.status === 429) return json({ error: 'rate_limited' }, 429);
    if (!res.ok) return json({ error: 'upstream' }, 502);

    const data = await res.json();
    const parts = data?.candidates?.[0]?.content?.parts ?? [];
    const answer = parts.map((p) => p.text ?? '').join('').trim();
    return json({ answer });
  },
};
