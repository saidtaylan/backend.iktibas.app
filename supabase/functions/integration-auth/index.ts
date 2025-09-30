import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface CredentialPayload {
  provider_name: string;
  credentials: Record<string, any>;
}

interface EncryptionRequest {
  action: 'encrypt' | 'decrypt';
  payload: CredentialPayload;
}

// Basit credential encryption/decryption servisi
// Üretim ortamında AWS KMS, HashiCorp Vault vb. kullanılmalı
class CredentialService {
  private key: CryptoKey | null = null;

  async initialize() {
    const keyMaterial = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(Deno.env.get("ENCRYPTION_KEY") || "default-key-32-chars-long-123456"),
      { name: "PBKDF2" },
      false,
      ["deriveBits", "deriveKey"]
    );

    this.key = await crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        salt: new TextEncoder().encode("iktibas-salt"),
        iterations: 100000,
        hash: "SHA-256",
      },
      keyMaterial,
      { name: "AES-GCM", length: 256 },
      true,
      ["encrypt", "decrypt"]
    );
  }

  async encrypt(data: any): Promise<string> {
    if (!this.key) await this.initialize();
    
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const encodedData = new TextEncoder().encode(JSON.stringify(data));
    
    const encrypted = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      this.key!,
      encodedData
    );

    const result = new Uint8Array(iv.length + encrypted.byteLength);
    result.set(iv);
    result.set(new Uint8Array(encrypted), iv.length);
    
    return btoa(String.fromCharCode(...result));
  }

  async decrypt(encryptedData: string): Promise<any> {
    if (!this.key) await this.initialize();
    
    const data = new Uint8Array(
      atob(encryptedData).split('').map(c => c.charCodeAt(0))
    );
    
    const iv = data.slice(0, 12);
    const encrypted = data.slice(12);
    
    const decrypted = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      this.key!,
      encrypted
    );
    
    return JSON.parse(new TextDecoder().decode(decrypted));
  }
}

// Provider-specific credential validatörleri
class ProviderValidators {
  static async validateNotion(credentials: any): Promise<boolean> {
    const { api_key, workspace_url } = credentials;
    
    if (!api_key || !workspace_url) {
      return false;
    }

    try {
      const response = await fetch('https://api.notion.com/v1/users/me', {
        headers: {
          'Authorization': `Bearer ${api_key}`,
          'Notion-Version': '2022-06-28'
        }
      });
      
      return response.ok;
    } catch (error) {
      console.error('Notion validation error:', error);
      return false;
    }
  }

  static async validateGoogleDocs(credentials: any): Promise<boolean> {
    const { access_token } = credentials;
    
    if (!access_token) {
      return false;
    }

    try {
      const response = await fetch('https://www.googleapis.com/oauth2/v1/tokeninfo', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${access_token}`
        }
      });
      
      return response.ok;
    } catch (error) {
      console.error('Google Docs validation error:', error);
      return false;
    }
  }

  static async validate(providerName: string, credentials: any): Promise<boolean> {
    switch (providerName) {
      case 'notion':
        return this.validateNotion(credentials);
      case 'google_docs':
        return this.validateGoogleDocs(credentials);
      default:
        return false;
    }
  }
}

Deno.serve(async (req: Request) => {
  // CORS preflight check
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    );

    // JWT doğrulama
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { action, payload }: EncryptionRequest = await req.json();
    const credentialService = new CredentialService();

    if (action === 'encrypt') {
      // Credential'ları validate et
      const isValid = await ProviderValidators.validate(
        payload.provider_name, 
        payload.credentials
      );

      if (!isValid) {
        return new Response(
          JSON.stringify({ error: 'Invalid credentials for provider' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const encrypted = await credentialService.encrypt(payload.credentials);
      
      return new Response(
        JSON.stringify({ encrypted_credentials: encrypted }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } 
    
    else if (action === 'decrypt') {
      const decrypted = await credentialService.decrypt(payload.credentials as string);
      
      return new Response(
        JSON.stringify({ decrypted_credentials: decrypted }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ error: 'Invalid action' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Integration auth error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
