-- Run this SQL in Supabase Dashboard > SQL Editor if people feature tables don't exist.
-- Creates: people, person_relationships, location_visit_people, receipt_people, person_favourite_places

-- 1. Create people table
CREATE TABLE IF NOT EXISTS public.people (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    nickname TEXT,
    relationship TEXT NOT NULL DEFAULT 'friend',
    custom_relationship TEXT,
    birthday DATE,
    favourite_food TEXT,
    favourite_gift TEXT,
    favourite_color TEXT,
    interests TEXT[],
    notes TEXT,
    how_we_met TEXT,
    phone TEXT,
    email TEXT,
    address TEXT,
    instagram TEXT,
    linkedin TEXT,
    photo_url TEXT,
    is_favourite BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    date_modified TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_people_user_id ON public.people(user_id);
CREATE INDEX IF NOT EXISTS idx_people_relationship ON public.people(relationship);
CREATE INDEX IF NOT EXISTS idx_people_is_favourite ON public.people(is_favourite);
CREATE INDEX IF NOT EXISTS idx_people_name ON public.people(name);
CREATE INDEX IF NOT EXISTS idx_people_date_modified ON public.people(date_modified DESC);

ALTER TABLE public.people ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own people" ON public.people;
CREATE POLICY "Users can view their own people" ON public.people FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can create their own people" ON public.people;
CREATE POLICY "Users can create their own people" ON public.people FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own people" ON public.people;
CREATE POLICY "Users can update their own people" ON public.people FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own people" ON public.people;
CREATE POLICY "Users can delete their own people" ON public.people FOR DELETE USING (auth.uid() = user_id);

-- 2. Create person_relationships table
CREATE TABLE IF NOT EXISTS public.person_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
    related_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
    relationship_label TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_person_relationship UNIQUE (person_id, related_person_id)
);

CREATE INDEX IF NOT EXISTS idx_person_relationships_person_id ON public.person_relationships(person_id);
CREATE INDEX IF NOT EXISTS idx_person_relationships_related_person_id ON public.person_relationships(related_person_id);

ALTER TABLE public.person_relationships ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Users can view relationships of their own people" ON public.person_relationships FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_relationships.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can create relationships for their own people" ON public.person_relationships FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_relationships.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can update relationships of their own people" ON public.person_relationships FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_relationships.person_id AND people.user_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_relationships.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can delete relationships of their own people" ON public.person_relationships FOR DELETE
    USING (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_relationships.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. Create location_visit_people table (links people to location visits)
CREATE TABLE IF NOT EXISTS public.location_visit_people (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visit_id UUID NOT NULL REFERENCES public.location_visits(id) ON DELETE CASCADE,
    person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_visit_person UNIQUE (visit_id, person_id)
);

CREATE INDEX IF NOT EXISTS idx_location_visit_people_visit_id ON public.location_visit_people(visit_id);
CREATE INDEX IF NOT EXISTS idx_location_visit_people_person_id ON public.location_visit_people(person_id);

ALTER TABLE public.location_visit_people ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Users can view visit-people for their own visits" ON public.location_visit_people FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.location_visits WHERE location_visits.id = location_visit_people.visit_id AND location_visits.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can create visit-people for their own visits" ON public.location_visit_people FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.location_visits WHERE location_visits.id = location_visit_people.visit_id AND location_visits.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can update visit-people for their own visits" ON public.location_visit_people FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.location_visits WHERE location_visits.id = location_visit_people.visit_id AND location_visits.user_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.location_visits WHERE location_visits.id = location_visit_people.visit_id AND location_visits.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can delete visit-people for their own visits" ON public.location_visit_people FOR DELETE
    USING (EXISTS (SELECT 1 FROM public.location_visits WHERE location_visits.id = location_visit_people.visit_id AND location_visits.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 4. Create receipt_people table
CREATE TABLE IF NOT EXISTS public.receipt_people (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id UUID NOT NULL REFERENCES public.notes(id) ON DELETE CASCADE,
    person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_receipt_person UNIQUE (note_id, person_id)
);

CREATE INDEX IF NOT EXISTS idx_receipt_people_note_id ON public.receipt_people(note_id);
CREATE INDEX IF NOT EXISTS idx_receipt_people_person_id ON public.receipt_people(person_id);

ALTER TABLE public.receipt_people ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Users can view receipt-people for their own notes" ON public.receipt_people FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.notes WHERE notes.id = receipt_people.note_id AND notes.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can create receipt-people for their own notes" ON public.receipt_people FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.notes WHERE notes.id = receipt_people.note_id AND notes.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can update receipt-people for their own notes" ON public.receipt_people FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.notes WHERE notes.id = receipt_people.note_id AND notes.user_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.notes WHERE notes.id = receipt_people.note_id AND notes.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can delete receipt-people for their own notes" ON public.receipt_people FOR DELETE
    USING (EXISTS (SELECT 1 FROM public.notes WHERE notes.id = receipt_people.note_id AND notes.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 5. Create person_favourite_places table
CREATE TABLE IF NOT EXISTS public.person_favourite_places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
    place_id UUID NOT NULL REFERENCES public.saved_places(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_person_favourite_place UNIQUE (person_id, place_id)
);

CREATE INDEX IF NOT EXISTS idx_person_favourite_places_person_id ON public.person_favourite_places(person_id);
CREATE INDEX IF NOT EXISTS idx_person_favourite_places_place_id ON public.person_favourite_places(place_id);

ALTER TABLE public.person_favourite_places ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Users can view favourite places of their own people" ON public.person_favourite_places FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_favourite_places.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can create favourite places for their own people" ON public.person_favourite_places FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_favourite_places.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can update favourite places of their own people" ON public.person_favourite_places FOR UPDATE
    USING (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_favourite_places.person_id AND people.user_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_favourite_places.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can delete favourite places of their own people" ON public.person_favourite_places FOR DELETE
    USING (EXISTS (SELECT 1 FROM public.people WHERE people.id = person_favourite_places.person_id AND people.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 6. Trigger for people date_modified
CREATE OR REPLACE FUNCTION update_people_modified_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.date_modified = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_people_modified ON public.people;
CREATE TRIGGER trigger_update_people_modified
    BEFORE UPDATE ON public.people
    FOR EACH ROW
    EXECUTE FUNCTION update_people_modified_timestamp();
