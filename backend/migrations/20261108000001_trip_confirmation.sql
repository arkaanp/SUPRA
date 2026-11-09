-- Existing planned trips remain intact, but are not invented journey history.
ALTER TABLE trips
    ADD COLUMN start_latitude DOUBLE PRECISION,
    ADD COLUMN start_longitude DOUBLE PRECISION,
    ADD COLUMN destination_latitude DOUBLE PRECISION,
    ADD COLUMN destination_longitude DOUBLE PRECISION,
    ADD COLUMN confirmed_at TIMESTAMPTZ,
    ADD CONSTRAINT trips_coordinates CHECK (
        (start_latitude IS NULL AND start_longitude IS NULL AND
         destination_latitude IS NULL AND destination_longitude IS NULL AND confirmed_at IS NULL)
        OR
        (start_latitude IS NOT NULL AND start_longitude IS NOT NULL AND
         destination_latitude IS NOT NULL AND destination_longitude IS NOT NULL AND
         start_latitude BETWEEN -90 AND 90 AND start_longitude BETWEEN -180 AND 180 AND
         destination_latitude BETWEEN -90 AND 90 AND destination_longitude BETWEEN -180 AND 180)
    );
