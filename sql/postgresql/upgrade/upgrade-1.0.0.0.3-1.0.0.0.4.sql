SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-1.0.0.0.3-1.0.0.0.4.sql','');
    
-- Update the Link to the resource planning
update im_menus set url = '/intranet-planning/project-resources/index' where menu_id = 46232;