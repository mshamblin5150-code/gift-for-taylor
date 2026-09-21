-- Correct the original Section labels without changing any custom names.
update public.sections
set name = case name
  when 'State dayshift RN' then 'State Dayshift RN'
  when 'PRN dayshift RN' then 'PRN Dayshift RN'
  when 'State dayshift LPN' then 'State Dayshift LPN'
  when 'PRN nightshift RN' then 'PRN Nightshift RN'
  when 'Unit clerks' then 'Unit Clerks'
  when 'Unit clerk PRN' then 'Unit Clerk PRN'
end
where name in (
  'State dayshift RN',
  'PRN dayshift RN',
  'State dayshift LPN',
  'PRN nightshift RN',
  'Unit clerks',
  'Unit clerk PRN'
);
