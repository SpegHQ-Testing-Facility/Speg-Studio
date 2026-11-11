-- ============================================================================
-- Speg Studio / Spegtility Supabase Database Schema & Stored Procedures (RPCs)
-- Compatible with Supabase project: suakvplhyllvgqntuhht
-- Run this script in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/suakvplhyllvgqntuhht/sql/new
-- ============================================================================

-- Enable pgcrypto for UUID and cryptographic random generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. TABLES
-- ============================================================================

-- 1A. speg_users: user accounts & profiles
CREATE TABLE IF NOT EXISTS public.speg_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    avatar_data TEXT DEFAULT '',
    tag TEXT DEFAULT 'Free',
    is_banned BOOLEAN DEFAULT FALSE,
    ban_reason TEXT DEFAULT '',
    is_admin BOOLEAN DEFAULT FALSE,
    in_game BOOLEAN DEFAULT FALSE,
    game_name TEXT DEFAULT '',
    place_id TEXT DEFAULT '',
    job_id TEXT DEFAULT '',
    username_changed_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 1B. speg_keys: software license keys & HWID machine locks
CREATE TABLE IF NOT EXISTS public.speg_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key_code TEXT UNIQUE NOT NULL,
    tier TEXT DEFAULT 'Standard',            -- 'Standard', 'VIP', 'Lifetime', etc.
    tag TEXT DEFAULT '',
    status TEXT DEFAULT 'active',            -- 'active', 'redeemed', 'banned', 'revoked', 'expired'
    user_id UUID REFERENCES public.speg_users(id) ON DELETE SET NULL,
    hwid TEXT DEFAULT '',                    -- Machine-locked Hardware ID
    hwid_resets_remaining INT DEFAULT 3,
    duration_days INT DEFAULT 30,
    expires_at TIMESTAMPTZ,
    redeemed_at TIMESTAMPTZ,
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 1C. speg_friends: user friend network & pending requests
CREATE TABLE IF NOT EXISTS public.speg_friends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.speg_users(id) ON DELETE CASCADE,
    friend_id UUID REFERENCES public.speg_users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending',           -- 'pending', 'accepted'
    created_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT uq_friend_pair UNIQUE (user_id, friend_id)
);

-- 1D. speg_messages: direct messages between friends
CREATE TABLE IF NOT EXISTS public.speg_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES public.speg_users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.speg_users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================================
-- 2. INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_speg_users_email ON public.speg_users (email);
CREATE INDEX IF NOT EXISTS idx_speg_users_username ON public.speg_users (username);
CREATE INDEX IF NOT EXISTS idx_speg_keys_code ON public.speg_keys (key_code);
CREATE INDEX IF NOT EXISTS idx_speg_keys_user ON public.speg_keys (user_id);
CREATE INDEX IF NOT EXISTS idx_speg_friends_user ON public.speg_friends (user_id);
CREATE INDEX IF NOT EXISTS idx_speg_friends_friend ON public.speg_friends (friend_id);
CREATE INDEX IF NOT EXISTS idx_speg_messages_conv ON public.speg_messages (sender_id, receiver_id);

-- ============================================================================
-- 3. ROW LEVEL SECURITY (RLS)
-- ============================================================================
ALTER TABLE public.speg_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.speg_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.speg_friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.speg_messages ENABLE ROW LEVEL SECURITY;

-- Allow anon and authenticated roles full select/insert/update/delete via Security Definer RPCs
CREATE POLICY "Public full access via RPCs speg_users" ON public.speg_users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public full access via RPCs speg_keys" ON public.speg_keys FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public full access via RPCs speg_friends" ON public.speg_friends FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public full access via RPCs speg_messages" ON public.speg_messages FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- 4. STORED PROCEDURES (RPCs)
-- ============================================================================

-- 4A. speg_register: Register new user account
CREATE OR REPLACE FUNCTION public.speg_register(
    p_email TEXT,
    p_password_hash TEXT,
    p_hwid TEXT,
    p_username TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_email TEXT;
    v_username TEXT;
    v_user_id UUID;
    v_user RECORD;
BEGIN
    v_clean_email := lower(trim(p_email));
    IF v_clean_email = '' OR position('@' in v_clean_email) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid email address.');
    END IF;

    IF EXISTS (SELECT 1 FROM speg_users WHERE email = v_clean_email) THEN
        RETURN jsonb_build_object('success', false, 'error', 'An account with this email already exists.');
    END IF;

    IF p_username IS NOT NULL AND trim(p_username) <> '' THEN
        v_username := trim(p_username);
    ELSE
        v_username := split_part(v_clean_email, '@', 1);
    END IF;

    -- Avoid duplicate username
    WHILE EXISTS (SELECT 1 FROM speg_users WHERE username = v_username) LOOP
        v_username := v_username || floor(random() * 90 + 10)::text;
    END LOOP;

    INSERT INTO speg_users (email, username, password_hash, tag, last_seen_at)
    VALUES (v_clean_email, v_username, p_password_hash, 'Free', now())
    RETURNING id INTO v_user_id;

    SELECT id, email, username, avatar_data, tag, is_admin, is_banned, ban_reason, created_at
    INTO v_user
    FROM speg_users
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user', to_jsonb(v_user)
    );
END;
$$;

-- 4B. speg_login: Authenticate user, verify HWID and active key
CREATE OR REPLACE FUNCTION public.speg_login(
    p_email TEXT,
    p_password_hash TEXT,
    p_hwid TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user RECORD;
    v_key RECORD;
    v_has_valid_key BOOLEAN := false;
BEGIN
    SELECT id, email, username, password_hash, avatar_data, tag, is_banned, ban_reason, is_admin, created_at
    INTO v_user
    FROM speg_users
    WHERE email = lower(trim(p_email));

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid email or password.');
    END IF;

    IF v_user.is_banned THEN
        RETURN jsonb_build_object(
            'success', false,
            'is_banned', true,
            'banned_type', 'user',
            'error', 'Your account has been suspended: ' || coalesce(v_user.ban_reason, 'Violation of terms')
        );
    END IF;

    IF v_user.password_hash <> p_password_hash THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid email or password.');
    END IF;

    -- Update last seen
    UPDATE speg_users SET last_seen_at = now() WHERE id = v_user.id;

    -- Find active key for this user
    SELECT id, key_code, tier, tag, status, hwid, expires_at, duration_days
    INTO v_key
    FROM speg_keys
    WHERE user_id = v_user.id AND status IN ('active', 'redeemed')
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND THEN
        -- Check expiry
        IF v_key.expires_at IS NOT NULL AND v_key.expires_at < now() THEN
            UPDATE speg_keys SET status = 'expired' WHERE id = v_key.id;
            v_has_valid_key := false;
        ELSE
            -- HWID lock verification
            IF coalesce(v_key.hwid, '') = '' THEN
                UPDATE speg_keys SET hwid = p_hwid WHERE id = v_key.id;
                v_has_valid_key := true;
            ELSIF v_key.hwid = p_hwid THEN
                v_has_valid_key := true;
            ELSE
                -- HWID mismatch
                v_has_valid_key := false;
            END IF;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'user', jsonb_build_object(
            'id', v_user.id,
            'email', v_user.email,
            'username', v_user.username,
            'avatar_data', coalesce(v_user.avatar_data, ''),
            'tag', coalesce(v_key.tag, v_user.tag),
            'is_admin', v_user.is_admin,
            'created_at', v_user.created_at
        ),
        'key', CASE WHEN v_key.id IS NOT NULL THEN to_jsonb(v_key) ELSE NULL END,
        'has_valid_key', v_has_valid_key
    );
END;
$$;

-- 4C. speg_redeem_key: Redeem license key and bind HWID
CREATE OR REPLACE FUNCTION public.speg_redeem_key(
    p_user_id UUID,
    p_key_code TEXT,
    p_hwid TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_code TEXT;
    v_key RECORD;
    v_expires TIMESTAMPTZ;
BEGIN
    v_clean_code := upper(trim(p_key_code));
    SELECT * INTO v_key FROM speg_keys WHERE key_code = v_clean_code;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid license key.');
    END IF;

    IF v_key.status = 'banned' OR v_key.status = 'revoked' THEN
        RETURN jsonb_build_object('success', false, 'error', 'This key has been revoked or banned.');
    END IF;

    IF v_key.user_id IS NOT NULL AND v_key.user_id <> p_user_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'This key is already redeemed by another account.');
    END IF;

    -- Calculate expiration if not set
    IF v_key.duration_days IS NOT NULL AND v_key.duration_days > 0 THEN
        v_expires := now() + (v_key.duration_days || ' days')::interval;
    ELSE
        v_expires := NULL; -- Lifetime
    END IF;

    UPDATE speg_keys
    SET user_id = p_user_id,
        hwid = p_hwid,
        status = 'redeemed',
        redeemed_at = coalesce(redeemed_at, now()),
        expires_at = coalesce(expires_at, v_expires)
    WHERE id = v_key.id
    RETURNING * INTO v_key;

    -- Update user tag
    IF v_key.tier IS NOT NULL THEN
        UPDATE speg_users SET tag = v_key.tier WHERE id = p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'key', to_jsonb(v_key),
        'message', 'Key successfully redeemed!'
    );
END;
$$;

-- 4D. speg_verify_license: Client check verifying license validity and HWID lock
CREATE OR REPLACE FUNCTION public.speg_verify_license(
    p_user_id UUID,
    p_hwid TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user RECORD;
    v_key RECORD;
BEGIN
    SELECT is_banned, ban_reason, tag INTO v_user FROM speg_users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', false, 'error', 'User not found.');
    END IF;

    IF v_user.is_banned THEN
        RETURN jsonb_build_object(
            'valid', false,
            'banned_type', 'user',
            'error', 'Your account has been banned: ' || coalesce(v_user.ban_reason, 'Violation')
        );
    END IF;

    SELECT * INTO v_key
    FROM speg_keys
    WHERE user_id = p_user_id AND status IN ('active', 'redeemed')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', false, 'error', 'No active license key found.');
    END IF;

    IF v_key.status = 'banned' OR v_key.status = 'revoked' THEN
        RETURN jsonb_build_object('valid', false, 'banned_type', 'key', 'error', 'Your license key was revoked.');
    END IF;

    IF v_key.expires_at IS NOT NULL AND v_key.expires_at < now() THEN
        UPDATE speg_keys SET status = 'expired' WHERE id = v_key.id;
        RETURN jsonb_build_object('valid', false, 'error', 'Your license key has expired.');
    END IF;

    -- HWID check
    IF coalesce(v_key.hwid, '') = '' THEN
        UPDATE speg_keys SET hwid = p_hwid WHERE id = v_key.id;
    ELSIF v_key.hwid <> p_hwid THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'Hardware ID mismatch. This key is locked to another computer.'
        );
    END IF;

    RETURN jsonb_build_object(
        'valid', true,
        'key_code', v_key.key_code,
        'tier', v_key.tier,
        'tag', coalesce(v_key.tag, v_key.tier),
        'status', v_key.status,
        'expires_at', v_key.expires_at,
        'duration_days', v_key.duration_days
    );
END;
$$;

-- 4E. speg_refresh_key_code: Regenerate key string while retaining record
CREATE OR REPLACE FUNCTION public.speg_refresh_key_code(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_key RECORD;
    v_new_code TEXT;
BEGIN
    SELECT * INTO v_key
    FROM speg_keys
    WHERE user_id = p_user_id AND status IN ('active', 'redeemed')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'No active key to refresh.');
    END IF;

    -- Generate new code SPEG-XXXX-XXXX-XXXX
    v_new_code := 'SPEG-' || upper(substr(md5(random()::text), 1, 4)) || '-' ||
                  upper(substr(md5(random()::text), 5, 4)) || '-' ||
                  upper(substr(md5(random()::text), 9, 4));

    UPDATE speg_keys
    SET key_code = v_new_code
    WHERE id = v_key.id
    RETURNING * INTO v_key;

    RETURN jsonb_build_object(
        'success', true,
        'new_key_code', v_new_code,
        'key', to_jsonb(v_key)
    );
END;
$$;

-- 4F. speg_update_profile: Update username and avatar
CREATE OR REPLACE FUNCTION public.speg_update_profile(
    p_user_id UUID,
    p_username TEXT,
    p_avatar_data TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_uname TEXT;
BEGIN
    v_clean_uname := trim(p_username);
    IF v_clean_uname = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Username cannot be empty.');
    END IF;

    IF EXISTS (SELECT 1 FROM speg_users WHERE username = v_clean_uname AND id <> p_user_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Username is already taken.');
    END IF;

    UPDATE speg_users
    SET username = v_clean_uname,
        avatar_data = coalesce(p_avatar_data, avatar_data),
        username_changed_at = now()
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'username', v_clean_uname,
        'username_changed_at', now()
    );
END;
$$;

-- 4G. speg_update_password: Update user password
CREATE OR REPLACE FUNCTION public.speg_update_password(
    p_user_id UUID,
    p_old_password_hash TEXT,
    p_new_password_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM speg_users WHERE id = p_user_id AND password_hash = p_old_password_hash) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Current password is incorrect.');
    END IF;

    UPDATE speg_users SET password_hash = p_new_password_hash WHERE id = p_user_id;
    RETURN jsonb_build_object('success', true, 'message', 'Password updated successfully.');
END;
$$;

-- 4H. speg_reset_password: Reset user password by email
CREATE OR REPLACE FUNCTION public.speg_reset_password(
    p_email TEXT,
    p_new_password_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE speg_users
    SET password_hash = p_new_password_hash
    WHERE email = lower(trim(p_email));

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'No account found with that email.');
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Password has been reset.');
END;
$$;

-- 4I. speg_update_presence: Update real-time online and in-app status
CREATE OR REPLACE FUNCTION public.speg_update_presence(
    p_user_id UUID,
    p_in_game BOOLEAN,
    p_game_name TEXT DEFAULT NULL,
    p_place_id TEXT DEFAULT NULL,
    p_job_id TEXT DEFAULT NULL,
    p_is_offline BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE speg_users
    SET in_game = p_in_game,
        game_name = coalesce(p_game_name, ''),
        place_id = coalesce(p_place_id, ''),
        job_id = coalesce(p_job_id, ''),
        last_seen_at = CASE WHEN p_is_offline THEN now() - interval '10 minutes' ELSE now() END
    WHERE id = p_user_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 4J. speg_add_friend: Send a friend request
CREATE OR REPLACE FUNCTION public.speg_add_friend(
    p_user_id UUID,
    p_friend_username TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_friend_id UUID;
BEGIN
    SELECT id INTO v_friend_id FROM speg_users WHERE username = trim(p_friend_username);
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found.');
    END IF;

    IF v_friend_id = p_user_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'You cannot add yourself as a friend.');
    END IF;

    IF EXISTS (
        SELECT 1 FROM speg_friends
        WHERE (user_id = p_user_id AND friend_id = v_friend_id)
           OR (user_id = v_friend_id AND friend_id = p_user_id)
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'A friendship or pending request already exists.');
    END IF;

    INSERT INTO speg_friends (user_id, friend_id, status)
    VALUES (p_user_id, v_friend_id, 'pending');

    RETURN jsonb_build_object('success', true, 'message', 'Friend request sent!');
END;
$$;

-- 4K. speg_accept_friend: Accept friend request
CREATE OR REPLACE FUNCTION public.speg_accept_friend(
    p_user_id UUID,
    p_requester_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE speg_friends
    SET status = 'accepted'
    WHERE user_id = p_requester_id AND friend_id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Friend request not found.');
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Friend request accepted!');
END;
$$;

-- 4L. speg_reject_friend: Reject or cancel request
CREATE OR REPLACE FUNCTION public.speg_reject_friend(
    p_user_id UUID,
    p_requester_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM speg_friends
    WHERE (user_id = p_requester_id AND friend_id = p_user_id)
       OR (user_id = p_user_id AND friend_id = p_requester_id);

    RETURN jsonb_build_object('success', true, 'message', 'Request removed.');
END;
$$;

-- 4M. speg_unfriend: Remove friend
CREATE OR REPLACE FUNCTION public.speg_unfriend(
    p_user_id UUID,
    p_friend_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM speg_friends
    WHERE (user_id = p_user_id AND friend_id = p_friend_id)
       OR (user_id = p_friend_id AND friend_id = p_user_id);

    RETURN jsonb_build_object('success', true, 'message', 'Friend removed.');
END;
$$;

-- 4N. speg_get_friends: Get accepted friends list with presence
CREATE OR REPLACE FUNCTION public.speg_get_friends(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_res JSONB;
BEGIN
    SELECT coalesce(jsonb_agg(
        jsonb_build_object(
            'id', u.id,
            'username', u.username,
            'avatar_data', coalesce(u.avatar_data, ''),
            'tag', coalesce(u.tag, 'Free'),
            'in_game', u.in_game,
            'game_name', coalesce(u.game_name, ''),
            'is_online', (u.last_seen_at > now() - interval '3 minutes')
        )
    ), '[]'::jsonb) INTO v_res
    FROM (
        SELECT friend_id AS fid FROM speg_friends WHERE user_id = p_user_id AND status = 'accepted'
        UNION
        SELECT user_id AS fid FROM speg_friends WHERE friend_id = p_user_id AND status = 'accepted'
    ) f
    JOIN speg_users u ON u.id = f.fid;

    RETURN v_res;
END;
$$;

-- 4O. speg_get_friend_requests: Get incoming pending requests
CREATE OR REPLACE FUNCTION public.speg_get_friend_requests(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_res JSONB;
BEGIN
    SELECT coalesce(jsonb_agg(
        jsonb_build_object(
            'id', u.id,
            'username', u.username,
            'avatar_data', coalesce(u.avatar_data, ''),
            'tag', coalesce(u.tag, 'Free'),
            'created_at', f.created_at
        )
    ), '[]'::jsonb) INTO v_res
    FROM speg_friends f
    JOIN speg_users u ON u.id = f.user_id
    WHERE f.friend_id = p_user_id AND f.status = 'pending';

    RETURN v_res;
END;
$$;

-- 4P. speg_get_pending_requests: Get outgoing pending requests
CREATE OR REPLACE FUNCTION public.speg_get_pending_requests(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_res JSONB;
BEGIN
    SELECT coalesce(jsonb_agg(
        jsonb_build_object(
            'id', u.id,
            'username', u.username,
            'avatar_data', coalesce(u.avatar_data, ''),
            'tag', coalesce(u.tag, 'Free'),
            'created_at', f.created_at
        )
    ), '[]'::jsonb) INTO v_res
    FROM speg_friends f
    JOIN speg_users u ON u.id = f.friend_id
    WHERE f.user_id = p_user_id AND f.status = 'pending';

    RETURN v_res;
END;
$$;

-- 4Q. speg_get_social_overview: Unread count & pending badge counters
CREATE OR REPLACE FUNCTION public.speg_get_social_overview(
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_unread INT := 0;
    v_pending INT := 0;
BEGIN
    SELECT count(*) INTO v_unread FROM speg_messages WHERE receiver_id = p_user_id AND read_at IS NULL;
    SELECT count(*) INTO v_pending FROM speg_friends WHERE friend_id = p_user_id AND status = 'pending';

    RETURN jsonb_build_object(
        'unread_messages', v_unread,
        'pending_requests', v_pending,
        'total_badge_count', v_unread + v_pending
    );
END;
$$;

-- 4R. speg_send_message: Send direct message
CREATE OR REPLACE FUNCTION public.speg_send_message(
    p_sender_id UUID,
    p_receiver_id UUID,
    p_content TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_msg RECORD;
BEGIN
    INSERT INTO speg_messages (sender_id, receiver_id, content)
    VALUES (p_sender_id, p_receiver_id, trim(p_content))
    RETURNING * INTO v_msg;

    RETURN jsonb_build_object(
        'success', true,
        'message', to_jsonb(v_msg)
    );
END;
$$;

-- 4S. speg_get_messages: Read direct message history
CREATE OR REPLACE FUNCTION public.speg_get_messages(
    p_user_id UUID,
    p_friend_id UUID,
    p_limit INT DEFAULT 60
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_res JSONB;
BEGIN
    -- Mark received messages as read
    UPDATE speg_messages
    SET read_at = now()
    WHERE sender_id = p_friend_id AND receiver_id = p_user_id AND read_at IS NULL;

    SELECT coalesce(jsonb_agg(m_row), '[]'::jsonb) INTO v_res
    FROM (
        SELECT id, sender_id, receiver_id, content, read_at, created_at
        FROM speg_messages
        WHERE (sender_id = p_user_id AND receiver_id = p_friend_id)
           OR (sender_id = p_friend_id AND receiver_id = p_user_id)
        ORDER BY created_at ASC
        LIMIT p_limit
    ) m_row;

    RETURN v_res;
END;
$$;

-- 4T. speg_generate_key: Admin helper to create new keys
CREATE OR REPLACE FUNCTION public.speg_generate_key(
    p_tier TEXT DEFAULT 'VIP',
    p_duration_days INT DEFAULT 30,
    p_tag TEXT DEFAULT '',
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code TEXT;
    v_key RECORD;
BEGIN
    v_code := 'SPEG-' || upper(substr(md5(random()::text), 1, 4)) || '-' ||
              upper(substr(md5(random()::text), 5, 4)) || '-' ||
              upper(substr(md5(random()::text), 9, 4));

    INSERT INTO speg_keys (key_code, tier, tag, duration_days, notes, status)
    VALUES (v_code, p_tier, coalesce(nullif(p_tag, ''), p_tier), p_duration_days, p_notes, 'active')
    RETURNING * INTO v_key;

    RETURN jsonb_build_object(
        'success', true,
        'key', to_jsonb(v_key)
    );
END;
$$;

-- ============================================================================
-- 5. GRANTS FOR SUPABASE (anon, authenticated, service_role)
-- ============================================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

-- ============================================================================
-- 6. SEED INITIAL SAMPLE LICENSE KEYS
-- Use any of these keys to activate your client immediately after running SQL!
-- ============================================================================
INSERT INTO public.speg_keys (key_code, tier, tag, duration_days, notes, status)
VALUES
    ('SPEG-STUDIO-VIP-2026', 'VIP', 'VIP', 365, 'Speg Studio 1-Year VIP License', 'active'),
    ('SPEG-STUDIO-PRO-LIFETIME', 'Lifetime', 'Lifetime', 0, 'Speg Studio Lifetime Pro License', 'active'),
    ('SPEG-STUDIO-CREATOR-99', 'Creator', 'Creator', 90, 'Speg Studio Creator 90-Day Key', 'active'),
    ('SPEG-STUDIO-TRIAL-KEY', 'Standard', 'Trial', 14, 'Speg Studio 14-Day Free Trial', 'active')
ON CONFLICT (key_code) DO NOTHING;
