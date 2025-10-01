# Supabase Setup Instructions for Folder Sync

## Database Migration Required

To enable folder sync with Supabase, you need to run the SQL migration script. Here's how:

### Steps:

1. **Go to your Supabase Dashboard**
   - Navigate to: https://supabase.com/dashboard
   - Select your project: `rtiacmeeqkihzhgosvjn`

2. **Open SQL Editor**
   - Click on "SQL Editor" in the left sidebar
   - Click "New query"

3. **Copy and run the migration**
   - Open the file: `create_folders_table.sql` (in the project root)
   - Copy the entire contents
   - Paste into the SQL Editor
   - Click "Run" to execute the migration

### What the migration does:

✅ **Creates `folders` table** with:
- `id` (UUID, primary key)
- `user_id` (UUID, foreign key to auth.users)
- `name` (text, folder name)
- `color` (text, hex color code)
- `parent_folder_id` (UUID, foreign key to folders, for hierarchy)
- `created_at` and `updated_at` timestamps

✅ **Adds foreign key** from `notes.folder_id` to `folders.id`

✅ **Creates indexes** for faster queries:
- `folders_user_id_idx`
- `folders_parent_folder_id_idx`
- `notes_folder_id_idx`

✅ **Enables Row Level Security (RLS)** with policies:
- Users can only view their own folders
- Users can only insert/update/delete their own folders

✅ **Sets up automatic timestamp updates** via trigger

### Folder Hierarchy Support:

The system supports **3-level folder hierarchy**:
- Level 0: Root folders (no parent)
- Level 1: Subfolders (parent is a root folder)
- Level 2: Sub-subfolders (parent is a subfolder)

Maximum depth is enforced in the app to prevent deeper nesting.

## App Features Now Available:

### Folder Management:
- ✅ Create folders with hierarchy (up to 3 levels)
- ✅ Rename folders
- ✅ Delete folders (cascades to child folders and unlinks notes)
- ✅ Organize folders in collapsible tree structure
- ✅ All changes sync to Supabase in real-time

### Notes Integration:
- ✅ Notes are properly tied to folders via `folder_id`
- ✅ Pinned status is tracked and synced (`is_pinned`)
- ✅ Moving notes between folders syncs to Supabase
- ✅ Filter notes by folder in the main view
- ✅ When folder is deleted, notes are unlinked (folder_id set to null)

### Sync Behavior:
- **On app launch**: Loads folders and notes from Supabase if user is authenticated
- **On folder create**: Immediately syncs to Supabase
- **On folder update**: Syncs changes to Supabase
- **On folder delete**: Removes from Supabase and unlinks notes
- **On note pin/unpin**: Syncs pinned status to Supabase
- **On note save**: Syncs folder_id to Supabase

## Verification:

After running the migration, you can verify it worked by:

1. **Check tables in Supabase**:
   - Go to Table Editor
   - You should see a new `folders` table

2. **Test in the app**:
   - Create a folder in the sidebar
   - Check Supabase Table Editor → folders table
   - You should see your folder with correct user_id

3. **Test hierarchy**:
   - Create a subfolder (long-press folder → Create Subfolder)
   - Check that `parent_folder_id` is set correctly in Supabase

4. **Test note-folder relationship**:
   - Create a note in a folder (click + button on folder)
   - Check Supabase Table Editor → notes table
   - Verify `folder_id` matches the folder's ID

## Troubleshooting:

**If you see foreign key constraint errors:**
- The notes table already has notes with folder_ids that don't exist in the folders table
- Solution: Either delete those notes or set their folder_id to null first

**If you see RLS policy errors:**
- Make sure you're authenticated in the app
- Check that `auth.uid()` returns the correct user ID

**If folders don't load:**
- Check the Xcode console for error messages
- Look for "Loading folders from Supabase" logs
- Verify the RLS policies allow SELECT for your user
