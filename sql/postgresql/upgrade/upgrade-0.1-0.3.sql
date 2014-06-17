-- 
-- 
-- 
-- @author Malte Sussdorff (malte.sussdorff@cognovis.de)
-- @creation-date 2013-01-14
-- @cvs-id $Id$
--

SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-0.1-0.3.sql','');

update im_categories set visible_tcl = '[im_user_is_hr_p $user_id]' where category_id in (5001,5005,5007);

-- Enable Workflows
update im_categories set aux_string1 = 'vacation_approval_wf' where category_id in (5000,5006);
    
-- Enable the 5002 category for everything considered "Special Vacation"
update im_categories set enabled_p = 't', category = 'Special Vacation' where category_id in (5002);
update im_menus SET name = 'New Special Leave', url = '/intranet-timesheet2/absences/new?absence_type_id=5002' where menu_id = 28518;
update im_categories set aux_string1 = 'hr_vacation_approval_wf' where category_id in (5002);

select im_grant_permission(28515,463,'read') from dual;
select im_remove_permission(59545,463,'read') from dual;
select im_grant_permission(59545,585,'read') from dual;

insert into im_category_hierarchy (parent_id, child_id) values ('5005','5007');
insert into im_category_hierarchy (parent_id, child_id) values ('5000','5006');
update im_component_plugins set enabled_p = 'f' where plugin_id = 28442;
update im_component_plugins set enabled_p = 'f' where plugin_id = 18496;
update im_component_plugins set enabled_p = 't' where plugin_id = 249178;
update im_component_plugins set location = 'right' where plugin_id = 11379;
update im_component_plugins set location = 'right' where plugin_id = 249178;
select im_menu__delete(183292) from dual;