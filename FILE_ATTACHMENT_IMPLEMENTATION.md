# File Attachment Feature - Implementation Guide

## Overview

This guide explains the complete architecture for adding file attachment and intelligent content extraction to the Seline note-taking app.

**Key Features:**
- Upload 1 file per note (max 5MB)
- Intelligent document parsing (bank statements, invoices, receipts, generic docs)
- Editable extracted data fields (similar to receipt handling)
- Full-text search integration
- Works seamlessly with existing note architecture

---

## Architecture

### 1. Database Schema

**New Tables:**

#### `attachments`
Stores file metadata for each note attachment.

```sql
CREATE TABLE attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  note_id UUID NOT NULL UNIQUE REFERENCES notes(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  file_type TEXT NOT NULL CHECK (file_type IN ('pdf', 'image', 'csv', 'excel', 'other')),
  storage_path TEXT NOT NULL,
  document_type TEXT, -- 'bank_statement', 'invoice', 'receipt', 'document'
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE notes ADD COLUMN attachment_id UUID UNIQUE REFERENCES attachments(id) ON DELETE SET NULL;
```

#### `extracted_data`
Stores parsed and editable content from attachments.

```sql
CREATE TABLE extracted_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attachment_id UUID NOT NULL UNIQUE REFERENCES attachments(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL,
  extracted_fields JSONB NOT NULL, -- dynamic fields per type
  raw_text TEXT, -- full-text searchable
  confidence NUMERIC DEFAULT 0.9 CHECK (confidence >= 0.0 AND confidence <= 1.0),
  is_edited BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

**RLS Policies:** Enable RLS on both tables and create standard user-based SELECT/INSERT/UPDATE/DELETE policies.

**Indexes:**
```sql
CREATE INDEX idx_extracted_data_raw_text ON extracted_data USING GIN(to_tsvector('english', raw_text));
CREATE INDEX idx_extracted_data_user_id ON extracted_data(user_id);
CREATE INDEX idx_attachments_user_id ON attachments(user_id);
CREATE INDEX idx_attachments_note_id ON attachments(note_id);
```

**Storage Bucket:**
Create a new Supabase Storage bucket called `note-attachments` with RLS enabled.

---

### 2. Swift Models (✅ Created)

**Files:**
- `Seline/Models/AttachmentModels.swift` - Contains:
  - `NoteAttachment` - File metadata model
  - `ExtractedData` - Parsed content model
  - Document type-specific structures:
    - `BankStatementData`
    - `InvoiceData`
    - `ReceiptData`
  - Supabase data structures for encoding/decoding

**Key Features:**
- Type-safe extracted data with document-specific fields
- Helper methods to get typed data (`getBankStatementData()`, etc.)
- Conversion helpers from Supabase format

**Updated Files:**
- `Seline/Models/NoteModels.swift`
  - Added `attachmentId: UUID?` to Note struct
  - Updated `NoteSupabaseData` to include `attachment_id`
  - Updated sync methods to save/load attachmentId

---

### 3. Service Layer (✅ Created)

**File:** `Seline/Services/AttachmentService.swift`

**Responsibilities:**
- Upload files to Supabase Storage
- Download files from Supabase Storage
- Create/update/delete attachment records
- Load extracted data
- Update extracted fields when user edits
- Trigger extraction via Edge Function
- Cache extracted data locally

**Key Methods:**
```swift
// Upload file and create attachment
func uploadFileToNote(_ fileData: Data, fileName: String, fileType: String, noteId: UUID) async throws -> NoteAttachment

// Load extracted data for an attachment
func loadExtractedData(for attachmentId: UUID) async throws -> ExtractedData?

// Update extracted data (user edits)
func updateExtractedData(_ data: ExtractedData) async throws

// Delete attachment and extracted data
func deleteAttachment(_ attachment: NoteAttachment) async throws

// Download file for preview
func downloadFile(from storagePath: String) async throws -> Data
```

---

### 4. Edge Function (✅ Created)

**File:** `supabase/functions/extract-file-content/index.ts`

**Workflow:**
1. Receive attachment metadata and storage path
2. Download file from Supabase Storage
3. Convert file to format Claude can process:
   - Images/PDFs → base64
   - CSVs/TXT → raw text
4. Call Claude API with document type-specific extraction prompts
5. Parse JSON response from Claude
6. Store extracted data in `extracted_data` table
7. Update attachment with `document_type`

**Document Types Detected:**
- `bank_statement` - If filename contains "bank", "statement", or "account"
- `invoice` - If filename contains "invoice" or "bill"
- `receipt` - If filename contains "receipt" or "order"
- `document` - Generic fallback

**Extracted Fields by Type:**

**Bank Statement:**
- accountNumber, accountNumberMasked
- statementPeriodStart, statementPeriodEnd
- openingBalance, closingBalance
- totalDeposits, totalWithdrawals
- transactionCount, interestEarned, feesCharged
- transactions (array)

**Invoice:**
- vendorName, invoiceNumber
- invoiceDate, dueDate
- lineItems (array)
- subtotal, taxAmount, totalAmount
- paymentTerms

**Receipt:**
- merchantName, transactionDate, transactionTime
- items (array)
- subtotal, tax, totalPaid
- paymentMethod

**Deployment:**
```bash
# Deploy the function
supabase functions deploy extract-file-content

# Set environment variable
supabase secrets set ANTHROPIC_API_KEY="your-api-key"
```

---

## Implementation Checklist

### Database & Infrastructure
- [ ] Apply the database migration to create `attachments` and `extracted_data` tables
- [ ] Create `note-attachments` Supabase Storage bucket with RLS
- [ ] Enable RLS on both new tables
- [ ] Create RLS policies for user-based access
- [ ] Create indexes for performance

### Edge Function
- [ ] Deploy `extract-file-content` Edge Function to Supabase
- [ ] Set `ANTHROPIC_API_KEY` secret in Supabase project
- [ ] Test function with sample files

### Swift UI Components (TODO)
**File Picker Components:**
- [ ] `FilePickerButton` - Tap to open file picker (in note editor toolbar)
- [ ] `FilePickerController` - Wrapper around UIDocumentPickerViewController
- [ ] `FileChip` - Displays file in note (shows name, size, loading state)

**Extraction Detail Components:**
- [ ] `ExtractionDetailSheet` - Modal showing extracted data
- [ ] `ExtractedFieldRow` - Editable field row (single extracted field)
- [ ] `BankStatementView` - Displays bank statement data (table format)
- [ ] `InvoiceView` - Displays invoice with line items
- [ ] `ReceiptView` - Displays receipt items

**Space Management:**
- [ ] `FileSpaceIndicator` - Shows "2.3 MB / 5 MB used" at top of detail sheet

### Integration with NotesManager (TODO)
- [ ] Add attachment loading to `loadNotesFromSupabase()`
- [ ] Add attachment saving to note Supabase sync methods
- [ ] Add attachment cleanup when note is deleted

### Search Integration (TODO)
**Main Search (Home Page):**
- Include `extracted_data.raw_text` in search results
- Show extracted fields as preview (e.g., "Invoice from Vendor")

**LLM Search Integration:**
- Include extracted text in conversation context
- Use extracted structured data for better context

---

## SwiftUI Components to Create

### 1. File Picker
```swift
struct FilePickerButton: View {
    @State var isPresentingPicker = false
    var onFilePicked: (UIDocumentPickerDelegate.Result) -> Void

    var body: some View {
        Button(action: { isPresentingPicker = true }) {
            Image(systemName: "paperclip")
        }
        .fileImporter(
            isPresented: $isPresentingPicker,
            allowedContentTypes: [.pdf, .image, .plainText, .spreadsheet],
            onCompletion: { result in
                onFilePicked(result)
            }
        )
    }
}
```

### 2. File Attachment Chip
```swift
struct FileChip: View {
    @State var attachment: NoteAttachment
    @State var isLoading = false
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: attachment.fileTypeIcon)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.subheadline)
                        .lineLimit(1)

                    Text(attachment.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8, anchor: .center)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture(perform: onTap)
    }
}
```

### 3. Extraction Detail Sheet
```swift
struct ExtractionDetailSheet: View {
    @State var extractedData: ExtractedData
    @State var isSaving = false
    var onSave: (ExtractedData) -> Void

    var body: some View {
        NavigationStack {
            List {
                // Render different views based on document type
                switch extractedData.documentType {
                case "bank_statement":
                    if let data = extractedData.getBankStatementData() {
                        BankStatementDetailView(data: data)
                    }
                case "invoice":
                    if let data = extractedData.getInvoiceData() {
                        InvoiceDetailView(data: data)
                    }
                case "receipt":
                    if let data = extractedData.getReceiptData() {
                        ReceiptDetailView(data: data)
                    }
                default:
                    GenericDocumentView(fields: extractedData.extractedFields)
                }
            }
            .navigationTitle("Extracted Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if extractedData.isEdited {
                            onSave(extractedData)
                        }
                    }
                    .disabled(!extractedData.isEdited)
                }
            }
        }
    }
}
```

---

## Integration Steps

### 1. Update NoteEditorView
Add file attachment button to note editor:

```swift
HStack {
    // Existing buttons...

    // Add file attachment button
    FilePickerButton { result in
        handleFilePicked(result)
    }
}
```

### 2. Handle File Upload
```swift
private func handleFilePicked(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
        guard let fileURL = urls.first else { return }
        Task {
            do {
                let fileData = try Data(contentsOf: fileURL)
                let fileName = fileURL.lastPathComponent
                let fileType = fileURL.pathExtension

                let attachment = try await AttachmentService.shared.uploadFileToNote(
                    fileData,
                    fileName: fileName,
                    fileType: fileType,
                    noteId: note.id
                )

                // Update note with attachment ID
                note.attachmentId = attachment.id
                NotesManager.shared.updateNote(note)

                // Load and display extracted data
                if let extracted = try await AttachmentService.shared.loadExtractedData(for: attachment.id) {
                    showExtractionSheet = true
                    extractedData = extracted
                }
            } catch {
                // Handle error
            }
        }
    case .failure(let error):
        // Handle error
        print("File picker error: \(error)")
    }
}
```

### 3. Search Integration
In `SearchServiceIntegration`, add extracted data to search:

```swift
// When searching notes
let noteMatches = notes.filter { note in
    // Existing title/content search
    note.title.contains(query) || note.content.contains(query) ||
    // Add extracted data search
    (note.attachmentId != nil && searchExtractedData(noteId: note.id, query: query))
}
```

### 4. LLM Search Integration
In conversation context, include attachment data:

```swift
func buildContextWithAttachments(for note: Note) -> String {
    var context = note.content

    if let attachmentId = note.attachmentId,
       let extractedData = AttachmentService.shared.extractedDataCache[attachmentId] {
        context += "\n\nAttached Document Data:\n"
        context += extractedData.rawText ?? ""
    }

    return context
}
```

---

## File Storage

Files are stored in Supabase Storage at:
```
note-attachments/{user_id}/{note_id}_{timestamp}_{filename}
```

Example path:
```
note-attachments/550e8400-e29b-41d4-a716-446655440000/123e4567-e89b-12d3-a456-426614174000_1698765432_statement.pdf
```

---

## Limitations & Considerations

1. **One file per note** - By design, only one attachment per note
2. **5MB total size** - Currently enforced per note
3. **File types** - PDF, images, CSV, Excel, TXT (can extend)
4. **Extraction quality** - Depends on Claude API's vision capabilities
5. **Searchability** - Raw text is indexed for full-text search
6. **Privacy** - All data encrypted in transit and at rest (existing Seline encryption)

---

## Future Enhancements

1. **Multiple attachments per note** - Remove UNIQUE constraint, redesign UI
2. **File preview** - Show PDF preview or image preview before extraction
3. **Extraction refinement UI** - Let Claude suggest corrections for human review
4. **Smart linking** - Automatically link extracted data to other notes
5. **Export functionality** - Export extracted data as CSV or structured format
6. **Document templates** - Allow users to define custom extraction templates
7. **Batch processing** - Upload multiple files and organize automatically

---

## Testing Checklist

- [ ] Upload bank statement PDF and verify extraction
- [ ] Upload invoice and verify line items extraction
- [ ] Upload receipt image and verify item parsing
- [ ] Upload generic document and verify fallback extraction
- [ ] Edit extracted fields and verify they save
- [ ] Search for extracted text in main search
- [ ] Use extracted data in LLM conversations
- [ ] Delete attachment and verify cleanup
- [ ] Test file size limit enforcement
- [ ] Test 5MB per note limit
- [ ] Verify encrypted data at rest
- [ ] Test with various file formats

---

## Important Notes

1. **Database Migration** - Must apply schema changes before using the feature
2. **Edge Function** - Must deploy and set API key before extraction works
3. **Storage Bucket** - Must create with RLS policies matching notes table
4. **Encryption** - Extracted data uses same encryption as existing notes
5. **Backward Compatibility** - Existing notes work without attachments

