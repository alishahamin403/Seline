-- Fix Storage RLS policy to allow authenticated users to upload images
-- Run this in your Supabase SQL editor

-- Drop the existing restrictive policies
DROP POLICY IF EXISTS "Users can upload their own images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload to note-images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update note-images" ON storage.objects;

-- Create policies that allow any authenticated user to insert and update in note-images bucket
CREATE POLICY "Authenticated users can upload to note-images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'note-images');

CREATE POLICY "Authenticated users can update note-images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'note-images')
WITH CHECK (bucket_id = 'note-images');

-- Verify the policies
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'objects'
AND schemaname = 'storage'
ORDER BY policyname;
