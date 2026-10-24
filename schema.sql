-- ID Management Portal schema. Run once in Supabase > SQL Editor.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null,
  role text not null default 'team_lead' check (role in ('admin','team_lead')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.files (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  received_from text not null,
  assigned_to text not null,
  team_lead_id uuid not null references public.profiles(id),
  assignment_date date not null default current_date,
  total_ids int not null check (total_ids between 1 and 500),
  notes text,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.id_records (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references public.files(id) on delete cascade,
  person_number int not null,
  uid text, password text, reason text, reason_other text, remarks text,
  updated_by uuid references public.profiles(id),
  last_updated timestamptz,
  unique (file_id, person_number),
  check (reason is null or reason in ('Wrong Pass','1st Reach','Suspend','Suspend Working','Name Issue','Email','0 Response','1 Response','2 Response','Other'))
);
create table public.id_update_history (
  id uuid primary key default gen_random_uuid(),
  id_record_id uuid not null references public.id_records(id) on delete cascade,
  previous_values jsonb, new_values jsonb,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);
create index on public.files(team_lead_id);
create index on public.files(assignment_date);
create index on public.id_records(file_id);
create index on public.id_records(reason);
create index on public.id_update_history(id_record_id);

-- helpers (security definer so RLS policies can look up the caller's role)
create function public.is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin' and active) $$;
create function public.is_active() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and active) $$;
create function public.owns_file(fid uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from files where id=fid and team_lead_id=auth.uid()) and public.is_active() $$;

-- new auth user -> profile (always team_lead; promote admin via SQL, see README)
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,email,full_name) values (new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- create file + N records atomically
create function public.create_file_with_records(p_name text,p_from text,p_to text,p_date date,p_total int,p_notes text)
returns uuid language plpgsql security definer set search_path=public as $$
declare fid uuid;
begin
  if not public.is_active() then raise exception 'Not authorized'; end if;
  if p_total is null or p_total<1 or p_total>500 then raise exception 'Total IDs must be 1-500'; end if;
  insert into files(file_name,received_from,assigned_to,team_lead_id,assignment_date,total_ids,notes)
    values (p_name,p_from,p_to,auth.uid(),coalesce(p_date,current_date),p_total,p_notes) returning id into fid;
  insert into id_records(file_id,person_number) select fid,g from generate_series(1,p_total) g;
  return fid;
end $$;

-- audit + stamp trigger; file_id/person_number are immutable
create function public.log_record_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
  new.file_id:=old.file_id; new.person_number:=old.person_number;
  if (old.uid,old.password,old.reason,old.reason_other,old.remarks) is distinct from (new.uid,new.password,new.reason,new.reason_other,new.remarks) then
    new.updated_by:=auth.uid(); new.last_updated:=now();
    insert into id_update_history(id_record_id,previous_values,new_values,updated_by)
    values (old.id,
      jsonb_build_object('uid',old.uid,'password',old.password,'reason',old.reason,'reason_other',old.reason_other,'remarks',old.remarks),
      jsonb_build_object('uid',new.uid,'password',new.password,'reason',new.reason,'reason_other',new.reason_other,'remarks',new.remarks),
      auth.uid());
    update files set updated_at=now() where id=new.file_id;
  else
    new.updated_by:=old.updated_by; new.last_updated:=old.last_updated;
  end if;
  return new;
end $$;
create trigger id_records_audit before update on public.id_records for each row execute function public.log_record_change();

-- RLS
alter table public.profiles enable row level security;
alter table public.files enable row level security;
alter table public.id_records enable row level security;
alter table public.id_update_history enable row level security;

create policy profiles_read on public.profiles for select using (id=auth.uid() or public.is_admin());
create policy profiles_admin_update on public.profiles for update using (public.is_admin()) with check (public.is_admin());

create policy files_read on public.files for select using (public.is_admin() or (team_lead_id=auth.uid() and public.is_active()));
create policy files_update on public.files for update using (public.is_admin() or (team_lead_id=auth.uid() and public.is_active()))
  with check (public.is_admin() or team_lead_id=auth.uid());
create policy files_admin_delete on public.files for delete using (public.is_admin());
-- inserts go through create_file_with_records() only (no insert policy)

create policy rec_read on public.id_records for select using (public.is_admin() or public.owns_file(file_id));
create policy rec_update on public.id_records for update using (public.is_admin() or public.owns_file(file_id));
create policy rec_admin_delete on public.id_records for delete using (public.is_admin());

create policy hist_read on public.id_update_history for select using (
  public.is_admin() or exists(select 1 from id_records r where r.id=id_record_id and public.owns_file(r.file_id)));

revoke all on all tables in schema public from anon;
grant select, update on public.profiles, public.files, public.id_records to authenticated;
grant delete on public.files, public.id_records to authenticated;
grant select on public.id_update_history to authenticated;
grant execute on function public.create_file_with_records(text,text,text,date,int,text) to authenticated;
