--
-- PostgreSQL database dump
--

\restrict 6zSRlIeIJToO2mFoK7MjKJnMBidE4PBXcDglsGy7RI7WJTfkOn5iICZmla4IRYT

-- Dumped from database version 15.14 (Homebrew)
-- Dumped by pg_dump version 15.14 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    record_id uuid
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: advancements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.advancements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    character_id uuid NOT NULL,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: attunements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attunements (
    id bigint NOT NULL,
    character_id uuid NOT NULL,
    site_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: attunements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.attunements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attunements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.attunements_id_seq OWNED BY public.attunements.id;


--
-- Name: campaign_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    campaign_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name character varying,
    active boolean DEFAULT true NOT NULL,
    is_master_template boolean DEFAULT false NOT NULL,
    seeded_at timestamp(6) without time zone
);


--
-- Name: carries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    character_id uuid NOT NULL,
    weapon_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: character_effects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.character_effects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    character_id uuid,
    vehicle_id uuid,
    description character varying,
    severity character varying DEFAULT 'info'::character varying NOT NULL,
    change character varying,
    action_value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name character varying,
    shot_id uuid
);


--
-- Name: character_schticks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.character_schticks (
    id bigint NOT NULL,
    character_id uuid NOT NULL,
    schtick_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: character_schticks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.character_schticks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: character_schticks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.character_schticks_id_seq OWNED BY public.character_schticks.id;


--
-- Name: characters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.characters (
    name character varying NOT NULL,
    defense integer,
    impairments integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    color character varying,
    user_id uuid,
    action_values jsonb,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid,
    active boolean DEFAULT true NOT NULL,
    description jsonb,
    skills jsonb,
    faction_id uuid,
    image_url character varying,
    task boolean,
    notion_page_id uuid,
    last_synced_to_notion_at timestamp(6) without time zone,
    summary character varying,
    juncture_id uuid,
    wealth character varying,
    is_template boolean,
    status jsonb DEFAULT '[]'::jsonb
);


--
-- Name: chase_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chase_relationships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pursuer_id uuid NOT NULL,
    evader_id uuid NOT NULL,
    fight_id uuid NOT NULL,
    "position" character varying DEFAULT 'far'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT different_vehicles CHECK ((pursuer_id <> evader_id)),
    CONSTRAINT position_values CHECK ((("position")::text = ANY ((ARRAY['near'::character varying, 'far'::character varying])::text[])))
);


--
-- Name: effects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.effects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fight_id uuid,
    user_id uuid,
    start_sequence integer,
    end_sequence integer,
    start_shot integer,
    end_shot integer,
    severity character varying,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name character varying
);


--
-- Name: factions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    campaign_id uuid NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: fight_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fight_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fight_id uuid NOT NULL,
    event_type character varying,
    description character varying,
    details jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: fights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fights (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    sequence integer DEFAULT 0 NOT NULL,
    campaign_id uuid,
    active boolean DEFAULT true NOT NULL,
    archived boolean DEFAULT false NOT NULL,
    description text,
    server_id bigint,
    fight_message_id character varying,
    channel_id bigint,
    started_at timestamp without time zone,
    ended_at timestamp without time zone,
    season integer,
    session integer,
    action_id uuid
);


--
-- Name: image_positions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.image_positions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    positionable_type character varying NOT NULL,
    positionable_id uuid NOT NULL,
    context character varying NOT NULL,
    x_position double precision DEFAULT 0.0,
    y_position double precision DEFAULT 0.0,
    style_overrides jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    user_id uuid NOT NULL,
    email character varying,
    pending_user_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    maximum_count integer,
    remaining_count integer
);


--
-- Name: junctures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.junctures (
    name character varying,
    description character varying,
    active boolean DEFAULT true NOT NULL,
    faction_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    notion_page_id uuid,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    party_id uuid NOT NULL,
    character_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    vehicle_id uuid
);


--
-- Name: onboarding_progresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.onboarding_progresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    first_campaign_created_at timestamp without time zone,
    first_character_created_at timestamp without time zone,
    first_fight_created_at timestamp without time zone,
    first_faction_created_at timestamp without time zone,
    first_party_created_at timestamp without time zone,
    first_site_created_at timestamp without time zone,
    congratulations_dismissed_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    first_campaign_activated_at timestamp(6) without time zone
);


--
-- Name: parties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    description character varying,
    campaign_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    faction_id uuid,
    juncture_id uuid,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: schticks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schticks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    description character varying,
    prerequisite_id uuid,
    category character varying,
    path character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    color character varying,
    image_url character varying,
    bonus boolean,
    archetypes jsonb,
    name character varying,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: shots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fight_id uuid NOT NULL,
    character_id uuid,
    vehicle_id uuid,
    shot integer,
    "position" character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    count integer DEFAULT 0,
    color character varying,
    driver_id uuid,
    impairments integer DEFAULT 0,
    driving_id uuid,
    location character varying,
    was_rammed_or_damaged boolean DEFAULT false NOT NULL
);


--
-- Name: sites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    campaign_id uuid,
    name character varying,
    faction_id uuid,
    juncture_id uuid,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name character varying DEFAULT ''::character varying NOT NULL,
    last_name character varying DEFAULT ''::character varying NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    jti character varying NOT NULL,
    avatar_url character varying,
    admin boolean,
    gamemaster boolean,
    confirmation_token character varying,
    confirmed_at timestamp(6) without time zone,
    confirmation_sent_at timestamp(6) without time zone,
    unconfirmed_email character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying,
    locked_at timestamp(6) without time zone,
    current_campaign_id uuid,
    name character varying,
    active boolean DEFAULT true NOT NULL,
    pending_invitation_id uuid
);


--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vehicles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    action_values jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id uuid,
    color character varying,
    impairments integer,
    campaign_id uuid,
    active boolean DEFAULT true NOT NULL,
    faction_id uuid,
    image_url character varying,
    task boolean,
    notion_page_id uuid,
    last_synced_to_notion_at timestamp(6) without time zone,
    summary character varying,
    juncture_id uuid,
    description jsonb
);


--
-- Name: weapons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weapons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    name character varying NOT NULL,
    description character varying,
    damage integer NOT NULL,
    concealment integer,
    reload_value integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    juncture character varying,
    mook_bonus integer DEFAULT 0 NOT NULL,
    category character varying,
    kachunk boolean,
    image_url character varying,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: attunements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attunements ALTER COLUMN id SET DEFAULT nextval('public.attunements_id_seq'::regclass);


--
-- Name: character_schticks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_schticks ALTER COLUMN id SET DEFAULT nextval('public.character_schticks_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: advancements advancements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.advancements
    ADD CONSTRAINT advancements_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attunements attunements_character_id_site_id_index; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attunements
    ADD CONSTRAINT attunements_character_id_site_id_index UNIQUE (character_id, site_id);


--
-- Name: attunements attunements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attunements
    ADD CONSTRAINT attunements_pkey PRIMARY KEY (id);


--
-- Name: campaign_memberships campaign_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_memberships
    ADD CONSTRAINT campaign_memberships_pkey PRIMARY KEY (id);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);


--
-- Name: carries carries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carries
    ADD CONSTRAINT carries_pkey PRIMARY KEY (id);


--
-- Name: character_effects character_effects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_effects
    ADD CONSTRAINT character_effects_pkey PRIMARY KEY (id);


--
-- Name: character_schticks character_schticks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_schticks
    ADD CONSTRAINT character_schticks_pkey PRIMARY KEY (id);


--
-- Name: characters characters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT characters_pkey PRIMARY KEY (id);


--
-- Name: chase_relationships chase_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chase_relationships
    ADD CONSTRAINT chase_relationships_pkey PRIMARY KEY (id);


--
-- Name: effects effects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.effects
    ADD CONSTRAINT effects_pkey PRIMARY KEY (id);


--
-- Name: factions factions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factions
    ADD CONSTRAINT factions_pkey PRIMARY KEY (id);


--
-- Name: fight_events fight_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fight_events
    ADD CONSTRAINT fight_events_pkey PRIMARY KEY (id);


--
-- Name: fights fights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fights
    ADD CONSTRAINT fights_pkey PRIMARY KEY (id);


--
-- Name: image_positions image_positions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_positions
    ADD CONSTRAINT image_positions_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: junctures junctures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.junctures
    ADD CONSTRAINT junctures_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_party_id_character_id_index; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_party_id_character_id_index UNIQUE (party_id, character_id);


--
-- Name: memberships memberships_party_id_vehicle_id_index; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_party_id_vehicle_id_index UNIQUE (party_id, vehicle_id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: onboarding_progresses onboarding_progresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.onboarding_progresses
    ADD CONSTRAINT onboarding_progresses_pkey PRIMARY KEY (id);


--
-- Name: parties parties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parties
    ADD CONSTRAINT parties_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: schticks schticks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schticks
    ADD CONSTRAINT schticks_pkey PRIMARY KEY (id);


--
-- Name: shots shots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shots
    ADD CONSTRAINT shots_pkey PRIMARY KEY (id);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);


--
-- Name: weapons weapons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weapons
    ADD CONSTRAINT weapons_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_on_record_type_name_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_record_type_name_id ON public.active_storage_attachments USING btree (record_type, name, record_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_advancements_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_advancements_on_character_id ON public.advancements USING btree (character_id);


--
-- Name: index_attunements_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attunements_on_character_id ON public.attunements USING btree (character_id);


--
-- Name: index_attunements_on_site_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attunements_on_site_id ON public.attunements USING btree (site_id);


--
-- Name: index_campaign_memberships_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_memberships_on_campaign_id ON public.campaign_memberships USING btree (campaign_id);


--
-- Name: index_campaign_memberships_on_campaign_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_memberships_on_campaign_id_and_user_id ON public.campaign_memberships USING btree (campaign_id, user_id);


--
-- Name: index_campaign_memberships_on_user_and_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_memberships_on_user_and_created ON public.campaign_memberships USING btree (user_id, created_at);


--
-- Name: index_campaign_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaign_memberships_on_user_id ON public.campaign_memberships USING btree (user_id);


--
-- Name: index_campaigns_on_active_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaigns_on_active_and_created_at ON public.campaigns USING btree (active, created_at);


--
-- Name: index_campaigns_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaigns_on_lower_name ON public.campaigns USING btree (lower((name)::text));


--
-- Name: index_campaigns_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_campaigns_on_user_id ON public.campaigns USING btree (user_id);


--
-- Name: index_carries_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_carries_on_character_id ON public.carries USING btree (character_id);


--
-- Name: index_carries_on_weapon_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_carries_on_weapon_id ON public.carries USING btree (weapon_id);


--
-- Name: index_character_effects_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_character_effects_on_character_id ON public.character_effects USING btree (character_id);


--
-- Name: index_character_effects_on_shot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_character_effects_on_shot_id ON public.character_effects USING btree (shot_id);


--
-- Name: index_character_effects_on_vehicle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_character_effects_on_vehicle_id ON public.character_effects USING btree (vehicle_id);


--
-- Name: index_character_id_on_schtick_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_character_id_on_schtick_id ON public.character_schticks USING btree (character_id, schtick_id);


--
-- Name: index_character_schticks_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_character_schticks_on_character_id ON public.character_schticks USING btree (character_id);


--
-- Name: index_character_schticks_on_schtick_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_character_schticks_on_schtick_id ON public.character_schticks USING btree (schtick_id);


--
-- Name: index_characters_on_action_values; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_action_values ON public.characters USING gin (action_values);


--
-- Name: index_characters_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_active ON public.characters USING btree (active);


--
-- Name: index_characters_on_campaign_active_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_campaign_active_created ON public.characters USING btree (campaign_id, active, created_at);


--
-- Name: index_characters_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_campaign_id ON public.characters USING btree (campaign_id);


--
-- Name: index_characters_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_campaign_id_and_active ON public.characters USING btree (campaign_id, active);


--
-- Name: index_characters_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_created_at ON public.characters USING btree (created_at);


--
-- Name: index_characters_on_faction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_faction_id ON public.characters USING btree (faction_id);


--
-- Name: index_characters_on_juncture_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_juncture_id ON public.characters USING btree (juncture_id);


--
-- Name: index_characters_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_lower_name ON public.characters USING btree (lower((name)::text));


--
-- Name: index_characters_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_status ON public.characters USING gin (status);


--
-- Name: index_characters_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_characters_on_user_id ON public.characters USING btree (user_id);


--
-- Name: index_chase_relationships_on_evader_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chase_relationships_on_evader_id ON public.chase_relationships USING btree (evader_id);


--
-- Name: index_chase_relationships_on_fight_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chase_relationships_on_fight_id ON public.chase_relationships USING btree (fight_id);


--
-- Name: index_chase_relationships_on_pursuer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chase_relationships_on_pursuer_id ON public.chase_relationships USING btree (pursuer_id);


--
-- Name: index_effects_on_fight_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_effects_on_fight_id ON public.effects USING btree (fight_id);


--
-- Name: index_effects_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_effects_on_user_id ON public.effects USING btree (user_id);


--
-- Name: index_factions_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_factions_on_active ON public.factions USING btree (active);


--
-- Name: index_factions_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_factions_on_campaign_id ON public.factions USING btree (campaign_id);


--
-- Name: index_factions_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_factions_on_campaign_id_and_active ON public.factions USING btree (campaign_id, active);


--
-- Name: index_factions_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_factions_on_lower_name ON public.factions USING btree (lower((name)::text));


--
-- Name: index_fight_events_on_fight_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fight_events_on_fight_id ON public.fight_events USING btree (fight_id);


--
-- Name: index_fights_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fights_on_active ON public.fights USING btree (active);


--
-- Name: index_fights_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fights_on_campaign_id ON public.fights USING btree (campaign_id);


--
-- Name: index_fights_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fights_on_campaign_id_and_active ON public.fights USING btree (campaign_id, active);


--
-- Name: index_fights_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fights_on_lower_name ON public.fights USING btree (lower((name)::text));


--
-- Name: index_image_positions_on_positionable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_positions_on_positionable ON public.image_positions USING btree (positionable_type, positionable_id);


--
-- Name: index_image_positions_on_positionable_and_context; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_image_positions_on_positionable_and_context ON public.image_positions USING btree (positionable_type, positionable_id, context);


--
-- Name: index_invitations_on_campaign_and_pending_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_campaign_and_pending_user ON public.invitations USING btree (campaign_id, pending_user_id);


--
-- Name: index_invitations_on_campaign_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_campaign_email ON public.invitations USING btree (campaign_id, email);


--
-- Name: index_invitations_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_campaign_id ON public.invitations USING btree (campaign_id);


--
-- Name: index_invitations_on_pending_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_pending_user_id ON public.invitations USING btree (pending_user_id);


--
-- Name: index_invitations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_user_id ON public.invitations USING btree (user_id);


--
-- Name: index_junctures_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_junctures_on_active ON public.junctures USING btree (active);


--
-- Name: index_junctures_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_junctures_on_campaign_id ON public.junctures USING btree (campaign_id);


--
-- Name: index_junctures_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_junctures_on_campaign_id_and_active ON public.junctures USING btree (campaign_id, active);


--
-- Name: index_junctures_on_faction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_junctures_on_faction_id ON public.junctures USING btree (faction_id);


--
-- Name: index_junctures_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_junctures_on_lower_name ON public.junctures USING btree (lower((name)::text));


--
-- Name: index_memberships_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_character_id ON public.memberships USING btree (character_id);


--
-- Name: index_memberships_on_party_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_party_id ON public.memberships USING btree (party_id);


--
-- Name: index_memberships_on_vehicle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_vehicle_id ON public.memberships USING btree (vehicle_id);


--
-- Name: index_onboarding_progresses_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_onboarding_progresses_on_user_id ON public.onboarding_progresses USING btree (user_id);


--
-- Name: index_parties_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parties_on_active ON public.parties USING btree (active);


--
-- Name: index_parties_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parties_on_campaign_id ON public.parties USING btree (campaign_id);


--
-- Name: index_parties_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parties_on_campaign_id_and_active ON public.parties USING btree (campaign_id, active);


--
-- Name: index_parties_on_faction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parties_on_faction_id ON public.parties USING btree (faction_id);


--
-- Name: index_parties_on_juncture_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parties_on_juncture_id ON public.parties USING btree (juncture_id);


--
-- Name: index_parties_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_parties_on_lower_name ON public.parties USING btree (lower((name)::text));


--
-- Name: index_schticks_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schticks_on_active ON public.schticks USING btree (active);


--
-- Name: index_schticks_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schticks_on_campaign_id ON public.schticks USING btree (campaign_id);


--
-- Name: index_schticks_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schticks_on_campaign_id_and_active ON public.schticks USING btree (campaign_id, active);


--
-- Name: index_schticks_on_category_name_and_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_schticks_on_category_name_and_campaign ON public.schticks USING btree (category, name, campaign_id);


--
-- Name: index_schticks_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schticks_on_lower_name ON public.schticks USING btree (lower((name)::text));


--
-- Name: index_schticks_on_prerequisite_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schticks_on_prerequisite_id ON public.schticks USING btree (prerequisite_id);


--
-- Name: index_shots_on_character_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shots_on_character_id ON public.shots USING btree (character_id);


--
-- Name: index_shots_on_driver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shots_on_driver_id ON public.shots USING btree (driver_id);


--
-- Name: index_shots_on_driving_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shots_on_driving_id ON public.shots USING btree (driving_id);


--
-- Name: index_shots_on_fight_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shots_on_fight_id ON public.shots USING btree (fight_id);


--
-- Name: index_shots_on_vehicle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shots_on_vehicle_id ON public.shots USING btree (vehicle_id);


--
-- Name: index_shots_on_was_rammed_or_damaged; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shots_on_was_rammed_or_damaged ON public.shots USING btree (was_rammed_or_damaged);


--
-- Name: index_sites_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_active ON public.sites USING btree (active);


--
-- Name: index_sites_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_campaign_id ON public.sites USING btree (campaign_id);


--
-- Name: index_sites_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_campaign_id_and_active ON public.sites USING btree (campaign_id, active);


--
-- Name: index_sites_on_campaign_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sites_on_campaign_id_and_name ON public.sites USING btree (campaign_id, name);


--
-- Name: index_sites_on_faction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_faction_id ON public.sites USING btree (faction_id);


--
-- Name: index_sites_on_juncture_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_juncture_id ON public.sites USING btree (juncture_id);


--
-- Name: index_sites_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_lower_name ON public.sites USING btree (lower((name)::text));


--
-- Name: index_users_on_confirmation_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_confirmation_token ON public.users USING btree (confirmation_token);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_jti ON public.users USING btree (jti);


--
-- Name: index_users_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_lower_name ON public.users USING btree (lower((name)::text));


--
-- Name: index_users_on_pending_invitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_pending_invitation_id ON public.users USING btree (pending_invitation_id);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_unlock_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_unlock_token ON public.users USING btree (unlock_token);


--
-- Name: index_vehicles_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_active ON public.vehicles USING btree (active);


--
-- Name: index_vehicles_on_campaign_active_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_campaign_active_created ON public.vehicles USING btree (campaign_id, active, created_at);


--
-- Name: index_vehicles_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_campaign_id ON public.vehicles USING btree (campaign_id);


--
-- Name: index_vehicles_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_campaign_id_and_active ON public.vehicles USING btree (campaign_id, active);


--
-- Name: index_vehicles_on_faction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_faction_id ON public.vehicles USING btree (faction_id);


--
-- Name: index_vehicles_on_juncture_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_juncture_id ON public.vehicles USING btree (juncture_id);


--
-- Name: index_vehicles_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_lower_name ON public.vehicles USING btree (lower((name)::text));


--
-- Name: index_vehicles_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_user_id ON public.vehicles USING btree (user_id);


--
-- Name: index_weapons_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_weapons_on_active ON public.weapons USING btree (active);


--
-- Name: index_weapons_on_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_weapons_on_campaign_id ON public.weapons USING btree (campaign_id);


--
-- Name: index_weapons_on_campaign_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_weapons_on_campaign_id_and_active ON public.weapons USING btree (campaign_id, active);


--
-- Name: index_weapons_on_campaign_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_weapons_on_campaign_id_and_name ON public.weapons USING btree (campaign_id, name);


--
-- Name: index_weapons_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_weapons_on_lower_name ON public.weapons USING btree (lower((name)::text));


--
-- Name: unique_active_relationship; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_active_relationship ON public.chase_relationships USING btree (pursuer_id, evader_id, fight_id) WHERE (active = true);


--
-- Name: parties fk_rails_0c0806d04d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parties
    ADD CONSTRAINT fk_rails_0c0806d04d FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: sites fk_rails_0d1fa792f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT fk_rails_0d1fa792f0 FOREIGN KEY (juncture_id) REFERENCES public.junctures(id);


--
-- Name: character_effects fk_rails_1163db7ee4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_effects
    ADD CONSTRAINT fk_rails_1163db7ee4 FOREIGN KEY (shot_id) REFERENCES public.shots(id);


--
-- Name: invitations fk_rails_1e86198d66; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_1e86198d66 FOREIGN KEY (pending_user_id) REFERENCES public.users(id);


--
-- Name: onboarding_progresses fk_rails_1f27cad926; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.onboarding_progresses
    ADD CONSTRAINT fk_rails_1f27cad926 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: vehicles fk_rails_20e34e54a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT fk_rails_20e34e54a7 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: fight_events fk_rails_245a8783e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fight_events
    ADD CONSTRAINT fk_rails_245a8783e1 FOREIGN KEY (fight_id) REFERENCES public.fights(id);


--
-- Name: shots fk_rails_26bc83860a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shots
    ADD CONSTRAINT fk_rails_26bc83860a FOREIGN KEY (driver_id) REFERENCES public.shots(id);


--
-- Name: weapons fk_rails_2ce8a2c633; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weapons
    ADD CONSTRAINT fk_rails_2ce8a2c633 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: fights fk_rails_2d2f9c3580; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fights
    ADD CONSTRAINT fk_rails_2d2f9c3580 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: advancements fk_rails_37185dcab9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.advancements
    ADD CONSTRAINT fk_rails_37185dcab9 FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: users fk_rails_47b523e6b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_47b523e6b3 FOREIGN KEY (current_campaign_id) REFERENCES public.campaigns(id);


--
-- Name: characters fk_rails_4a6a8aaa2d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT fk_rails_4a6a8aaa2d FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: vehicles fk_rails_4aa26cc92e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT fk_rails_4aa26cc92e FOREIGN KEY (faction_id) REFERENCES public.factions(id);


--
-- Name: shots fk_rails_4b0302255b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shots
    ADD CONSTRAINT fk_rails_4b0302255b FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: memberships fk_rails_526855f545; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_526855f545 FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: characters fk_rails_53a8ea746c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT fk_rails_53a8ea746c FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: effects fk_rails_5b0e81433d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.effects
    ADD CONSTRAINT fk_rails_5b0e81433d FOREIGN KEY (fight_id) REFERENCES public.fights(id);


--
-- Name: campaign_memberships fk_rails_63d922f55b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_memberships
    ADD CONSTRAINT fk_rails_63d922f55b FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: campaign_memberships fk_rails_70a69f6bb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_memberships
    ADD CONSTRAINT fk_rails_70a69f6bb3 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: character_effects fk_rails_7528232602; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_effects
    ADD CONSTRAINT fk_rails_7528232602 FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);


--
-- Name: sites fk_rails_7e514689fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT fk_rails_7e514689fb FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: invitations fk_rails_7eae413fe6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_7eae413fe6 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: shots fk_rails_877a187d23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shots
    ADD CONSTRAINT fk_rails_877a187d23 FOREIGN KEY (driving_id) REFERENCES public.shots(id);


--
-- Name: attunements fk_rails_8b2279d60e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attunements
    ADD CONSTRAINT fk_rails_8b2279d60e FOREIGN KEY (site_id) REFERENCES public.sites(id);


--
-- Name: characters fk_rails_8b76601dea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT fk_rails_8b76601dea FOREIGN KEY (juncture_id) REFERENCES public.junctures(id);


--
-- Name: junctures fk_rails_8d7b4af951; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.junctures
    ADD CONSTRAINT fk_rails_8d7b4af951 FOREIGN KEY (faction_id) REFERENCES public.factions(id);


--
-- Name: effects fk_rails_8f259b1eb7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.effects
    ADD CONSTRAINT fk_rails_8f259b1eb7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: vehicles fk_rails_9e34682d54; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT fk_rails_9e34682d54 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: campaigns fk_rails_9eb8249bf2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT fk_rails_9eb8249bf2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: carries fk_rails_a4618bb448; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carries
    ADD CONSTRAINT fk_rails_a4618bb448 FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: chase_relationships fk_rails_a684d1d4db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chase_relationships
    ADD CONSTRAINT fk_rails_a684d1d4db FOREIGN KEY (evader_id) REFERENCES public.vehicles(id);


--
-- Name: chase_relationships fk_rails_ab79ee0301; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chase_relationships
    ADD CONSTRAINT fk_rails_ab79ee0301 FOREIGN KEY (fight_id) REFERENCES public.fights(id);


--
-- Name: parties fk_rails_b0e78b7930; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parties
    ADD CONSTRAINT fk_rails_b0e78b7930 FOREIGN KEY (faction_id) REFERENCES public.factions(id);


--
-- Name: shots fk_rails_b56eaf897c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shots
    ADD CONSTRAINT fk_rails_b56eaf897c FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);


--
-- Name: schticks fk_rails_b639e3f24b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schticks
    ADD CONSTRAINT fk_rails_b639e3f24b FOREIGN KEY (prerequisite_id) REFERENCES public.schticks(id);


--
-- Name: vehicles fk_rails_b6ea261768; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT fk_rails_b6ea261768 FOREIGN KEY (juncture_id) REFERENCES public.junctures(id);


--
-- Name: character_effects fk_rails_b8ed76264e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_effects
    ADD CONSTRAINT fk_rails_b8ed76264e FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: sites fk_rails_be29624db0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT fk_rails_be29624db0 FOREIGN KEY (faction_id) REFERENCES public.factions(id);


--
-- Name: character_schticks fk_rails_c3939d7d17; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_schticks
    ADD CONSTRAINT fk_rails_c3939d7d17 FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: chase_relationships fk_rails_c50d4f4bde; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chase_relationships
    ADD CONSTRAINT fk_rails_c50d4f4bde FOREIGN KEY (pursuer_id) REFERENCES public.vehicles(id);


--
-- Name: characters fk_rails_d917861fbf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.characters
    ADD CONSTRAINT fk_rails_d917861fbf FOREIGN KEY (faction_id) REFERENCES public.factions(id);


--
-- Name: schticks fk_rails_db3b4c10e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schticks
    ADD CONSTRAINT fk_rails_db3b4c10e0 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: memberships fk_rails_db60b1dd65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_db60b1dd65 FOREIGN KEY (party_id) REFERENCES public.parties(id);


--
-- Name: memberships fk_rails_e56423deb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_e56423deb1 FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);


--
-- Name: character_schticks fk_rails_e7af8a9e7b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.character_schticks
    ADD CONSTRAINT fk_rails_e7af8a9e7b FOREIGN KEY (schtick_id) REFERENCES public.schticks(id);


--
-- Name: parties fk_rails_e96f3d68ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parties
    ADD CONSTRAINT fk_rails_e96f3d68ac FOREIGN KEY (juncture_id) REFERENCES public.junctures(id);


--
-- Name: carries fk_rails_f0caecf170; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carries
    ADD CONSTRAINT fk_rails_f0caecf170 FOREIGN KEY (weapon_id) REFERENCES public.weapons(id);


--
-- Name: factions fk_rails_f1574181b1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factions
    ADD CONSTRAINT fk_rails_f1574181b1 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: junctures fk_rails_f532bbb3d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.junctures
    ADD CONSTRAINT fk_rails_f532bbb3d7 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: invitations fk_rails_f91663fe65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_f91663fe65 FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id);


--
-- Name: attunements fk_rails_fa7145d0cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attunements
    ADD CONSTRAINT fk_rails_fa7145d0cb FOREIGN KEY (character_id) REFERENCES public.characters(id);


--
-- Name: shots fk_rails_ffc06953c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shots
    ADD CONSTRAINT fk_rails_ffc06953c5 FOREIGN KEY (fight_id) REFERENCES public.fights(id);


--
-- PostgreSQL database dump complete
--

\unrestrict 6zSRlIeIJToO2mFoK7MjKJnMBidE4PBXcDglsGy7RI7WJTfkOn5iICZmla4IRYT

INSERT INTO public."schema_migrations" (version) VALUES (20221222150959);
INSERT INTO public."schema_migrations" (version) VALUES (20221223141417);
INSERT INTO public."schema_migrations" (version) VALUES (20221228142443);
INSERT INTO public."schema_migrations" (version) VALUES (20221228143241);
INSERT INTO public."schema_migrations" (version) VALUES (20221230220526);
INSERT INTO public."schema_migrations" (version) VALUES (20221230230333);
INSERT INTO public."schema_migrations" (version) VALUES (20221231152338);
INSERT INTO public."schema_migrations" (version) VALUES (20221231224627);
INSERT INTO public."schema_migrations" (version) VALUES (20221231225849);
INSERT INTO public."schema_migrations" (version) VALUES (20230101225536);
INSERT INTO public."schema_migrations" (version) VALUES (20230104011849);
INSERT INTO public."schema_migrations" (version) VALUES (20230104152752);
INSERT INTO public."schema_migrations" (version) VALUES (20230104152852);
INSERT INTO public."schema_migrations" (version) VALUES (20230104153708);
INSERT INTO public."schema_migrations" (version) VALUES (20230104160010);
INSERT INTO public."schema_migrations" (version) VALUES (20230104161525);
INSERT INTO public."schema_migrations" (version) VALUES (20230104195522);
INSERT INTO public."schema_migrations" (version) VALUES (20230111160112);
INSERT INTO public."schema_migrations" (version) VALUES (20230111160259);
INSERT INTO public."schema_migrations" (version) VALUES (20230111162829);
INSERT INTO public."schema_migrations" (version) VALUES (20230111165154);
INSERT INTO public."schema_migrations" (version) VALUES (20230111165214);
INSERT INTO public."schema_migrations" (version) VALUES (20230112200859);
INSERT INTO public."schema_migrations" (version) VALUES (20230112201215);
INSERT INTO public."schema_migrations" (version) VALUES (20230115155237);
INSERT INTO public."schema_migrations" (version) VALUES (20230115230424);
INSERT INTO public."schema_migrations" (version) VALUES (20230115231050);
INSERT INTO public."schema_migrations" (version) VALUES (20230115231139);
INSERT INTO public."schema_migrations" (version) VALUES (20230116001213);
INSERT INTO public."schema_migrations" (version) VALUES (20230116144133);
INSERT INTO public."schema_migrations" (version) VALUES (20230117193412);
INSERT INTO public."schema_migrations" (version) VALUES (20230118140006);
INSERT INTO public."schema_migrations" (version) VALUES (20230118143050);
INSERT INTO public."schema_migrations" (version) VALUES (20230118143234);
INSERT INTO public."schema_migrations" (version) VALUES (20230118154648);
INSERT INTO public."schema_migrations" (version) VALUES (20230120042133);
INSERT INTO public."schema_migrations" (version) VALUES (20230120174243);
INSERT INTO public."schema_migrations" (version) VALUES (20230121204521);
INSERT INTO public."schema_migrations" (version) VALUES (20230123163148);
INSERT INTO public."schema_migrations" (version) VALUES (20230123184025);
INSERT INTO public."schema_migrations" (version) VALUES (20230123223405);
INSERT INTO public."schema_migrations" (version) VALUES (20230123223603);
INSERT INTO public."schema_migrations" (version) VALUES (20230124033307);
INSERT INTO public."schema_migrations" (version) VALUES (20230124033520);
INSERT INTO public."schema_migrations" (version) VALUES (20230125042917);
INSERT INTO public."schema_migrations" (version) VALUES (20230125210000);
INSERT INTO public."schema_migrations" (version) VALUES (20230130012609);
INSERT INTO public."schema_migrations" (version) VALUES (20230130143833);
INSERT INTO public."schema_migrations" (version) VALUES (20230130184927);
INSERT INTO public."schema_migrations" (version) VALUES (20230130194045);
INSERT INTO public."schema_migrations" (version) VALUES (20230130194546);
INSERT INTO public."schema_migrations" (version) VALUES (20230130201314);
INSERT INTO public."schema_migrations" (version) VALUES (20230131123849);
INSERT INTO public."schema_migrations" (version) VALUES (20230131143516);
INSERT INTO public."schema_migrations" (version) VALUES (20230131143822);
INSERT INTO public."schema_migrations" (version) VALUES (20230131151159);
INSERT INTO public."schema_migrations" (version) VALUES (20230625195159);
INSERT INTO public."schema_migrations" (version) VALUES (20230626001923);
INSERT INTO public."schema_migrations" (version) VALUES (20230630000236);
INSERT INTO public."schema_migrations" (version) VALUES (20230630000341);
INSERT INTO public."schema_migrations" (version) VALUES (20230630120709);
INSERT INTO public."schema_migrations" (version) VALUES (20230630120936);
INSERT INTO public."schema_migrations" (version) VALUES (20230630121657);
INSERT INTO public."schema_migrations" (version) VALUES (20230630123031);
INSERT INTO public."schema_migrations" (version) VALUES (20230630140714);
INSERT INTO public."schema_migrations" (version) VALUES (20230702185354);
INSERT INTO public."schema_migrations" (version) VALUES (20230702185450);
INSERT INTO public."schema_migrations" (version) VALUES (20230702185653);
INSERT INTO public."schema_migrations" (version) VALUES (20230702192443);
INSERT INTO public."schema_migrations" (version) VALUES (20230703152116);
INSERT INTO public."schema_migrations" (version) VALUES (20230703183430);
INSERT INTO public."schema_migrations" (version) VALUES (20230703184647);
INSERT INTO public."schema_migrations" (version) VALUES (20230703184921);
INSERT INTO public."schema_migrations" (version) VALUES (20230703185023);
INSERT INTO public."schema_migrations" (version) VALUES (20230703191443);
INSERT INTO public."schema_migrations" (version) VALUES (20230704143438);
INSERT INTO public."schema_migrations" (version) VALUES (20230704143851);
INSERT INTO public."schema_migrations" (version) VALUES (20230704150412);
INSERT INTO public."schema_migrations" (version) VALUES (20230704162555);
INSERT INTO public."schema_migrations" (version) VALUES (20230704162845);
INSERT INTO public."schema_migrations" (version) VALUES (20230704164726);
INSERT INTO public."schema_migrations" (version) VALUES (20230704164807);
INSERT INTO public."schema_migrations" (version) VALUES (20230705124636);
INSERT INTO public."schema_migrations" (version) VALUES (20230706153522);
INSERT INTO public."schema_migrations" (version) VALUES (20230707180909);
INSERT INTO public."schema_migrations" (version) VALUES (20230707180918);
INSERT INTO public."schema_migrations" (version) VALUES (20230709190815);
INSERT INTO public."schema_migrations" (version) VALUES (20230709191117);
INSERT INTO public."schema_migrations" (version) VALUES (20230714185357);
INSERT INTO public."schema_migrations" (version) VALUES (20230717140354);
INSERT INTO public."schema_migrations" (version) VALUES (20230717150437);
INSERT INTO public."schema_migrations" (version) VALUES (20230717163818);
INSERT INTO public."schema_migrations" (version) VALUES (20230719115659);
INSERT INTO public."schema_migrations" (version) VALUES (20230719190547);
INSERT INTO public."schema_migrations" (version) VALUES (20230719190554);
INSERT INTO public."schema_migrations" (version) VALUES (20230725130412);
INSERT INTO public."schema_migrations" (version) VALUES (20230802231422);
INSERT INTO public."schema_migrations" (version) VALUES (20230802231432);
INSERT INTO public."schema_migrations" (version) VALUES (20230831204046);
INSERT INTO public."schema_migrations" (version) VALUES (20230903001007);
INSERT INTO public."schema_migrations" (version) VALUES (20230903001030);
INSERT INTO public."schema_migrations" (version) VALUES (20230903191152);
INSERT INTO public."schema_migrations" (version) VALUES (20230903191203);
INSERT INTO public."schema_migrations" (version) VALUES (20230904005552);
INSERT INTO public."schema_migrations" (version) VALUES (20230904005601);
INSERT INTO public."schema_migrations" (version) VALUES (20230908143200);
INSERT INTO public."schema_migrations" (version) VALUES (20231028003454);
INSERT INTO public."schema_migrations" (version) VALUES (20231109200642);
INSERT INTO public."schema_migrations" (version) VALUES (20231109200752);
INSERT INTO public."schema_migrations" (version) VALUES (20250612021722);
INSERT INTO public."schema_migrations" (version) VALUES (20250612024652);
INSERT INTO public."schema_migrations" (version) VALUES (20250612024728);
INSERT INTO public."schema_migrations" (version) VALUES (20250614224604);
INSERT INTO public."schema_migrations" (version) VALUES (20250616024437);
INSERT INTO public."schema_migrations" (version) VALUES (20250616213958);
INSERT INTO public."schema_migrations" (version) VALUES (20250616234644);
INSERT INTO public."schema_migrations" (version) VALUES (20250628125758);
INSERT INTO public."schema_migrations" (version) VALUES (20250628134615);
INSERT INTO public."schema_migrations" (version) VALUES (20250630024627);
INSERT INTO public."schema_migrations" (version) VALUES (20250721005120);
INSERT INTO public."schema_migrations" (version) VALUES (20250721005242);
INSERT INTO public."schema_migrations" (version) VALUES (20250721005335);
INSERT INTO public."schema_migrations" (version) VALUES (20250721005543);
INSERT INTO public."schema_migrations" (version) VALUES (20250721005655);
INSERT INTO public."schema_migrations" (version) VALUES (20250721014108);
INSERT INTO public."schema_migrations" (version) VALUES (20250723203605);
INSERT INTO public."schema_migrations" (version) VALUES (20250727132246);
INSERT INTO public."schema_migrations" (version) VALUES (20250727203518);
INSERT INTO public."schema_migrations" (version) VALUES (20250727203600);
INSERT INTO public."schema_migrations" (version) VALUES (20250801000901);
INSERT INTO public."schema_migrations" (version) VALUES (20250801115942);
INSERT INTO public."schema_migrations" (version) VALUES (20250804144233);
INSERT INTO public."schema_migrations" (version) VALUES (20250806222953);
INSERT INTO public."schema_migrations" (version) VALUES (20250810001829);
INSERT INTO public."schema_migrations" (version) VALUES (20250810002204);
INSERT INTO public."schema_migrations" (version) VALUES (20250810004814);
INSERT INTO public."schema_migrations" (version) VALUES (20250810024754);
INSERT INTO public."schema_migrations" (version) VALUES (20250810025034);
INSERT INTO public."schema_migrations" (version) VALUES (20250810025245);
INSERT INTO public."schema_migrations" (version) VALUES (20250810033245);
INSERT INTO public."schema_migrations" (version) VALUES (20250816145730);
INSERT INTO public."schema_migrations" (version) VALUES (20250816155319);
INSERT INTO public."schema_migrations" (version) VALUES (20250820132404);
INSERT INTO public."schema_migrations" (version) VALUES (20250821001644);
INSERT INTO public."schema_migrations" (version) VALUES (20250823103627);
INSERT INTO public."schema_migrations" (version) VALUES (20250823155625);
INSERT INTO public."schema_migrations" (version) VALUES (20250823232536);
INSERT INTO public."schema_migrations" (version) VALUES (20250823232549);
INSERT INTO public."schema_migrations" (version) VALUES (20250824014723);
INSERT INTO public."schema_migrations" (version) VALUES (20250826134826);
INSERT INTO public."schema_migrations" (version) VALUES (20250826134916);
INSERT INTO public."schema_migrations" (version) VALUES (20250826134953);
INSERT INTO public."schema_migrations" (version) VALUES (20250826135332);
INSERT INTO public."schema_migrations" (version) VALUES (20250903195018);
INSERT INTO public."schema_migrations" (version) VALUES (20250903201413);
INSERT INTO public."schema_migrations" (version) VALUES (20250905135419);
INSERT INTO public."schema_migrations" (version) VALUES (20250906201529);
