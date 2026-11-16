-- Keep event keys so scheduled checks cannot recreate a dismissed alert.
ALTER TABLE notifications ADD COLUMN deleted_at TIMESTAMPTZ;
CREATE INDEX notifications_visible_read ON notifications(user_id,is_read)
 WHERE deleted_at IS NULL;
