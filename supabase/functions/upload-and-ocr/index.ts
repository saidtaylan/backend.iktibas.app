import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { prompt as promptText } from "./prompt.ts";
// Gemini Files API URL'leri
const MODEL_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`;
// CORS başlıkları
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};
// Base64 başına göre MIME tipini tahmin et (hızlı ve yeterli)
function detectImageMimeType(base64String) {
  if (base64String.startsWith('/9j/')) return 'image/jpeg';
  if (base64String.startsWith('iVBORw0KGgo')) return 'image/png';
  if (base64String.startsWith('R0lGODlh') || base64String.startsWith('R0lGODdh')) return 'image/gif';
  if (base64String.startsWith('UklGR')) return 'image/webp';
  return 'image/jpeg'; // fallback
}
/**
 * Base64 verisini Gemini Files API'ye yükler.
 * @param base64Data Base64 formatındaki görsel verisi
 * @param mimeType Dosyanın MIME türü (örn: "image/jpeg")
 * @param apiKey Gemini API anahtarı
 */ async function uploadFileToGemini(base64Data, mimeType, apiKey1) {
  console.log(`Görsel Files API'ye yükleniyor... mime: ${mimeType}, size: ${base64Data.length}`);
  // Base64'i binary'ye çevir
  const binaryString = atob(base64Data);
  const bytes = new Uint8Array(binaryString.length);
  for(let i = 0; i < binaryString.length; i++){
    bytes[i] = binaryString.charCodeAt(i);
  }
  const numBytes = bytes.length;
  // 1. İlk resumable request - metadata tanımla
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
    const error = await initialResponse.json();
    throw new Error(`İlk upload isteği başarısız: ${JSON.stringify(error)}`);
  }
  // Upload URL'sini header'dan al
  const actualUploadUrl = initialResponse.headers.get("x-goog-upload-url");
  if (!actualUploadUrl) {
    throw new Error("Upload URL alınamadı");
  }
  // 2. Gerçek bytes'ları yükle
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
    throw new Error(`Dosya yükleme başarısız: ${error}`);
  }
  const result = await uploadResponse.json();
  return result.file;
}
/**
 * Yüklenen dosyayı kullanarak Gemini modeline bir soru sorar.
 * @param fileName Files API'den dönen dosya adı (örn: "files/abc-123")
 * @param prompt Sorulacak soru
 * @param mimeType Dosyanın MIME türü
 * @param apiKey Gemini API anahtarı
 */ async function askGeminiWithFile(fileName, prompt, mimeType, apiKey1) {
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
  const response = await fetch(`${MODEL_URL}?key=${apiKey1}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Gemini'ye sorulamadı: ${JSON.stringify(error)}`);
  }
  const result = await response.json();
  const textResponse = result.candidates[0].content.parts[0].text;
  return textResponse;
}
// OCR çıktısındaki görsel satır sonlarını temizle, paragrafları koru
function normalizeOcrText(raw) {
  if (!raw) return raw;
  // Satır sonlarını normalize et
  let t = raw.replace(/\r\n?/g, '\n');
  // Tire veya soft hyphen ile satır sonunda bölünmüş kelimeleri birleştir
  t = t.replace(/(\w)[\-\u00AD]\n(\w)/g, '$1$2');
  // Paragrafları iki veya daha fazla yeni satıra göre algıla ve paragraf içindeki tekli satır sonlarını boşlukla birleştir
  t = t.split(/\n{2,}/).map((para)=>{
    // Liste madde işaretlerini korumak için: yeni satırdan sonra madde ile başlamıyorsa boşlukla birleştir
    return para.replace(/([^\n])\n(?!\n)(?!\s*(?:[-–—•*]|\d+[\.)]|\([A-Za-z]\))\s)/g, '$1 ');
  }).join('\n\n');
  // Aşırı boşlukları toparla ve üçten fazla yeni satırı azalt
  t = t.replace(/[\t ]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  return t;
}
serve(async (req)=>{
  // CORS preflight isteklerini işle
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  // kullanıcı context'i için  anon client
  const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: req.headers.get('Authorization')
      }
    }
  });
  const { image_base64, quote_id } = await req.json();
  const { data: { user } } = await supabaseClient.auth.getUser();
  let ocrText;
  async function upsertQuote(status) {
    try {
      const { error } = await supabaseClient.from('quotes').update({
        content: ocrText ?? null,
        status
      }).eq('id', quote_id);
      if (error) {
        console.error('[upload-and-ocr] ❌ Update error for user:', user?.id, error);
      }
    } catch (e) {
      console.error('[upload-and-ocr] ❌ Update exception for user:', user?.id, e);
    }
  }
  try {
    const t0 = Date.now();
    // Supabase istemcileri (anon ve admin)
    // round-robin için admin client (sequence/RPC)
    const adminClient = supabaseServiceRoleKey ? createClient(supabaseUrl, supabaseServiceRoleKey) : null;
    // Kullanıcıyı token'dan al
    if (!user) {
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
    // Gemini anahtarlarını yükle (COUNT + GEMINI_KEY_i) veya tekil GEMINI_API_KEY fallback)
    function loadGeminiKeys() {
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
    if (geminiKeys.length === 0) {
      return new Response(JSON.stringify({
        error: "Gemini anahtarı bulunamadı. Lütfen GEMINI_API_KEY veya GEMINI_KEY_COUNT + GEMINI_KEY_i secrets ayarlayın."
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 500
      });
    }
    //
    async function pickGeminiKey() {
      if (geminiKeys.length === 1) return {
        key: geminiKeys[0],
        index: 0
      };
      // adminClient yoksa stateless fallback: zamanı bazlı basit rr (tam garanti değil)
      if (!adminClient) {
        const idx = Math.floor(Date.now() / 1000 % geminiKeys.length);
        return {
          key: geminiKeys[idx],
          index: idx
        };
      }
      const { data, error } = await adminClient.rpc('gemini_rr_next', {
        total: geminiKeys.length
      });
      if (error || typeof data !== 'number') {
        // fallback: zaman bazlı
        const idx = Math.floor(Date.now() / 1000 % geminiKeys.length);
        return {
          key: geminiKeys[idx],
          index: idx
        };
      }
      const idx = data % geminiKeys.length;
      return {
        key: geminiKeys[idx],
        index: idx
      };
    }
    // Gemini ile OCR işlemi yap (Files API kullanarak)
    try {
      const { key: selectedKey, index: rrIndex } = await pickGeminiKey();
      // Güvenli log: anahtarı asla loglama
      const prompt = promptText;
      const mimeType = detectImageMimeType(image_base64);
      // Önce dosyayı Files API'ye yükle
      const tUploadStart = Date.now();
      const uploadedFile = await uploadFileToGemini(image_base64, mimeType, selectedKey);
      // Sonra yüklenen dosya ile Gemini'ye soru sor
      const tGenStart = Date.now();
      // AbortSignal için manuel kontrol implementasyonu
      let timeoutId;
      const timeoutPromise = new Promise((_, reject)=>{
        timeoutId = setTimeout(()=>{
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
      } catch (error) {
        if (timeoutId) clearTimeout(timeoutId);
        if (error.message === 'AbortError') {
          await upsertQuote('failed');
          throw new Error('Function timed out');
        }
        throw error;
      }
      // Normalize et (satır sonu kırılmalarını düzelt, paragrafları koru)
      ocrText = normalizeOcrText(ocrText);
      console.log(`Gemini responded in ${Date.now() - tGenStart}ms (total ${Date.now() - t0}ms) behalf of user ${user?.id}`);
      if (!ocrText || ocrText.trim() === "") {
        await upsertQuote('failed');
        throw new Error("Gemini boş veya geçersiz bir yanıt döndürdü.");
      }
    } catch (error) {
      await upsertQuote('failed');
      console.error("Gemini OCR failed for user", user?.id, error);
      return new Response(JSON.stringify({
        error: `Gemini OCR işlemi başarısız oldu: ${error.message}`
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 500
      });
    }
    // OCR sonucu: unreadable / success
    const isUnreadable = ocrText?.trim().startsWith('UNREADABLE_TEXT') ?? false;
    if (isUnreadable) {
      await upsertQuote('unreadable');
      return new Response(JSON.stringify({
        success: true,
        ocrText,
        quoteId: quote_id,
        message: "OCR sonucu okunamadı (unreadable)."
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        },
        status: 200
      });
    }
    // Okunabilir başarı: pending_selection
    await upsertQuote('pending_selection');
    // Başarılı yanıt döndür (OCR sonucu + varsa quoteId)
    return new Response(JSON.stringify({
      success: true,
      ocrText,
      quoteId: quote_id,
      message: "OCR işlemi tamamlandı."
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      },
      status: 200
    });
  } catch (e) {
    // AbortError özel durumu
    if (e?.name === 'AbortError') {
      await upsertQuote('failed');
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
    console.error('Other error for user', user?.id, e);
    return new Response(JSON.stringify({
      error: e?.message ?? String(e)
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      },
      status: 500
    });
  }
});
