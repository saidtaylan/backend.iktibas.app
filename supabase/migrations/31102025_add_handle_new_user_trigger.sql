-- Trigger: auth.users tablosuna yeni kullanıcı eklendiğinde handle_new_user fonksiyonunu çalıştır
-- Bu trigger, kullanıcı kaydı sırasında profiles, readspaces ve readspace_memberships tablolarına
-- otomatik kayıt ekler.

-- Önce mevcut trigger'ı kaldır (varsa)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Yeni trigger'ı oluştur
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger açıklaması
COMMENT ON TRIGGER on_auth_user_created ON auth.users IS 
'Yeni kullanıcı kaydedildiğinde otomatik olarak profile, readspace ve membership oluşturur';
