-- PetVitals — initial multi-tenant schema with row-level security per clinic.
--
-- Auth model:
--   * Supabase Auth provides `auth.users`.
--   * `clinics` are the tenant unit; every clinical row pivots on `clinic_id`.
--   * `clinic_members` bridges users ↔ clinics with a role.
--   * RLS policies make a row visible iff the requesting user is a member of
--     the clinic that owns it. Writes additionally require a non-readonly
--     role.
--
-- A clinic's veterinarian / technician can register pets, run sessions,
-- and request AI insights; receptionists can read everything but write
-- nothing under `vital_readings`.

create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Clinics + membership
-- ---------------------------------------------------------------------------
create table clinics (
    id              uuid primary key default uuid_generate_v4(),
    name            text not null,
    address         text not null default '',
    phone           text not null default '',
    email           text not null default '',
    subscription_tier text not null default 'free'
        check (subscription_tier in ('free', 'pro', 'enterprise')),
    created_at      timestamptz not null default now()
);

create type clinic_role as enum (
    'owner', 'veterinarian', 'technician', 'receptionist', 'readonly'
);

create table clinic_members (
    user_id     uuid not null references auth.users(id) on delete cascade,
    clinic_id   uuid not null references clinics(id) on delete cascade,
    role        clinic_role not null default 'veterinarian',
    display_name text not null default '',
    created_at  timestamptz not null default now(),
    primary key (user_id, clinic_id)
);

create index clinic_members_clinic_id_idx on clinic_members (clinic_id);

-- Helper: is the current user a member of the given clinic?
create or replace function is_clinic_member(_clinic uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from clinic_members
        where user_id = auth.uid() and clinic_id = _clinic
    );
$$;

-- Helper: does the current user have write privileges on the clinic?
create or replace function can_write_clinic(_clinic uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from clinic_members
        where user_id = auth.uid()
          and clinic_id = _clinic
          and role in ('owner', 'veterinarian', 'technician')
    );
$$;

-- ---------------------------------------------------------------------------
-- Pets
-- ---------------------------------------------------------------------------
create type pet_species as enum (
    'dog', 'cat', 'rabbit', 'ferret', 'otherSmallMammal'
);

create type pet_sex as enum (
    'male', 'female', 'neutered', 'spayed', 'unknown'
);

create table pets (
    id              uuid primary key default uuid_generate_v4(),
    clinic_id       uuid not null references clinics(id) on delete cascade,
    name            text not null,
    species         pet_species not null,
    breed           text not null default '',
    sex             pet_sex not null default 'unknown',
    weight_kg       numeric(6,2) not null,
    date_of_birth   date not null,
    owner_name      text not null default '',
    owner_email     text not null default '',
    owner_phone     text not null default '',
    notes           text not null default '',
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index pets_clinic_idx on pets (clinic_id);

create table alarm_thresholds (
    pet_id          uuid primary key references pets(id) on delete cascade,
    spo2_min        numeric(5,2) not null default 94,
    hr_min          numeric(6,2) not null,
    hr_max          numeric(6,2) not null,
    temp_min_c      numeric(5,2) not null,
    temp_max_c      numeric(5,2) not null,
    resp_min        numeric(5,2) not null,
    resp_max        numeric(5,2) not null,
    alarm_beep      boolean not null default true,
    auto_monitor    boolean not null default false
);

-- ---------------------------------------------------------------------------
-- Sessions + readings
-- ---------------------------------------------------------------------------
create table sessions (
    id                  uuid primary key default uuid_generate_v4(),
    pet_id              uuid not null references pets(id) on delete cascade,
    clinic_id           uuid not null references clinics(id) on delete cascade,
    started_at          timestamptz not null,
    ended_at            timestamptz,
    started_by_user_id  uuid references auth.users(id) on delete set null,
    notes               text not null default '',
    device_id           text not null default '',
    device_name         text not null default '',
    summary             jsonb not null default '{}'::jsonb,
    created_at          timestamptz not null default now()
);

create index sessions_pet_started_idx on sessions (pet_id, started_at desc);
create index sessions_clinic_idx on sessions (clinic_id);

create type vital_kind as enum (
    'heartRate', 'pulseRate', 'spo2', 'temperatureC', 'respirationRate',
    'nibp', 'batteryPercent', 'perfusionIndex'
);

create table vital_readings (
    id              bigserial primary key,
    session_id      uuid not null references sessions(id) on delete cascade,
    timestamp       timestamptz not null,
    kind            vital_kind not null,
    value           numeric(10,3) not null,
    secondary_value numeric(10,3),
    tertiary_value  numeric(10,3)
);

create index vital_readings_session_kind_ts
    on vital_readings (session_id, kind, timestamp);

-- ---------------------------------------------------------------------------
-- AI insights
-- ---------------------------------------------------------------------------
create type insight_urgency as enum ('routine', 'monitor', 'urgent');

create table insights (
    id                  uuid primary key default uuid_generate_v4(),
    session_id          uuid not null references sessions(id) on delete cascade,
    pet_id              uuid not null references pets(id) on delete cascade,
    summary             text not null,
    findings            jsonb not null default '[]'::jsonb,
    recommendations     jsonb not null default '[]'::jsonb,
    urgency             insight_urgency not null default 'routine',
    thinking            text not null default '',
    model_id            text not null,
    input_tokens        integer not null default 0,
    output_tokens       integer not null default 0,
    cache_read_tokens   integer not null default 0,
    generated_at        timestamptz not null default now(),
    generated_by_user_id uuid references auth.users(id) on delete set null
);

create index insights_session_idx on insights (session_id, generated_at desc);
create index insights_pet_idx on insights (pet_id, generated_at desc);

-- ---------------------------------------------------------------------------
-- Share links — vet sends a session to an external referrer.
-- ---------------------------------------------------------------------------
create table share_links (
    token           text primary key,
    session_id      uuid not null references sessions(id) on delete cascade,
    pet_id          uuid not null references pets(id) on delete cascade,
    clinic_id       uuid not null references clinics(id) on delete cascade,
    created_by      uuid references auth.users(id) on delete set null,
    created_at      timestamptz not null default now(),
    expires_at      timestamptz not null,
    revoked_at      timestamptz
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table clinics              enable row level security;
alter table clinic_members       enable row level security;
alter table pets                 enable row level security;
alter table alarm_thresholds     enable row level security;
alter table sessions             enable row level security;
alter table vital_readings       enable row level security;
alter table insights             enable row level security;
alter table share_links          enable row level security;

-- Clinics: visible to members; only owner role can update.
create policy "clinics_select_members" on clinics
    for select using (is_clinic_member(id));
create policy "clinics_update_owner" on clinics
    for update using (
        exists (
            select 1 from clinic_members
            where user_id = auth.uid()
              and clinic_id = clinics.id
              and role = 'owner'
        )
    );
create policy "clinics_insert_self" on clinics
    for insert with check (auth.uid() is not null);

-- clinic_members: members can see all members of their own clinics; owners
-- can add/remove.
create policy "clinic_members_select_self_clinic" on clinic_members
    for select using (is_clinic_member(clinic_id));
create policy "clinic_members_insert_owner" on clinic_members
    for insert with check (
        exists (
            select 1 from clinic_members cm
            where cm.user_id = auth.uid()
              and cm.clinic_id = clinic_members.clinic_id
              and cm.role = 'owner'
        )
        or
        -- Bootstrap: a brand-new clinic with no members yet — the inserter
        -- becomes the first owner.
        not exists (
            select 1 from clinic_members cm2
            where cm2.clinic_id = clinic_members.clinic_id
        )
    );
create policy "clinic_members_delete_owner" on clinic_members
    for delete using (
        exists (
            select 1 from clinic_members cm
            where cm.user_id = auth.uid()
              and cm.clinic_id = clinic_members.clinic_id
              and cm.role = 'owner'
        )
    );

-- Pets / sessions / readings / insights / thresholds — uniform pattern.
create policy "pets_select_clinic" on pets
    for select using (is_clinic_member(clinic_id));
create policy "pets_write_clinic" on pets
    for all using (can_write_clinic(clinic_id))
    with check (can_write_clinic(clinic_id));

create policy "alarm_thresholds_select_clinic" on alarm_thresholds
    for select using (
        exists (select 1 from pets p
                where p.id = alarm_thresholds.pet_id
                  and is_clinic_member(p.clinic_id))
    );
create policy "alarm_thresholds_write_clinic" on alarm_thresholds
    for all using (
        exists (select 1 from pets p
                where p.id = alarm_thresholds.pet_id
                  and can_write_clinic(p.clinic_id))
    )
    with check (
        exists (select 1 from pets p
                where p.id = alarm_thresholds.pet_id
                  and can_write_clinic(p.clinic_id))
    );

create policy "sessions_select_clinic" on sessions
    for select using (is_clinic_member(clinic_id));
create policy "sessions_write_clinic" on sessions
    for all using (can_write_clinic(clinic_id))
    with check (can_write_clinic(clinic_id));

create policy "vital_readings_select_clinic" on vital_readings
    for select using (
        exists (select 1 from sessions s
                where s.id = vital_readings.session_id
                  and is_clinic_member(s.clinic_id))
    );
create policy "vital_readings_write_clinic" on vital_readings
    for all using (
        exists (select 1 from sessions s
                where s.id = vital_readings.session_id
                  and can_write_clinic(s.clinic_id))
    )
    with check (
        exists (select 1 from sessions s
                where s.id = vital_readings.session_id
                  and can_write_clinic(s.clinic_id))
    );

create policy "insights_select_clinic" on insights
    for select using (
        exists (select 1 from sessions s
                where s.id = insights.session_id
                  and is_clinic_member(s.clinic_id))
    );
create policy "insights_write_clinic" on insights
    for all using (
        exists (select 1 from sessions s
                where s.id = insights.session_id
                  and can_write_clinic(s.clinic_id))
    )
    with check (
        exists (select 1 from sessions s
                where s.id = insights.session_id
                  and can_write_clinic(s.clinic_id))
    );

create policy "share_links_select_clinic" on share_links
    for select using (is_clinic_member(clinic_id));
create policy "share_links_write_clinic" on share_links
    for all using (can_write_clinic(clinic_id))
    with check (can_write_clinic(clinic_id));
