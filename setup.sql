-- Haaloo backend. Paste this whole file into Supabase > SQL Editor > Run.

create table profiles(id uuid primary key references auth.users on delete cascade, username text unique not null);
create table posts(id bigserial primary key, user_id uuid not null references auth.users on delete cascade, username text not null,
  caption text, url text not null, dur int default 0, kind text default 'reel', created_at timestamptz default now());
create table likes(post_id bigint references posts on delete cascade, user_id uuid references auth.users on delete cascade, primary key(post_id,user_id));
create table comments(id bigserial primary key, post_id bigint references posts on delete cascade, user_id uuid not null references auth.users on delete cascade,
  username text not null, body text not null, created_at timestamptz default now());
create table follows(follower uuid references auth.users on delete cascade, followee uuid references auth.users on delete cascade, primary key(follower,followee));
create table messages(id bigserial primary key, room text not null, user_id uuid not null references auth.users on delete cascade,
  username text not null, body text not null, created_at timestamptz default now());

-- Create a profile automatically when someone signs up
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,username) values(new.id, new.raw_user_meta_data->>'username'); return new; end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

-- Security: every table is locked, then opened only as listed
alter table profiles enable row level security;
alter table posts enable row level security;
alter table likes enable row level security;
alter table comments enable row level security;
alter table follows enable row level security;
alter table messages enable row level security;

create policy "read profiles" on profiles for select using (true);
create policy "read posts" on posts for select using (true);
create policy "add own post" on posts for insert with check (user_id=auth.uid());
create policy "delete own post" on posts for delete using (user_id=auth.uid());
create policy "read likes" on likes for select using (true);
create policy "add own like" on likes for insert with check (user_id=auth.uid());
create policy "remove own like" on likes for delete using (user_id=auth.uid());
create policy "read comments" on comments for select using (true);
create policy "add own comment" on comments for insert with check (user_id=auth.uid());
create policy "read follows" on follows for select using (true);
create policy "follow" on follows for insert with check (follower=auth.uid());
create policy "unfollow" on follows for delete using (follower=auth.uid());

-- Public rooms are open to everyone signed in. Private chats (room "dm:a|b") only to the two people named.
create function in_room(r text) returns boolean language sql stable security definer set search_path=public as $$
  select r not like 'dm:%' or (select username from profiles where id=auth.uid()) = any(string_to_array(substr(r,4),'|')) $$;
create policy "read messages" on messages for select using (in_room(room));
create policy "send message" on messages for insert with check (user_id=auth.uid() and in_room(room));

-- Video storage (50 MB per file, public links, upload only into your own folder)
insert into storage.buckets(id,name,public,file_size_limit) values('videos','videos',true,52428800);
create policy "upload own videos" on storage.objects for insert to authenticated
  with check (bucket_id='videos' and (storage.foldername(name))[1]=auth.uid()::text);

-- Live chat
alter publication supabase_realtime add table messages;
