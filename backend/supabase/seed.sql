-- Local-dev seed data. Not applied to remote.
-- Inserts a demo clinic + a demo dog so `flutter run` against
-- `supabase start` yields a usable UI without a registration flow.

insert into clinics (id, name, address, phone, email, subscription_tier)
values (
    '00000000-0000-0000-0000-000000000001',
    'Pacific Veterinary',
    '123 Oak St, Seattle WA',
    '+1-555-VET-CARE',
    'hello@pacvet.example',
    'pro'
);

insert into pets (
    id, clinic_id, name, species, breed, sex, weight_kg, date_of_birth,
    owner_name, owner_email, owner_phone, notes
) values (
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000001',
    'Bella',
    'dog',
    'Beagle',
    'spayed',
    12.5,
    '2022-03-14',
    'Sam Lee',
    'sam@example.com',
    '+1-555-0100',
    'Recovering from dental surgery; monitor weekly.'
);

insert into alarm_thresholds (
    pet_id, spo2_min, hr_min, hr_max,
    temp_min_c, temp_max_c, resp_min, resp_max
) values (
    '00000000-0000-0000-0000-000000000010',
    94,        -- spo2_min
    68,        -- hr_min  (0.85 × 80)
    161,       -- hr_max  (1.15 × 140)
    37.5,      -- temp_min_c
    39.7,      -- temp_max_c
    16,        -- resp_min
    36         -- resp_max
);
