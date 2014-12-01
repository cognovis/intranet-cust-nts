SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-0.9-1.0.sql','');

-- Fix a problem preventing form HR disapproval to work
update wf_arcs set guard_custom_arg = 'hr_review_reject_p' where workflow_key = 'hr_vacation_approval_wf' and transition_key = 'hr_approve' and place_key = 'hr_approved';
