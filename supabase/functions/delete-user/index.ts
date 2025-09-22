import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS başlıkları
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface DeleteUserRequest {
  userId?: string;
}

interface DeleteUserResponse {
  success: boolean;
  message: string;
  error?: string;
}

serve(async (req: Request): Promise<Response> => {
  // CORS preflight isteği
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Yalnızca POST metoduna izin ver
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: "Method not allowed" 
        }),
        {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Authorization header kontrolü
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: "Authorization header missing" 
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // JWT token'ı çıkar
    const jwt = authHeader.replace("Bearer ", "");

    // Normal client ile kullanıcı doğrulama
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseClient = createClient(supabaseUrl, supabaseKey);

    // Kullanıcıyı doğrula
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: "Invalid or expired token" 
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Request body'yi parse et
    let requestData: DeleteUserRequest = {};
    try {
      const body = await req.text();
      if (body) {
        requestData = JSON.parse(body);
      }
    } catch (parseError) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: "Invalid JSON in request body" 
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Silinecek kullanıcı ID'si - request'ten gelen ya da mevcut kullanıcı
    const userIdToDelete = requestData.userId || user.id;

    // Güvenlik: Kullanıcı yalnızca kendi hesabını silebilir (admin değilse)
    if (userIdToDelete !== user.id) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: "You can only delete your own account" 
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Service role key ile admin client oluştur
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) {
      console.error("Service role key not found in environment");
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: "Server configuration error" 
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });

    // Profile verilerini kontrol et (hata olsa da devam et)
    let profileExists = false;
    try {
      const { data: profileData, error: profileCheckError } = await supabaseAdmin
        .from('profiles')
        .select('id, user_id')
        .eq('user_id', userIdToDelete)
        .single();
      
      if (!profileCheckError && profileData) {
        profileExists = true;
        console.log("Profile found, will be deleted");
      } else if (profileCheckError?.code === 'PGRST116') {
        console.log("Profile not found, skipping profile deletion");
      } else {
        console.warn("Profile check warning (continuing anyway):", profileCheckError);
      }
    } catch (profileError) {
      console.warn("Profile check failed (continuing anyway):", profileError);
    }

    try {
      // 1. Adım: İlgili verileri sil (cascade olmayacak şekilde)
      
      // ReadSpaces'leri sil (kullanıcının sahip olduğu)
      const { error: readSpacesError } = await supabaseAdmin
        .from('readspaces')
        .delete()
        .eq('owner_id', userIdToDelete);
      
      if (readSpacesError) {
        console.error("ReadSpaces deletion error:", readSpacesError);
        throw new Error("Failed to delete user readspaces");
      }

      // 2. Adım: Profili sil (eğer varsa)
      if (profileExists) {
        const { error: profileError } = await supabaseAdmin
          .from('profiles')
          .delete()
          .eq('user_id', userIdToDelete);

        if (profileError) {
          console.error("Profile deletion error:", profileError);
          throw new Error("Failed to delete user profile");
        }
        console.log("Profile deleted successfully");
      } else {
        console.log("No profile to delete");
      }

      // 3. Adım: Auth user'ını sil
      const { error: authDeleteError } = await supabaseAdmin.auth.admin.deleteUser(userIdToDelete);
      
      if (authDeleteError) {
        console.error("Auth user deletion error:", authDeleteError);
        throw new Error("Failed to delete user from authentication");
      }

      console.log(`User ${userIdToDelete} successfully deleted`);

      const response: DeleteUserResponse = {
        success: true,
        message: "User account successfully deleted"
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });

    } catch (deletionError) {
      console.error("User deletion failed:", deletionError);
      
      // Hata durumunda geri alma işlemi yapılamaz (transaction olmadığı için)
      // Bu yüzden silme işlemlerini dikkatli sıraladık
      
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: deletionError instanceof Error ? deletionError.message : "User deletion failed" 
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

  } catch (error) {
    console.error("Unexpected error in delete-user function:", error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: "Internal server error" 
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
