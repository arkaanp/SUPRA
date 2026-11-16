ALTER TABLE notification_preferences
 ADD COLUMN news_min_severity TEXT NOT NULL DEFAULT 'low'
 CHECK (news_min_severity IN ('low','medium','high','critical'));
