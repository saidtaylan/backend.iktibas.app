import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface SyncRequest {
  action: 'create_integration' | 'update_integration' | 'sync_content' | 'validate_connection' | 'get_destinations';
  integration_id?: string;
  provider_name?: string;
  readspace_id?: string;
  integration_name?: string;
  credentials?: any;
  sync_settings?: any;
  sync_type?: 'full' | 'incremental' | 'manual';
}

// Provider-specific sync implementasyonları
abstract class BaseProviderSync {
  protected credentials: any;
  protected syncSettings: any;

  constructor(credentials: any, syncSettings: any) {
    this.credentials = credentials;
    this.syncSettings = syncSettings;
  }

  abstract async validateConnection(): Promise<boolean>;
  abstract async getDestinations(): Promise<any[]>;
  abstract async syncBooks(books: any[]): Promise<any>;
  abstract async syncQuotes(quotes: any[]): Promise<any>;
}

class NotionSync extends BaseProviderSync {
  private apiKey: string;
  private baseUrl = 'https://api.notion.com/v1';

  constructor(credentials: any, syncSettings: any) {
    super(credentials, syncSettings);
    this.apiKey = credentials.api_key;
  }

  async validateConnection(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/users/me`, {
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Notion-Version': '2022-06-28'
        }
      });
      return response.ok;
    } catch (error) {
      console.error('Notion connection validation failed:', error);
      return false;
    }
  }

  async getDestinations(): Promise<any[]> {
    try {
      // Kullanıcının erişebildiği sayfaları listele
      const response = await fetch(`${this.baseUrl}/search`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Notion-Version': '2022-06-28',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          filter: {
            property: 'object',
            value: 'page'
          }
        })
      });

      if (!response.ok) {
        throw new Error(`Notion API error: ${response.status}`);
      }

      const data = await response.json();
      
      return data.results.map((page: any) => ({
        id: page.id,
        name: this.getPageTitle(page),
        type: 'page',
        url: page.url,
        parent_type: page.parent?.type || 'workspace'
      }));
    } catch (error) {
      console.error('Failed to get Notion destinations:', error);
      return [];
    }
  }

  private getPageTitle(page: any): string {
    if (page.properties?.title?.title?.[0]?.plain_text) {
      return page.properties.title.title[0].plain_text;
    }
    if (page.properties?.Name?.title?.[0]?.plain_text) {
      return page.properties.Name.title[0].plain_text;
    }
    return 'Untitled';
  }

  async syncBooks(books: any[]): Promise<any> {
    const results = { success: [], failed: [] };
    
    const targetConfig = this.syncSettings.target_config;
    if (!targetConfig?.books_page_id) {
      throw new Error('Books page ID not configured');
    }

    for (const book of books) {
      try {
        await this.createBookPage(book, targetConfig.books_page_id);
        results.success.push(book.id);
      } catch (error) {
        console.error(`Failed to sync book ${book.id}:`, error);
        results.failed.push({ id: book.id, error: error.message });
      }
    }

    return results;
  }

  async syncQuotes(quotes: any[]): Promise<any> {
    const results = { success: [], failed: [] };
    
    for (const quote of quotes) {
      try {
        if (quote.book_id) {
          // Kitapla ilişkili quote - kitap sayfasına ekle
          await this.addQuoteToBookPage(quote);
        } else {
          // Kitapsız quote - ayrı sayfaya ekle
          await this.addQuoteToStandalonePage(quote);
        }
        results.success.push(quote.id);
      } catch (error) {
        console.error(`Failed to sync quote ${quote.id}:`, error);
        results.failed.push({ id: quote.id, error: error.message });
      }
    }

    return results;
  }

  private async createBookPage(book: any, parentPageId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/pages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Notion-Version': '2022-06-28',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        parent: { page_id: parentPageId },
        properties: {
          title: {
            title: [{ text: { content: book.title } }]
          }
        },
        children: [
          {
            object: 'block',
            type: 'paragraph',
            paragraph: {
              rich_text: [
                { text: { content: `Yazar: ${book.author || 'Bilinmiyor'}` } }
              ]
            }
          },
          ...(book.description ? [{
            object: 'block',
            type: 'paragraph',
            paragraph: {
              rich_text: [
                { text: { content: book.description } }
              ]
            }
          }] : [])
        ]
      })
    });

    if (!response.ok) {
      throw new Error(`Failed to create book page: ${response.status}`);
    }

    const result = await response.json();
    
    // Sync data'yı güncelle
    book.sync_data = {
      ...book.sync_data,
      notion: {
        page_id: result.id,
        url: result.url,
        last_synced_at: new Date().toISOString(),
        sync_status: 'synced'
      }
    };
  }

  private async addQuoteToBookPage(quote: any): Promise<void> {
    // Quote'un kitabının Notion page ID'sini bul
    const bookPageId = quote.book?.sync_data?.notion?.page_id;
    if (!bookPageId) {
      throw new Error('Book not synced to Notion yet');
    }

    await this.appendQuoteBlock(quote, bookPageId);
  }

  private async addQuoteToStandalonePage(quote: any): Promise<void> {
    const targetConfig = this.syncSettings.target_config;
    const quotesPageId = targetConfig?.quotes_page_id;
    if (!quotesPageId) {
      throw new Error('Quotes page ID not configured');
    }

    await this.appendQuoteBlock(quote, quotesPageId);
  }

  private async appendQuoteBlock(quote: any, pageId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/blocks/${pageId}/children`, {
      method: 'PATCH',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Notion-Version': '2022-06-28',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        children: [
          {
            object: 'block',
            type: 'quote',
            quote: {
              rich_text: [
                { text: { content: quote.content } }
              ],
              color: this.syncSettings.target_config?.color_scheme || 'default'
            }
          },
          ...(quote.page ? [{
            object: 'block',
            type: 'paragraph',
            paragraph: {
              rich_text: [
                { text: { content: `Sayfa: ${quote.page}`, annotations: { italic: true } } }
              ]
            }
          }] : [])
        ]
      })
    });

    if (!response.ok) {
      throw new Error(`Failed to append quote: ${response.status}`);
    }

    const result = await response.json();
    
    // Quote sync data'sını güncelle
    quote.sync_data = {
      ...quote.sync_data,
      notion: {
        block_id: result.results[0]?.id,
        last_synced_at: new Date().toISOString(),
        sync_status: 'synced'
      }
    };
  }
}

// Provider Factory
class ProviderSyncFactory {
  static create(providerName: string, credentials: any, syncSettings: any): BaseProviderSync {
    switch (providerName) {
      case 'notion':
        return new NotionSync(credentials, syncSettings);
      default:
        throw new Error(`Unsupported provider: ${providerName}`);
    }
  }
}

Deno.serve(async (req: Request) => {
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

    const requestData: SyncRequest = await req.json();

    switch (requestData.action) {
      case 'create_integration': {
        // Yeni integration oluştur
        const { data, error } = await supabase
          .from('readspace_integrations')
          .insert({
            user_id: user.id,
            provider_id: requestData.provider_name, // Bu provider name'den ID'ye çevrilmeli
            readspace_id: requestData.readspace_id,
            integration_name: requestData.integration_name,
            credentials: requestData.credentials, // Encrypted olmalı
            sync_settings: requestData.sync_settings || {},
            status: 'inactive'
          })
          .select()
          .single();

        if (error) {
          throw error;
        }

        return new Response(
          JSON.stringify({ success: true, integration: data }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      case 'validate_connection': {
        // Connection'ı validate et
        const { data: integration } = await supabase
          .from('readspace_integrations')
          .select('*, providers(*)')
          .eq('id', requestData.integration_id)
          .eq('user_id', user.id)
          .single();

        if (!integration) {
          throw new Error('Integration not found');
        }

        const providerSync = ProviderSyncFactory.create(
          integration.providers.name,
          integration.credentials,
          integration.sync_settings
        );

        const isValid = await providerSync.validateConnection();

        // Status'u güncelle
        await supabase
          .from('readspace_integrations')
          .update({ 
            status: isValid ? 'active' : 'error',
            error_message: isValid ? null : 'Connection validation failed'
          })
          .eq('id', requestData.integration_id);

        return new Response(
          JSON.stringify({ success: true, is_valid: isValid }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      case 'get_destinations': {
        // Available destinations'ı getir
        const { data: integration } = await supabase
          .from('readspace_integrations')
          .select('*, providers(*)')
          .eq('id', requestData.integration_id)
          .eq('user_id', user.id)
          .single();

        if (!integration) {
          throw new Error('Integration not found');
        }

        const providerSync = ProviderSyncFactory.create(
          integration.providers.name,
          integration.credentials,
          integration.sync_settings
        );

        const destinations = await providerSync.getDestinations();

        return new Response(
          JSON.stringify({ success: true, destinations }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      case 'sync_content': {
        // İçerik senkronizasyonu yap
        const { data: integration } = await supabase
          .from('readspace_integrations')
          .select('*, providers(*)')
          .eq('id', requestData.integration_id)
          .eq('user_id', user.id)
          .single();

        if (!integration || integration.status !== 'active') {
          throw new Error('Integration not found or not active');
        }

        // Sync log başlat
        const { data: syncLog } = await supabase
          .from('sync_logs')
          .insert({
            readspace_integration_id: requestData.integration_id,
            sync_type: requestData.sync_type || 'manual',
            status: 'pending'
          })
          .select()
          .single();

        try {
          const providerSync = ProviderSyncFactory.create(
            integration.providers.name,
            integration.credentials,
            integration.sync_settings
          );

          // Books ve quotes'ları çek
          const { data: books } = await supabase
            .from('books')
            .select('*')
            .eq('readspace_id', integration.readspace_id)
            .eq('is_deleted', false);

          const { data: quotes } = await supabase
            .from('quotes')
            .select('*, books(*)')
            .eq('readspace_id', integration.readspace_id);

          // Sync yap
          const bookResults = await providerSync.syncBooks(books || []);
          const quoteResults = await providerSync.syncQuotes(quotes || []);

          const totalSynced = bookResults.success.length + quoteResults.success.length;
          const totalFailed = bookResults.failed.length + quoteResults.failed.length;

          // Sync log'u güncelle
          await supabase
            .from('sync_logs')
            .update({
              status: 'synced',
              items_synced: totalSynced,
              items_failed: totalFailed,
              completed_at: new Date().toISOString()
            })
            .eq('id', syncLog.id);

          // Integration last sync güncelle
          await supabase
            .from('readspace_integrations')
            .update({
              last_sync_at: new Date().toISOString(),
              status: totalFailed > 0 ? 'error' : 'active'
            })
            .eq('id', requestData.integration_id);

          return new Response(
            JSON.stringify({
              success: true,
              sync_results: { books: bookResults, quotes: quoteResults }
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );

        } catch (syncError) {
          // Sync hatasında log'u güncelle
          await supabase
            .from('sync_logs')
            .update({
              status: 'error',
              error_details: { message: syncError.message },
              completed_at: new Date().toISOString()
            })
            .eq('id', syncLog.id);

          throw syncError;
        }
      }

      default:
        throw new Error('Invalid action');
    }

  } catch (error) {
    console.error('Integration sync error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
