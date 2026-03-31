CREATE TABLE IF NOT EXISTS public.receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source text NOT NULL,
  legacy_note_id uuid REFERENCES public.notes(id) ON DELETE SET NULL,
  title text NOT NULL,
  merchant text,
  amount double precision NOT NULL DEFAULT 0,
  date timestamptz NOT NULL,
  transaction_time timestamptz,
  category text,
  subtotal double precision,
  tax double precision,
  tip double precision,
  payment_method text,
  image_urls jsonb NOT NULL DEFAULT '[]'::jsonb,
  detail_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  line_items jsonb NOT NULL DEFAULT '[]'::jsonb,
  year integer,
  month text,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT receipts_source_check CHECK (source IN ('native', 'migratedLegacy', 'legacyFallback'))
);

CREATE INDEX IF NOT EXISTS receipts_user_id_idx
  ON public.receipts(user_id);

CREATE INDEX IF NOT EXISTS receipts_user_date_idx
  ON public.receipts(user_id, date DESC);

CREATE UNIQUE INDEX IF NOT EXISTS receipts_legacy_note_id_uidx
  ON public.receipts(legacy_note_id)
  WHERE legacy_note_id IS NOT NULL;

ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own receipts" ON public.receipts;
CREATE POLICY "Users can view their own receipts" ON public.receipts
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can create their own receipts" ON public.receipts;
CREATE POLICY "Users can create their own receipts" ON public.receipts
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update their own receipts" ON public.receipts;
CREATE POLICY "Users can update their own receipts" ON public.receipts
  FOR UPDATE USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own receipts" ON public.receipts;
CREATE POLICY "Users can delete their own receipts" ON public.receipts
  FOR DELETE USING (user_id = (SELECT auth.uid()));

ALTER TABLE public.receipt_people
  ADD COLUMN IF NOT EXISTS receipt_id uuid;

UPDATE public.receipt_people
SET receipt_id = note_id
WHERE receipt_id IS NULL
  AND note_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS receipt_people_receipt_id_idx
  ON public.receipt_people(receipt_id);

CREATE INDEX IF NOT EXISTS receipt_people_note_id_idx
  ON public.receipt_people(note_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'receipt_people_receipt_id_fkey'
  ) THEN
    ALTER TABLE public.receipt_people
      ADD CONSTRAINT receipt_people_receipt_id_fkey
      FOREIGN KEY (receipt_id)
      REFERENCES public.receipts(id)
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END
$$;

DROP POLICY IF EXISTS "Users can view receipt-people for their own notes" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can create receipt-people for their own notes" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can update receipt-people for their own notes" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can delete receipt-people for their own notes" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can view receipt-people for their own receipts" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can create receipt-people for their own receipts" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can update receipt-people for their own receipts" ON public.receipt_people;
DROP POLICY IF EXISTS "Users can delete receipt-people for their own receipts" ON public.receipt_people;

CREATE POLICY "Users can view receipt-people for their own receipts" ON public.receipt_people
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.receipts r
      WHERE r.id = receipt_people.receipt_id
        AND r.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.notes n
      WHERE n.id = receipt_people.note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "Users can create receipt-people for their own receipts" ON public.receipt_people
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.receipts r
      WHERE r.id = receipt_people.receipt_id
        AND r.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.notes n
      WHERE n.id = receipt_people.note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "Users can update receipt-people for their own receipts" ON public.receipt_people
  FOR UPDATE USING (
    EXISTS (
      SELECT 1
      FROM public.receipts r
      WHERE r.id = receipt_people.receipt_id
        AND r.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.notes n
      WHERE n.id = receipt_people.note_id
        AND n.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.receipts r
      WHERE r.id = receipt_people.receipt_id
        AND r.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.notes n
      WHERE n.id = receipt_people.note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "Users can delete receipt-people for their own receipts" ON public.receipt_people
  FOR DELETE USING (
    EXISTS (
      SELECT 1
      FROM public.receipts r
      WHERE r.id = receipt_people.receipt_id
        AND r.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.notes n
      WHERE n.id = receipt_people.note_id
        AND n.user_id = (SELECT auth.uid())
    )
  );
