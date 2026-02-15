-- ============================================
-- Fix Security and Performance Issues
-- ============================================

-- 1. Fix Security Definer View
-- Drop and recreate without SECURITY DEFINER
DROP VIEW IF EXISTS public.visit_health_check;
CREATE VIEW public.visit_health_check AS
  SELECT
    user_id,
    COUNT(*) as total_visits,
    COUNT(*) FILTER (WHERE exit_time IS NULL) as active_visits,
    MAX(created_at) as last_visit
  FROM public.location_visits
  GROUP BY user_id;

-- 2. Fix Functions - Add search_path for security
CREATE OR REPLACE FUNCTION public.increment_deepseek_quota(p_user_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_profiles
  SET deepseek_quota_used = COALESCE(deepseek_quota_used, 0) + p_amount
  WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_deepseek_quota(p_user_id uuid)
RETURNS TABLE(quota_used numeric, quota_limit numeric, can_use boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(deepseek_quota_used, 0) as quota_used,
    COALESCE(deepseek_quota_limit, 100) as quota_limit,
    COALESCE(deepseek_quota_used, 0) < COALESCE(deepseek_quota_limit, 100) as can_use
  FROM user_profiles
  WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_location_thresholds_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_people_modified_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.date_modified = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_location_visit(
    p_user_id uuid,
    p_saved_place_id uuid,
    p_entry_time timestamp,
    p_session_id uuid,
    p_merge_window_minutes integer DEFAULT 7
) RETURNS TABLE(visit_id uuid, action text, merge_reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_visit location_visits%ROWTYPE;
    v_new_visit_id uuid;
    v_merge_reason text;
BEGIN
    SELECT * INTO v_existing_visit
    FROM location_visits
    WHERE user_id = p_user_id
      AND saved_place_id = p_saved_place_id
      AND (
          exit_time IS NULL
          OR exit_time >= (p_entry_time - interval '1 minute' * p_merge_window_minutes)
      )
      AND DATE(exit_time) = DATE(p_entry_time)
    ORDER BY entry_time DESC
    LIMIT 1
    FOR UPDATE NOWAIT;

    IF FOUND THEN
        IF v_existing_visit.exit_time IS NULL THEN
            v_merge_reason := 'continued_open_visit';
        ELSE
            v_merge_reason := 'quick_return';
        END IF;

        UPDATE location_visits
        SET exit_time = NULL,
            duration_minutes = NULL,
            session_id = p_session_id,
            merge_reason = v_merge_reason,
            confidence_score = 1.0,
            updated_at = NOW()
        WHERE id = v_existing_visit.id;

        RETURN QUERY SELECT v_existing_visit.id, 'merged'::text, v_merge_reason;
    ELSE
        v_new_visit_id := gen_random_uuid();
        INSERT INTO location_visits (
            id, user_id, saved_place_id, entry_time, session_id,
            confidence_score, created_at, updated_at,
            day_of_week, month, year, time_of_day
        ) VALUES (
            v_new_visit_id, p_user_id, p_saved_place_id, p_entry_time, p_session_id,
            1.0, NOW(), NOW(),
            to_char(p_entry_time, 'Day'),
            EXTRACT(MONTH FROM p_entry_time)::int,
            EXTRACT(YEAR FROM p_entry_time)::int,
            CASE
                WHEN EXTRACT(HOUR FROM p_entry_time) < 6 THEN 'Night'
                WHEN EXTRACT(HOUR FROM p_entry_time) < 12 THEN 'Morning'
                WHEN EXTRACT(HOUR FROM p_entry_time) < 18 THEN 'Afternoon'
                ELSE 'Evening'
            END
        );

        RETURN QUERY SELECT v_new_visit_id, 'created'::text, NULL::text;
    END IF;
EXCEPTION
    WHEN lock_not_available THEN
        RAISE EXCEPTION 'Visit is being modified by another process';
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_embedding(
    p_user_id uuid,
    p_document_type text,
    p_document_id text,
    p_title text,
    p_content text,
    p_content_hash bigint,
    p_metadata jsonb,
    p_embedding text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_embedding_array float[];
BEGIN
    v_embedding_array := string_to_array(trim(both '[]' from p_embedding), ',')::float[];

    IF array_length(v_embedding_array, 1) != 3072 THEN
        RAISE EXCEPTION 'expected 3072 dimensions, not %', array_length(v_embedding_array, 1);
    END IF;

    INSERT INTO document_embeddings (
        user_id,
        document_type,
        document_id,
        title,
        content,
        content_hash,
        metadata,
        embedding,
        updated_at
    ) VALUES (
        p_user_id,
        p_document_type,
        p_document_id,
        p_title,
        p_content,
        p_content_hash,
        p_metadata,
        v_embedding_array::vector(3072),
        now()
    )
    ON CONFLICT (user_id, document_type, document_id)
    DO UPDATE SET
        title = EXCLUDED.title,
        content = EXCLUDED.content,
        content_hash = EXCLUDED.content_hash,
        metadata = EXCLUDED.metadata,
        embedding = EXCLUDED.embedding,
        updated_at = now();
END;
$$;

-- 3. Add missing foreign key index
CREATE INDEX IF NOT EXISTS idx_visit_feedback_visit_id ON public.visit_feedback(visit_id);

-- 4. Fix RLS Policies - Use subselect pattern for better performance
-- location_thresholds (uses place_id, not user_id)
DROP POLICY IF EXISTS location_thresholds_select ON public.location_thresholds;
CREATE POLICY location_thresholds_select ON public.location_thresholds
  FOR SELECT USING (
    place_id IN (
      SELECT id FROM public.saved_places WHERE user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS location_thresholds_insert ON public.location_thresholds;
CREATE POLICY location_thresholds_insert ON public.location_thresholds
  FOR INSERT WITH CHECK (
    place_id IN (
      SELECT id FROM public.saved_places WHERE user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS location_thresholds_update ON public.location_thresholds;
CREATE POLICY location_thresholds_update ON public.location_thresholds
  FOR UPDATE USING (
    place_id IN (
      SELECT id FROM public.saved_places WHERE user_id = (SELECT auth.uid())
    )
  );

-- location_wifi_fingerprints (uses place_id, not user_id)
DROP POLICY IF EXISTS wifi_fingerprints_select ON public.location_wifi_fingerprints;
CREATE POLICY wifi_fingerprints_select ON public.location_wifi_fingerprints
  FOR SELECT USING (
    place_id IN (
      SELECT id FROM public.saved_places WHERE user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS wifi_fingerprints_insert ON public.location_wifi_fingerprints;
CREATE POLICY wifi_fingerprints_insert ON public.location_wifi_fingerprints
  FOR INSERT WITH CHECK (
    place_id IN (
      SELECT id FROM public.saved_places WHERE user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS wifi_fingerprints_update ON public.location_wifi_fingerprints;
CREATE POLICY wifi_fingerprints_update ON public.location_wifi_fingerprints
  FOR UPDATE USING (
    place_id IN (
      SELECT id FROM public.saved_places WHERE user_id = (SELECT auth.uid())
    )
  );

-- visit_feedback (has user_id column)
DROP POLICY IF EXISTS visit_feedback_select ON public.visit_feedback;
CREATE POLICY visit_feedback_select ON public.visit_feedback
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS visit_feedback_insert ON public.visit_feedback;
CREATE POLICY visit_feedback_insert ON public.visit_feedback
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

-- location_memories
DROP POLICY IF EXISTS "Users can view their own location memories" ON public.location_memories;
CREATE POLICY "Users can view their own location memories" ON public.location_memories
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own location memories" ON public.location_memories;
CREATE POLICY "Users can insert their own location memories" ON public.location_memories
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update their own location memories" ON public.location_memories;
CREATE POLICY "Users can update their own location memories" ON public.location_memories
  FOR UPDATE USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own location memories" ON public.location_memories;
CREATE POLICY "Users can delete their own location memories" ON public.location_memories
  FOR DELETE USING (user_id = (SELECT auth.uid()));

-- day_summaries
DROP POLICY IF EXISTS "Users can view their own day summaries" ON public.day_summaries;
CREATE POLICY "Users can view their own day summaries" ON public.day_summaries
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own day summaries" ON public.day_summaries;
CREATE POLICY "Users can insert their own day summaries" ON public.day_summaries
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update their own day summaries" ON public.day_summaries;
CREATE POLICY "Users can update their own day summaries" ON public.day_summaries
  FOR UPDATE USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own day summaries" ON public.day_summaries;
CREATE POLICY "Users can delete their own day summaries" ON public.day_summaries
  FOR DELETE USING (user_id = (SELECT auth.uid()));

-- document_embeddings
DROP POLICY IF EXISTS "Users can view own embeddings" ON public.document_embeddings;
CREATE POLICY "Users can view own embeddings" ON public.document_embeddings
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert own embeddings" ON public.document_embeddings;
CREATE POLICY "Users can insert own embeddings" ON public.document_embeddings
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update own embeddings" ON public.document_embeddings;
CREATE POLICY "Users can update own embeddings" ON public.document_embeddings
  FOR UPDATE USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete own embeddings" ON public.document_embeddings;
CREATE POLICY "Users can delete own embeddings" ON public.document_embeddings
  FOR DELETE USING (user_id = (SELECT auth.uid()));

-- people
DROP POLICY IF EXISTS "Users can view their own people" ON public.people;
CREATE POLICY "Users can view their own people" ON public.people
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can create their own people" ON public.people;
CREATE POLICY "Users can create their own people" ON public.people
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update their own people" ON public.people;
CREATE POLICY "Users can update their own people" ON public.people
  FOR UPDATE USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own people" ON public.people;
CREATE POLICY "Users can delete their own people" ON public.people
  FOR DELETE USING (user_id = (SELECT auth.uid()));

-- person_relationships
DROP POLICY IF EXISTS "Users can view relationships of their own people" ON public.person_relationships;
CREATE POLICY "Users can view relationships of their own people" ON public.person_relationships
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_relationships.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can create relationships for their own people" ON public.person_relationships;
CREATE POLICY "Users can create relationships for their own people" ON public.person_relationships
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_relationships.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can update relationships of their own people" ON public.person_relationships;
CREATE POLICY "Users can update relationships of their own people" ON public.person_relationships
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_relationships.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can delete relationships of their own people" ON public.person_relationships;
CREATE POLICY "Users can delete relationships of their own people" ON public.person_relationships
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_relationships.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

-- location_visit_people
DROP POLICY IF EXISTS "Users can view visit-people for their own visits" ON public.location_visit_people;
CREATE POLICY "Users can view visit-people for their own visits" ON public.location_visit_people
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.location_visits lv
      WHERE lv.id = location_visit_people.visit_id
      AND lv.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can create visit-people for their own visits" ON public.location_visit_people;
CREATE POLICY "Users can create visit-people for their own visits" ON public.location_visit_people
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.location_visits lv
      WHERE lv.id = location_visit_people.visit_id
      AND lv.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can update visit-people for their own visits" ON public.location_visit_people;
CREATE POLICY "Users can update visit-people for their own visits" ON public.location_visit_people
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.location_visits lv
      WHERE lv.id = location_visit_people.visit_id
      AND lv.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can delete visit-people for their own visits" ON public.location_visit_people;
CREATE POLICY "Users can delete visit-people for their own visits" ON public.location_visit_people
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.location_visits lv
      WHERE lv.id = location_visit_people.visit_id
      AND lv.user_id = (SELECT auth.uid())
    )
  );

-- receipt_people
DROP POLICY IF EXISTS "Users can view receipt-people for their own notes" ON public.receipt_people;
CREATE POLICY "Users can view receipt-people for their own notes" ON public.receipt_people
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.notes n
      WHERE n.id = receipt_people.note_id
      AND n.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can create receipt-people for their own notes" ON public.receipt_people;
CREATE POLICY "Users can create receipt-people for their own notes" ON public.receipt_people
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.notes n
      WHERE n.id = receipt_people.note_id
      AND n.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can update receipt-people for their own notes" ON public.receipt_people;
CREATE POLICY "Users can update receipt-people for their own notes" ON public.receipt_people
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.notes n
      WHERE n.id = receipt_people.note_id
      AND n.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can delete receipt-people for their own notes" ON public.receipt_people;
CREATE POLICY "Users can delete receipt-people for their own notes" ON public.receipt_people
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.notes n
      WHERE n.id = receipt_people.note_id
      AND n.user_id = (SELECT auth.uid())
    )
  );

-- person_favourite_places
DROP POLICY IF EXISTS "Users can view favourite places of their own people" ON public.person_favourite_places;
CREATE POLICY "Users can view favourite places of their own people" ON public.person_favourite_places
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_favourite_places.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can create favourite places for their own people" ON public.person_favourite_places;
CREATE POLICY "Users can create favourite places for their own people" ON public.person_favourite_places
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_favourite_places.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can update favourite places of their own people" ON public.person_favourite_places;
CREATE POLICY "Users can update favourite places of their own people" ON public.person_favourite_places
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_favourite_places.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can delete favourite places of their own people" ON public.person_favourite_places;
CREATE POLICY "Users can delete favourite places of their own people" ON public.person_favourite_places
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.people p
      WHERE p.id = person_favourite_places.person_id
      AND p.user_id = (SELECT auth.uid())
    )
  );

-- user_memory
DROP POLICY IF EXISTS "Users can view own memory" ON public.user_memory;
CREATE POLICY "Users can view own memory" ON public.user_memory
  FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert own memory" ON public.user_memory;
CREATE POLICY "Users can insert own memory" ON public.user_memory
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update own memory" ON public.user_memory;
CREATE POLICY "Users can update own memory" ON public.user_memory
  FOR UPDATE USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete own memory" ON public.user_memory;
CREATE POLICY "Users can delete own memory" ON public.user_memory
  FOR DELETE USING (user_id = (SELECT auth.uid()));

-- 5. Remove unused indexes for better write performance
DROP INDEX IF EXISTS public.idx_conversations_user_id;
DROP INDEX IF EXISTS public.idx_conversations_created_at;
DROP INDEX IF EXISTS public.idx_content_relationships_source;
DROP INDEX IF EXISTS public.idx_content_relationships_target;
DROP INDEX IF EXISTS public.idx_content_relationships_created;
DROP INDEX IF EXISTS public.idx_search_history_user;
DROP INDEX IF EXISTS public.idx_search_history_intent;
DROP INDEX IF EXISTS public.idx_search_contexts_user;
DROP INDEX IF EXISTS public.idx_suggestions_user;
DROP INDEX IF EXISTS public.idx_suggestions_dismissed;
DROP INDEX IF EXISTS public.idx_notes_tables;
DROP INDEX IF EXISTS public.idx_deleted_notes_tables;
DROP INDEX IF EXISTS public.idx_tasks_weekday;
DROP INDEX IF EXISTS public.user_profiles_email_idx;
DROP INDEX IF EXISTS public.idx_notes_todo_lists;
DROP INDEX IF EXISTS public.saved_emails_ai_summary_idx;
DROP INDEX IF EXISTS public.email_label_mappings_gmail_label_id_idx;
DROP INDEX IF EXISTS public.saved_emails_gmail_label_ids_idx;
DROP INDEX IF EXISTS public.idx_attachments_user_id;
DROP INDEX IF EXISTS public.idx_extracted_data_user_id;
DROP INDEX IF EXISTS public.idx_recurring_expenses_user_id;
DROP INDEX IF EXISTS public.idx_saved_emails_user_id;
DROP INDEX IF EXISTS public.idx_location_visits_exit_time_null;
DROP INDEX IF EXISTS public.idx_deepseek_usage_user_date;
DROP INDEX IF EXISTS public.idx_deepseek_usage_operation;
DROP INDEX IF EXISTS public.idx_deepseek_usage_cost;
DROP INDEX IF EXISTS public.idx_location_visits_signal_quality;
DROP INDEX IF EXISTS public.idx_location_visits_outliers;
DROP INDEX IF EXISTS public.idx_location_visits_commute_stops;
DROP INDEX IF EXISTS public.idx_visit_feedback_type;
DROP INDEX IF EXISTS public.idx_location_memories_user_id;
DROP INDEX IF EXISTS public.idx_location_memories_memory_type;
DROP INDEX IF EXISTS public.idx_people_relationship;
DROP INDEX IF EXISTS public.idx_people_is_favourite;
DROP INDEX IF EXISTS public.idx_people_name;
DROP INDEX IF EXISTS public.idx_day_summaries_user_id;
DROP INDEX IF EXISTS public.idx_day_summaries_summary_date;
DROP INDEX IF EXISTS public.idx_people_date_modified;
DROP INDEX IF EXISTS public.idx_person_favourite_places_place_id;
DROP INDEX IF EXISTS public.idx_user_memory_user_type;
DROP INDEX IF EXISTS public.idx_user_memory_key;
DROP INDEX IF EXISTS public.idx_tasks_calendar_event_id;
DROP INDEX IF EXISTS public.idx_tasks_is_from_calendar;

-- 6. Move btree_gist extension to extensions schema (optional - for better organization)
-- Note: This is safe to run and will improve security
CREATE SCHEMA IF NOT EXISTS extensions;
ALTER EXTENSION btree_gist SET SCHEMA extensions;
