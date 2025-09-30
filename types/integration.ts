// Multi-Provider Integration TypeScript Types
// Web ve mobile uygulamalar için ortak type definitions

export type AuthType = 'api_key' | 'oauth2' | 'bearer_token';
export type ConnectionStatus = 'active' | 'inactive' | 'error';
export type SyncFrequency = 'manual' | 'hourly' | 'daily' | 'weekly';
export type SyncDirection = 'to_provider_only' | 'from_provider_only' | 'bidirectional';
export type SyncStatus = 'pending' | 'synced' | 'error';

// Provider tablosu
export interface Provider {
  id: string;
  name: string; // 'notion', 'google_docs', 'onedrive'
  display_name: string; // 'Notion', 'Google Docs'
  auth_type: AuthType;
  api_base_url?: string;
  documentation_url?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

// Provider-specific credential types
export interface NotionCredentials {
  api_key: string;
  workspace_url: string;
}

export interface GoogleOAuthCredentials {
  access_token: string;
  refresh_token: string;
  expires_at: string;
  scopes: string[];
}

export interface OneDriveCredentials {
  access_token: string;
  refresh_token: string;
  expires_at: string;
}

// Union type for all credentials
export type ProviderCredentials = NotionCredentials | GoogleOAuthCredentials | OneDriveCredentials;

// Sync settings yapılandırması
export interface SyncSettings {
  auto_sync: boolean;
  sync_frequency: SyncFrequency;
  sync_direction: SyncDirection;
  target_config: {
    // Notion için
    main_page_id?: string;
    books_page_id?: string;
    quotes_page_id?: string;
    color_scheme?: string;
    auto_create_structure?: boolean;
    
    // Google Docs için
    folder_id?: string;
    template_doc_id?: string;
    
    // OneDrive için
    drive_id?: string;
    folder_path?: string;
  };
}

// Readspace integration
export interface ReadspaceIntegration {
  id: string;
  user_id: string;
  provider_id: string;
  readspace_id: string;
  integration_name: string;
  credentials: ProviderCredentials; // Encrypted in DB
  sync_settings: SyncSettings;
  status: ConnectionStatus;
  last_sync_at?: string;
  error_message?: string;
  created_at: string;
  updated_at: string;
  
  // Joined data
  provider?: Provider;
}

// Integration destinations
export interface IntegrationDestination {
  id: string;
  readspace_integration_id: string;
  type: string; // 'page', 'database', 'folder'
  external_id: string;
  name?: string;
  is_default: boolean;
  metadata: Record<string, any>;
  
  // Provider-specific fields
  target_database_id?: string;
  target_page_id?: string;
  books_page_id?: string;
  quotes_without_books_page_id?: string;
  database_properties?: Record<string, any>;
  page_template_id?: string;
  color_scheme?: string;
  icon_type?: string;
  cover_image?: string;
  auto_create_pages: boolean;
  
  created_at: string;
  updated_at: string;
}

// Sync logs
export interface SyncLog {
  id: string;
  readspace_integration_id: string;
  sync_type: 'full' | 'incremental' | 'manual';
  status: SyncStatus;
  items_synced: number;
  items_failed: number;
  error_details?: Record<string, any>;
  started_at: string;
  completed_at?: string;
  duration_ms?: number;
}

// Sync data yapısı (books/quotes tablolarında)
export interface NotionSyncData {
  page_id?: string;
  block_id?: string;
  url?: string;
  last_synced_at: string;
  sync_status: SyncStatus;
  content_hash?: string;
  provider_metadata?: Record<string, any>;
}

export interface GoogleDocsSyncData {
  document_id: string;
  url?: string;
  last_synced_at: string;
  sync_status: SyncStatus;
  content_hash?: string;
}

export interface OneDriveSyncData {
  file_id: string;
  url?: string;
  last_synced_at: string;
  sync_status: SyncStatus;
  content_hash?: string;
}

// Union type for sync data
export type ItemSyncData = {
  notion?: NotionSyncData;
  google_docs?: GoogleDocsSyncData;
  onedrive?: OneDriveSyncData;
};

// Books with sync data
export interface BookWithSync {
  id: string;
  user_id?: string;
  readspace_id: string;
  title: string;
  author?: string;
  publish_year?: number;
  publisher?: string;
  version: number;
  is_deleted: boolean;
  created_at: string;
  updated_at: string;
  description?: string;
  image_url?: string;
  page_count?: number;
  sync_data: ItemSyncData;
}

// Quotes with sync data
export interface QuoteWithSync {
  id: string;
  user_id?: string;
  readspace_id: string;
  book_id?: string;
  content?: string;
  page?: number;
  status: string;
  created_at: string;
  updated_at?: string;
  notification_shown: boolean;
  user_device_id?: string;
  sync_data: ItemSyncData;
  
  // Joined data
  book?: BookWithSync;
}

// API Request/Response types
export interface CreateIntegrationRequest {
  provider_name: string;
  readspace_id: string;
  integration_name: string;
  credentials: ProviderCredentials;
  sync_settings: SyncSettings;
}

export interface UpdateIntegrationRequest {
  integration_id: string;
  integration_name?: string;
  credentials?: ProviderCredentials;
  sync_settings?: SyncSettings;
}

export interface SyncContentRequest {
  integration_id: string;
  sync_type?: 'full' | 'incremental' | 'manual';
}

export interface ValidateConnectionRequest {
  integration_id: string;
}

export interface GetDestinationsRequest {
  integration_id: string;
}

// API Response types
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface SyncResults {
  books: {
    success: string[];
    failed: Array<{id: string; error: string}>;
  };
  quotes: {
    success: string[];
    failed: Array<{id: string; error: string}>;
  };
}

export interface DestinationItem {
  id: string;
  name: string;
  type: 'page' | 'database' | 'folder';
  url?: string;
  parent_type?: string;
}

// Integration setup wizard state
export interface IntegrationSetupState {
  step: 'provider' | 'auth' | 'destinations' | 'settings' | 'confirm';
  selected_provider?: Provider;
  credentials?: ProviderCredentials;
  available_destinations?: DestinationItem[];
  selected_destinations?: {
    main_page_id?: string;
    books_page_id?: string;
    quotes_page_id?: string;
  };
  sync_settings?: Partial<SyncSettings>;
  integration_name?: string;
}

// Error types
export interface IntegrationError {
  code: string;
  message: string;
  provider?: string;
  details?: Record<string, any>;
}

// Validation helpers
export const isValidNotionUrl = (url: string): boolean => {
  return /^https:\/\/[\w-]+\.notion\.so/.test(url);
};

export const extractNotionPageId = (url: string): string | null => {
  const match = url.match(/([a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/);
  return match ? match[0].replace(/-/g, '') : null;
};

// Constants
export const SUPPORTED_PROVIDERS = ['notion', 'google_docs', 'onedrive'] as const;
export const DEFAULT_SYNC_SETTINGS: SyncSettings = {
  auto_sync: false,
  sync_frequency: 'manual',
  sync_direction: 'to_provider_only',
  target_config: {
    auto_create_structure: true,
    color_scheme: 'blue'
  }
};

export const PROVIDER_COLORS = {
  notion: '#000000',
  google_docs: '#4285F4',
  onedrive: '#0078D4'
} as const;
