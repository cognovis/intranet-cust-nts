SELECT acs_log__debug('/packages/intranet-cust-nts/sql/postgresql/upgrade/upgrade-1.0.0.0.2-1.0.0.0.3.sql','');

update apm_parameter_values
set attr_value = 'im_nts_absence_new_page_wf_perm_edit_button'
where parameter_id in (
        select parameter_id
        from apm_parameters
        where   parameter_name = 'AbsenceNewPageWfEditButtonPerm' and
                package_id = '12195'
        );
        
update im_categories set aux_string2='?' where category_id in (16004,16010);