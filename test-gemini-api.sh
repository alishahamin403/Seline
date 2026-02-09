#!/bin/bash

# Test Gemini API to verify the key and endpoint work
echo "🔍 Testing Gemini API directly..."
echo ""

# Get your Gemini API key from Supabase secrets
# You can get it from: Supabase Dashboard → Edge Functions → Secrets → GEMINI_API_KEY
read -p "Enter your GEMINI_API_KEY: " GEMINI_KEY

echo ""
echo "Testing with v1beta endpoint..."
curl -X POST "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${GEMINI_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "models/text-embedding-004",
    "content": {
      "parts": [{
        "text": "test embedding"
      }]
    },
    "taskType": "RETRIEVAL_DOCUMENT",
    "outputDimensionality": 768
  }' \
  2>&1 | head -20

echo ""
echo "---"
echo "✅ If you see 'embedding' with values, it works!"
echo "❌ If you see 404, the endpoint is wrong"
echo "❌ If you see 403, your API key is invalid"
