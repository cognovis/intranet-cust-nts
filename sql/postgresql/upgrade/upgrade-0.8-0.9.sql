SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-0.8-0.9.sql','');
update im_categories set category = 'Reduction in Working Hours' where category_id = 5007;
insert into im_categories(category_id, category, category_type,aux_string1,aux_string2,visible_tcl,sort_order) values (5008, 'Bridge Days', 'Intranet Absence Type','BT','73C6EF','[im_user_is_hr_p $user_id]',5008);
insert into im_category_hierarchy(child_id,parent_id) values (5008,5005);
update im_user_absences set absence_type_id = 5008 where absence_type_id = 5007;
update im_menus set url = '/intranet-timesheet2/absences/new?absence_type_id=5008' where menu_id =59545;

