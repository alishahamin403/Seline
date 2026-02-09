#!/bin/bash

# Test the embeddings-proxy edge function
# This will help verify if it's deployed and working

echo "🔍 Testing embeddings-proxy edge function..."
echo ""

# You'll need to fill in these values from your Supabase project
SUPABASE_URL="YOUR_SUPABASE_URL_HERE"  # e.g., https://xxxxx.supabase.co
ANON_KEY="YOUR_ANON_KEY_HERE"           # From your project settings
ACCESS_TOKEN="YOUR_ACCESS_TOKEN_HERE"   # Get from Supabase auth

# Test the function
curl -X POST "${SUPABASE_URL}/functions/v1/embeddings-proxy" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "apikey: ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "check_needed",
    "check_document_type": "note",
    "document_ids": [],
    "content_hashes": []
  }' \
  -v

echo ""
echo "✅ Check the response above. If you see a 404, the function is not deployed."
echo "📝 If you see 401, there's an auth issue."
echo "✨ If you see 200 with JSON response, it's working!"
