SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-1.0.0.0.4-1.0.0.0.5.sql','');
    
-- Enable Program Support
update im_categories set enabled_p = 't' where category_id = 2510;