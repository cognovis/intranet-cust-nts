SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-1.0.0.0.0-1.0.0.0.1.sql','');

update im_view_columns set visible_for = 'if {$hide_colors_p eq 0} {set visible_p 1} else {set visible_p 0}' where column_id in (20007,20009,1066);