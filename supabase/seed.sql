insert into public.sections (name, display_order)
values
  ('State dayshift RN', 0),
  ('PRN dayshift RN', 1),
  ('State dayshift LPN', 2),
  ('PRN nightshift RN', 3),
  ('Nightshift LPN', 4),
  ('CNA', 5),
  ('Unit clerks', 6),
  ('Unit clerk PRN', 7)
on conflict (name) do nothing;
