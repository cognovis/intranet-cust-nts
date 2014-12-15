SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-1.0.0.0.0-1.0.0.0.1.sql','');

update im_view_columns set visible_for = 'if {$hide_colors_p eq 0} {set visible_p 1} else {set visible_p 0}' where column_id in (20007,20009,1066,20001);
    
-- Close the rejected cases so they wont be approved automatically    
update wf_cases set state = 'finished' where case_id in (select case_id from wf_cases, im_user_absences where state = 'active' and workflow_key = 'vacation_approval_wf' and object_id = absence_id and absence_status_id =16006);
update wf_cases set state = 'finished' where case_id in (select case_id from wf_cases, im_user_absences where state = 'active' and workflow_key = 'hr_vacation_approval_wf' and object_id = absence_id and absence_status_id =16006);
update wf_cases set state = 'finished' where case_id in (select case_id from wf_cases, im_user_absences where state = 'active' and workflow_key = 'vacation_storno_wf' and object_id = absence_id and absence_status_id =16006);
update wf_context_transition_info set fire_custom_arg = '16006' where fire_custom_arg = '16002';