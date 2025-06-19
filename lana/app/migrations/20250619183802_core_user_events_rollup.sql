-- Add migration script here
CREATE TABLE core_user_events_rollup(
	id         		uuid				NOT NULL,	
	attributes		jsonb					,
	recorded_at_latest	timestamp with time zone	NOT NULL,
	sequence_latest		integer				NOT NULL,
	event_type_latest	character varying		NOT NULL
);

ALTER TABLE ONLY public.core_user_events_rollup
    ADD CONSTRAINT core_user_events_rollup_id_sequence_key UNIQUE (id, sequence_latest);

ALTER TABLE ONLY public.core_user_events_rollup
    ADD CONSTRAINT core_user_events_rollup_id_fkey FOREIGN KEY (id) REFERENCES public.core_users(id);

CREATE OR REPLACE FUNCTION process_core_user_events_rollup() RETURNS TRIGGER AS $core_user_events_rollup$
    BEGIN
        --
	-- TO DO: add handling for other operation types in source table (DELETE, UPDATE)
        IF (TG_OP = 'INSERT') THEN
            INSERT INTO core_user_events_rollup 
		SELECT
			new_record.id as id,
			-- if changed, set key value to value from last user event, and add new keys
			-- drop fields: type exists in separate col and audit_info is an event not user property
			COALESCE(rollup.attributes, '{}'::jsonb) || (new_record.event - 'audit_info' - 'type') as attributes,
			new_record.recorded_at as recorded_at_latest,
			new_record.sequence as sequence_latest,
			new_record.event_type as event_type_latest
		FROM 
			(SELECT * from core_user_events WHERE id = NEW.id and sequence = NEW.sequence) new_record
		LEFT JOIN
			core_user_events_rollup rollup
		ON
			rollup.id = new_record.id and rollup.sequence_latest = new_record.sequence - 1;
	    DELETE FROM core_user_events_rollup where id = NEW.id and sequence_latest = NEW.sequence - 1;
        END IF;
        RETURN NULL; 
    END;
$core_user_events_rollup$ LANGUAGE plpgsql;

CREATE TRIGGER core_user_events_rollup
AFTER INSERT ON core_user_events
    FOR EACH ROW EXECUTE FUNCTION process_core_user_events_rollup();
