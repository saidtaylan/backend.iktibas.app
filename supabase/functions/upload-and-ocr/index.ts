import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { prompt as promptText } from "./prompt.ts";

// Gemini Files API URLs
const MODEL_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`;

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

// Estimate MIME type based on Base64 prefix (fast and sufficient)
function detectImageMimeType(base64String: string): string {
  if (base64String.startsWith('/9j/')) return 'image/jpeg';
  if (base64String.startsWith('iVBORw0KGgo')) return 'image/png';
  if (base64String.startsWith('R0lGODlh') || base64String.startsWith('R0lGODdh')) return 'image/gif';
  if (base64String.startsWith('UklGR')) return 'image/webp';
  return 'image/jpeg'; // fallback
}

/**
 * Uploads Base64 data to the Gemini Files API.
 * @param base64Data Image data in Base64 format
 * @param mimeType MIME type of the file (e.g., "image/jpeg")
 * @param apiKey Gemini API key
 */
async function uploadFileToGemini(base64Data: string, mimeType: string, apiKey1: string) {
  console.log(`[upload-and-ocr] 🟡 FilesAPI upload start | mime=${mimeType} sizeB64Len=${base64Data?.length}`);

  // Convert Base64 to binary
  const binaryString = atob(base64Data);
  const bytes = new Uint8Array(binaryString.length);
  for(let i = 0; i < binaryString.length; i++){
    bytes[i] = binaryString.charCodeAt(i);
  }
  const numBytes = bytes.length;

  // 1. Initial resumable request - define metadata
  const uploadUrl = `https://generativelanguage.googleapis.com/upload/v1beta/files?key=${apiKey1}`;
  const initialResponse = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      "X-Goog-Upload-Protocol": "resumable",
      "X-Goog-Upload-Command": "start",
      "X-Goog-Upload-Header-Content-Length": numBytes.toString(),
      "X-Goog-Upload-Header-Content-Type": mimeType,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      file: {
        display_name: "ocr_image"
      }
    })
  });

  if (!initialResponse.ok) {
    const text = await initialResponse.text();
    console.error(`[upload-and-ocr] ❌ FilesAPI init failed | status=${initialResponse.status} body=${text}`);
    throw new Error(`Initial upload request failed: ${text}`);
  }

  // Get the Upload URL from the header
  const actualUploadUrl = initialResponse.headers.get("x-goog-upload-url");
  if (!actualUploadUrl) {
    console.error("[upload-and-ocr] ❌ Upload URL could not be retrieved (x-goog-upload-url is empty)" );
    throw new Error("Upload URL could not be retrieved");
  }

  // 2. Upload actual bytes
  const tUploadBytesStart = Date.now();
  const uploadResponse = await fetch(actualUploadUrl, {
    method: "POST",
    headers: {
      "Content-Length": numBytes.toString(),
      "X-Goog-Upload-Offset": "0",
      "X-Goog-Upload-Command": "upload, finalize"
    },
    body: bytes
  });

  if (!uploadResponse.ok) {
    const error = await uploadResponse.text();
    console.error(`[upload-and-ocr] ❌ FilesAPI bytes upload failed | status=${uploadResponse.status} body=${error}`);
    throw new Error(`File upload failed: ${error}`);
  }

  const elapsed = Date.now() - tUploadBytesStart;
  const result = await uploadResponse.json();
  console.log(`[upload-and-ocr] ✅ FilesAPI upload ok | bytes=${numBytes} tookMs=${elapsed} fileName=${result?.file?.name}`);
  return result.file;
}

/**
 * Asks the Gemini model a question using the uploaded file.
 * @param fileName File name returned from the Files API (e.g., "files/abc-123")
 * @param prompt The question to ask
 * @param mimeType MIME type of the file
 * @param apiKey Gemini API key
 */
async function askGeminiWithFile(fileName: string, prompt: string, mimeType: string, apiKey1: string) {
  const body = {
    "contents": [
      {
        "parts": [
          {
            "file_data": {
              "file_uri": `https://generativelanguage.googleapis.com/v1beta/${fileName}`,
              "mime_type": mimeType
            }
          },
          {
            "text": prompt
          }
        ]
      }
    ]
  };

  console.log(`[upload-and-ocr] 🟡 Gemini generate start | file=${fileName} mime=${mimeType}`);
  const tGen = Date.now();

  const response = await fetch(`${MODEL_URL}?key=${apiKey1}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const text = await response.text();
    console.error(`[upload-and-ocr] ❌ Gemini generate failed | status=${response.status} body=${text}`);
    throw new Error(`Could not ask Gemini: ${text}`);
  }

  const result = await response.json();
  const textResponse = result.candidates?.[0]?.content?.parts?.[0]?.text;
  console.log(`[upload-and-ocr] ✅ Gemini generate ok | tookMs=${Date.now() - tGen} textLen=${textResponse?.length}`);
  return textResponse;
}

// Clean up visual line breaks in OCR output, preserving paragraphs
function normalizeOcrText(raw: string | null | undefined): string | null | undefined {
  if (!raw) {
    console.log('[upload-and-ocr] ℹ️ normalizeOcrText: empty input');
    return raw;
  }

  // Normalize line endings
  let t = raw.replace(/\r\n?/g, '\n');

  // Join words split at the end of a line by a hyphen or soft hyphen
  t = t.replace(/(\w)[\-\u00AD]\n(\w)/g, '$1$2');

  // Detect paragraphs based on two or more newlines and join single line breaks within a paragraph with a space
  t = t.split(/\n{2,}/).map((para) => {
    // To preserve list items: join with a space if the newline is not followed by a list marker
    return para.replace(/([^\n])\n(?!\n)(?!\s*(?:[-–—•*]|\d+[\.)]|\([A-Za-z]\))\s)/g, '$1 ');
  }).join('\n\n');

  // Clean up excessive whitespace and reduce more than two newlines
  t = t.replace(/[\t ]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();

  console.log(`[upload-and-ocr] ℹ️ normalizeOcrText: inLen=${raw.length} outLen=${t.length}`);
  return t;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }

  const reqStart = Date.now();
  const authHeader = req.headers.get('Authorization');

  console.log(`[upload-and-ocr] ▶️ Request start | method=${req.method} url=${req.url} contentType=${req.headers.get('content-type')} authHdrLen=${authHeader ? authHeader.length : 0}`);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  console.log(`[upload-and-ocr] ℹ️ Env presence | SUPABASE_URL=${!!supabaseUrl} ANON_KEY=${supabaseAnonKey ? 'set' : 'missing'} SERVICE_ROLE_KEY=${supabaseServiceRoleKey ? 'set' : 'missing'}`);

  // anon client for user context
  const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: req.headers.get('Authorization')
      }
    }
  });
  console.log('[upload-and-ocr] ℹ️ Supabase anon client initialized');

  let image_base64: string | undefined;
  let quote_id: string | undefined;

  try {
    const body = await req.json();
    image_base64 = body?.image_base64;
    quote_id = body?.quote_id;
    console.log(`[upload-and-ocr] ℹ️ Body parsed | imageLen=${image_base64?.length} quoteId=${quote_id}`);
  } catch (parseErr) {
    console.error('[upload-and-ocr] ❌ Body parse failed', parseErr);
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 });
  }

  const { data: { user } } = await supabaseClient.auth.getUser();
  console.log(`[upload-and-ocr] ℹ️ Auth getUser | userId=${user?.id ?? 'none'}`);

  let ocrText: string | null | undefined;

  async function upsertQuote(status: 'failed' | 'unreadable' | 'pending_selection' | 'processing') {
    try {
      console.log(`[upload-and-ocr] 🟡 upsertQuote | status=${status} contentLen=${ocrText?.length} quoteId=${quote_id}`);
      const { error } = await supabaseClient.from('quotes').update({
        content: ocrText ?? null,
        status
      }).eq('id', quote_id);

      if (error) {
        console.error('[upload-and-ocr] ❌ Update error for user:', user?.id, error);
      }
      else {
        console.log(`[upload-and-ocr] ✅ upsertQuote ok | status=${status} quoteId=${quote_id}`);
      }
    } catch (e) {
      console.error('[upload-and-ocr] ❌ Update exception for user:', user?.id, e);
    }
  }

  try {
    const t0 = Date.now();

    // Supabase clients (anon and admin)
    // admin client for round-robin (sequence/RPC)
    const adminClient = supabaseServiceRoleKey ? createClient(supabaseUrl, supabaseServiceRoleKey) : null;
    console.log(`[upload-and-ocr] ℹ️ Admin client ${adminClient ? 'initialized' : 'not-initialized'}`);

    // Get user from token
    if (!user) {
      console.warn('[upload-and-ocr] ⚠️ Unauthorized request (no user)');
      return new Response(JSON.stringify({
        error: 'Unauthorized'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 401
      });
    }

    if (!image_base64) {
      console.warn('[upload-and-ocr] ⚠️ Missing image_base64');
      return new Response(JSON.stringify({
        error: 'Missing required field: image_base64'
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 400
      });
    }

    // Load Gemini keys (COUNT + GEMINI_KEY_i) or single GEMINI_API_KEY fallback)
    function loadGeminiKeys(): string[] {
      const keys: string[] = [];
      const countStr = Deno.env.get('GEMINI_KEY_COUNT');
      const count = countStr ? Number(countStr) : 0;

      if (Number.isFinite(count) && count > 0) {
        for(let i = 1; i <= count; i++){
          const k = Deno.env.get(`GEMINI_KEY_${i}`);
          if (k && k.trim().length > 0) keys.push(k.trim());
        }
      }

      if (keys.length === 0) {
        const single = Deno.env.get('GEMINI_API_KEY');
        if (single && single.trim().length > 0) keys.push(single.trim());
      }
      return keys;
    }

    const geminiKeys = loadGeminiKeys();
    console.log(`[upload-and-ocr] ℹ️ Gemini keys loaded | count=${geminiKeys.length}`);

    if (geminiKeys.length === 0) {
      return new Response(JSON.stringify({
        error: "Gemini key not found. Please set GEMINI_API_KEY or GEMINI_KEY_COUNT + GEMINI_KEY_i secrets."
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 500
      });
    }

    //
    async function pickGeminiKey(): Promise<{ key: string, index: number }> {
      if (geminiKeys.length === 1) return {
        key: geminiKeys[0],
        index: 0
      };

      // stateless fallback if adminClient is missing: simple time-based rr (not fully guaranteed)
      if (!adminClient) {
        const idx = Math.floor(Date.now() / 1000 % geminiKeys.length);
        console.log(`[upload-and-ocr] ℹ️ Gemini key pick | strategy=stateless-time idx=${idx}`);
        return {
          key: geminiKeys[idx],
          index: idx
        };
      }

      const { data, error } = await adminClient.rpc('gemini_rr_next', {
        total: geminiKeys.length
      });

      if (error || typeof data !== 'number') {
        // fallback: time-based
        const idx = Math.floor(Date.now() / 1000 % geminiKeys.length);
        console.warn(`[upload-and-ocr] ⚠️ Gemini key pick RPC fallback | err=${error?.message} idx=${idx}`);
        return {
          key: geminiKeys[idx],
          index: idx
        };
      }

      const idx = data % geminiKeys.length;
      console.log(`[upload-and-ocr] ℹ️ Gemini key pick | strategy=rpc idx=${idx}`);
      return {
        key: geminiKeys[idx],
        index: idx
      };
    }

    // Perform OCR with Gemini (using Files API)
    try {
      const { key: selectedKey, index: rrIndex } = await pickGeminiKey();
      console.log(`[upload-and-ocr] 🟡 OCR flow start | rrIndex=${rrIndex} user=${user?.id}`);

      // Secure log: never log the key
      const prompt = promptText;
      const mimeType = detectImageMimeType(image_base64);
      console.log(`[upload-and-ocr] ℹ️ Detected mime | mime=${mimeType}`);

      // First, upload the file to the Files API
      const tUploadStart = Date.now();
      const uploadedFile = await uploadFileToGemini(image_base64, mimeType, selectedKey);
      console.log(`[upload-and-ocr] ✅ Upload completed | tookMs=${Date.now() - tUploadStart} file=${uploadedFile?.name}`);

      // Then, ask Gemini a question with the uploaded file
      const tGenStart = Date.now();

      // Manual control implementation for AbortSignal
      let timeoutId: number | undefined;
      const timeoutPromise = new Promise((_, reject) => {
        timeoutId = setTimeout(() => {
          reject(new Error('AbortError'));
        }, 30000);
      });

      const geminiPromise = askGeminiWithFile(uploadedFile.name, prompt, mimeType, selectedKey);

      try {
        ocrText = await Promise.race([
          geminiPromise,
          timeoutPromise
        ]);
        if (timeoutId) clearTimeout(timeoutId);
        console.log(`[upload-and-ocr] ✅ Gemini responded | tookMs=${Date.now() - tGenStart} textLen=${ocrText?.length}`);
      } catch (error) {
        if (timeoutId) clearTimeout(timeoutId);
        if (error instanceof Error && error.message === 'AbortError') {
          await upsertQuote('failed');
          throw new Error('Function timed out');
        }
        console.error('[upload-and-ocr] ❌ Gemini promise failed', error);
        throw error;
      }

      // Normalize (fix line break issues, preserve paragraphs)
      ocrText = normalizeOcrText(ocrText);
      console.log(`[upload-and-ocr] ℹ️ Post-normalize | textLen=${ocrText?.length} totalMs=${Date.now() - t0}`);

      if (!ocrText || ocrText.trim() === "") {
        await upsertQuote('failed');
        throw new Error("Gemini returned an empty or invalid response.");
      }
    } catch (error) {
      await upsertQuote('failed');
      console.error("[upload-and-ocr] ❌ Gemini OCR failed for user", user?.id, error?.stack || error);
      return new Response(JSON.stringify({
        error: `Gemini OCR operation failed: ${error.message}`
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 500
      });
    }

    // OCR result: unreadable / success
    const isUnreadable = ocrText?.trim().startsWith('UNREADABLE_TEXT') ?? false;

    if (isUnreadable) {
      await upsertQuote('unreadable');
      console.log('[upload-and-ocr] ✅ OCR unreadable path | returning 200');
      return new Response(JSON.stringify({
        success: true,
        ocrText,
        quoteId: quote_id,
        message: "OCR result is unreadable (unreadable)."
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 200
      });
    }

    // Readable success: pending_selection
    await upsertQuote('pending_selection');

    // Return successful response (OCR result + quoteId if present)
    console.log('[upload-and-ocr] ✅ OCR success path | returning 200');
    return new Response(JSON.stringify({
      success: true,
      ocrText,
      quoteId: quote_id,
      message: "OCR operation completed."
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      },
      status: 200
    });
  } catch (e) {
    // AbortError special case
    if (e instanceof Error && e.name === 'AbortError') {
      await upsertQuote('failed');
      console.warn('[upload-and-ocr] ⏱️ Function timed out | returning 408');
      return new Response(JSON.stringify({
        error: 'Function timed out'
      }), {
        status: 408,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }

    await upsertQuote('failed');
    console.error('[upload-and-ocr] ❌ Other error for user', user?.id, e?.stack || e);
    return new Response(JSON.stringify({
      error: (e as Error)?.message ?? String(e)
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      },
      status: 500
    });
  }
  finally {
    console.log(`[upload-and-ocr] ⏹️ Request end | tookMs=${Date.now() - reqStart}`);
  }
});