#!/bin/bash

echo "🔍 DeepSeek API Diagnostic Script"
echo "=================================="
echo ""

# Check if supabase CLI is available
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Install with: brew install supabase/tap/supabase"
    exit 1
fi

echo "✅ Supabase CLI found"
echo ""

# Check .env.local for project ref
if [ -f .env.local ]; then
    echo "📄 Checking .env.local..."
    PROJECT_REF=$(grep SUPABASE_PROJECT_REF .env.local | cut -d '=' -f2)
    if [ -n "$PROJECT_REF" ]; then
        echo "✅ Project ref found: $PROJECT_REF"
    else
        echo "⚠️  SUPABASE_PROJECT_REF not found in .env.local"
    fi
else
    echo "⚠️  .env.local file not found"
fi
echo ""

# Check if linked to remote project
echo "📡 Checking Supabase project link..."
supabase status 2>&1 | head -5
echo ""

# Check secrets (requires login)
echo "🔐 Checking secrets..."
echo "   (You may need to run: supabase login)"
supabase secrets list 2>&1 | grep -E "(DEEPSEEK|Name)" || echo "⚠️  Could not list secrets. Run 'supabase login' first."
echo ""

# Check if edge function exists
echo "📦 Checking edge function..."
if [ -f "supabase/functions/deepseek-proxy/index.ts" ]; then
    echo "✅ Edge function file exists: supabase/functions/deepseek-proxy/index.ts"
else
    echo "❌ Edge function file not found"
fi
echo ""

# Check migrations
echo "📋 Checking migrations..."
ls -l supabase/migrations/*deepseek* 2>/dev/null || echo "⚠️  No deepseek migrations found"
echo ""

echo "🔧 Recommended actions:"
echo "======================="
echo "1. Login to Supabase: supabase login"
echo "2. Apply migrations: supabase db push"
echo "3. Set API key: supabase secrets set DEEPSEEK_API_KEY=your_key_here"
echo "4. Deploy edge function: supabase functions deploy deepseek-proxy"
echo ""
echo "📚 Get your DeepSeek API key at: https://platform.deepseek.com/"
