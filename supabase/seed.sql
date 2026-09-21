insert into public.sections (name, display_order)
values
  ('State Dayshift RN', 0),
  ('PRN Dayshift RN', 1),
  ('State Dayshift LPN', 2),
  ('PRN Nightshift RN', 3),
  ('Nightshift LPN', 4),
  ('CNA', 5),
  ('Unit Clerks', 6),
  ('Unit Clerk PRN', 7)
on conflict (name) do nothing;
