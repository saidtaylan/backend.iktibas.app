-- APP VERSIONS --
INSERT INTO public.app_versions (
  platform,
  version,
  build_number,
  minimum_supported_version,
  is_critical,
  is_released,
  release_date,
  release_notes,
  store_url
) VALUES (
  'ios',
  '1.0.0',
  1,
  '1.0.0',
  false,
  true,
  NOW(),
  'The first version of the app',
  'https://apps.apple.com/app/your-app-id'
);
INSERT INTO public.app_versions (
  platform,
  version,
  build_number,
  minimum_supported_version,
  is_critical,
  is_released,
  release_date,
  release_notes,
  store_url
) VALUES (
  'android',
  '1.0.0',
  1,
  '1.0.0',
  false,
  true,
  NOW(),
  'The first version of the app',
  'https://apps.apple.com/app/your-app-id'
);
-- APP VERSIONS END --
