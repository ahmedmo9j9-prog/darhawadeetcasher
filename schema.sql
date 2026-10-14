-- نظام حواديت: الصق الملف كله في Supabase > SQL Editor ثم Run

create table profiles(id uuid primary key references auth.users on delete cascade, username text unique not null, role text not null default 'cashier');
create table books(id bigint generated always as identity primary key, title text not null, author text, isbn text unique, price numeric not null default 0, cost numeric not null default 0, qty int not null default 0);
create table sales(id bigint generated always as identity primary key, place text not null, discount numeric not null default 0, total numeric not null, pay text, user_id uuid default auth.uid(), created_at timestamptz default now());
create table sale_items(id bigint generated always as identity primary key, sale_id bigint references sales on delete cascade, book_id bigint references books on delete set null, title text, qty int not null, price numeric not null);
create table expenses(id bigint generated always as identity primary key, category text, amount numeric not null, place text, note text, user_id uuid default auth.uid(), created_at timestamptz default now());
create table custody(id bigint generated always as identity primary key, holder text not null, amount numeric not null, spent numeric not null default 0, note text, created_at timestamptz default now());
create table stock_log(id bigint generated always as identity primary key, book_id bigint, delta int not null, user_id uuid default auth.uid(), created_at timestamptz default now());

create function is_member() returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid()) $$;
create function is_admin() returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;

create function log_qty() returns trigger language plpgsql security definer set search_path=public as $$
begin if new.qty<>old.qty then insert into stock_log(book_id,delta) values(new.id,new.qty-old.qty); end if; return new; end $$;
create trigger t_qty after update on books for each row execute function log_qty();

create function make_sale(p_place text,p_disc numeric,p_pay text,p_items jsonb) returns bigint language plpgsql security definer set search_path=public as $$
declare sid bigint; t numeric;
begin
  if not is_member() then raise exception 'غير مصرح'; end if;
  select coalesce(sum((i->>'qty')::int*(i->>'price')::numeric),0)*(1-p_disc/100) into t from jsonb_array_elements(p_items) i;
  insert into sales(place,discount,total,pay) values(p_place,p_disc,t,p_pay) returning id into sid;
  insert into sale_items(sale_id,book_id,title,qty,price) select sid,(i->>'id')::bigint,i->>'title',(i->>'qty')::int,(i->>'price')::numeric from jsonb_array_elements(p_items) i;
  update books b set qty=b.qty-x.q from (select (i->>'id')::bigint id,(i->>'qty')::int q from jsonb_array_elements(p_items) i) x where b.id=x.id;
  return sid;
end $$;

alter table profiles enable row level security;
alter table books enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table expenses enable row level security;
alter table custody enable row level security;
alter table stock_log enable row level security;

create policy r_profiles on profiles for select to authenticated using (is_member() or id=auth.uid());
create policy w_profiles on profiles for all to authenticated using (is_admin()) with check (is_admin());
create policy r_books on books for select to authenticated using (is_member());
create policy w_books on books for all to authenticated using (is_admin()) with check (is_admin());
create policy r_sales on sales for select to authenticated using (is_member());
create policy r_items on sale_items for select to authenticated using (is_member());
create policy r_exp on expenses for select to authenticated using (is_member());
create policy i_exp on expenses for insert to authenticated with check (is_member());
create policy w_exp on expenses for all to authenticated using (is_admin()) with check (is_admin());
create policy a_cus on custody for all to authenticated using (is_admin()) with check (is_admin());
create policy a_log on stock_log for select to authenticated using (is_admin());

-- بعد إنشاء أول مستخدم من لوحة Supabase (الخطوة 3 في الشرح) شغّل السطر ده مرة واحدة:
-- insert into profiles(id,username,role) select id,'admin','admin' from auth.users where email='admin@hawadeet.local';
