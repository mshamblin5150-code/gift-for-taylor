insert into public.sections (name, display_order)
values
  ('State dayshift RN', 0),
  ('PRN dayshift RN', 1),
  ('State nightshift RN', 2),
  ('PRN nightshift RN', 3),
  ('CNA', 4),
  ('Unit clerks', 5)
on conflict (name) do nothing;
