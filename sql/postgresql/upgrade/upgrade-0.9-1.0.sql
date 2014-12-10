SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-0.9-1.0.sql','');

-- Fix a problem preventing form HR disapproval to work
update wf_arcs set guard_custom_arg = 'hr_review_reject_p' where workflow_key = 'hr_vacation_approval_wf' and transition_key = 'hr_approve' and place_key = 'hr_approved';

insert into im_view_columns (column_id, view_id, column_name, column_render_tcl, sort_order,variable_name)
values (28105,281,'Type','[im_category_from_id $absence_type_id]',6,'absence_type_id');

update im_view_columns set visible_for = 'if {$hide_colors_p eq 0} {set visible_p 1} else {set visible_p 0}' where column_id in (20007,20009,1066);