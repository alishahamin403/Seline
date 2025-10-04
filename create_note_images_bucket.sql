-- Create storage bucket for note images
INSERT INTO storage.buckets (id, name, public)
VALUES ('note-images', 'note-images', true);

-- Set up RLS policies for note-images bucket
-- Allow authenticated users to upload images
CREATE POLICY "Users can upload their own images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'note-images' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Allow authenticated users to view their own images
CREATE POLICY "Users can view their own images"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'note-images' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Allow public access to images (since bucket is public)
CREATE POLICY "Public can view all images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'note-images');

-- Allow authenticated users to delete their own images
CREATE POLICY "Users can delete their own images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'note-images' AND (storage.foldername(name))[1] = auth.uid()::text);
