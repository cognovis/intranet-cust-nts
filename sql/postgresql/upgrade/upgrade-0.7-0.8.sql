SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-0.7-0.8.sql','');

insert into im_categories(category_id, category, category_type) values (16010, 'Storno Requested', 'Intranet Absence Status');
insert into im_category_hierarchy(child_id,parent_id) values (16010,16000);

update wf_context_transition_info set fire_callback = 'im_workflow__set_object_status_id', fire_custom_arg = '16010' where workflow_key = 'vacation_storno_wf' and transition_key = 'provide_comment';
update wf_context_transition_info set fire_callback = 'im_workflow__set_object_status_id', fire_custom_arg = '16000' where workflow_key = 'vacation_storno_wf' and transition_key = 'rejected';