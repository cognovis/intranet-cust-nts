# /intranet/companies/upload-contacts.tcl
#
# Copyright (C) 2004 ]project-open[
#
# This program is free software. You can redistribute it
# and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation;
# either version 2 of the License, or (at your option)
# any later version. This program is distributed in the
# hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

ad_page_contract {
    Serve the user a form to upload a new file or URL

    @author frank.bergmann@project-open.com
} {
    {booking_date ""}
}

set return_url "/intranet"
set user_id [ad_maybe_redirect_for_registration]
set page_title "Upload Entitlements CSV"
set context_bar [im_context_bar [list "/intranet/users/" "Users"] $page_title]
if {$booking_date eq ""} {
    set booking_date [lindex [split [ns_localsqltimestamp] " "] 0]
}

set user_is_admin_p [im_is_user_site_wide_or_intranet_admin $user_id]
if {!$user_is_admin_p && ![im_user_is_hr_p $user_id]} {
    ad_return_complaint 1 "You have insufficient privileges to use this page"
    return
}

ad_form -html { enctype multipart/form-data } -export { return_url } -name "upload" -form {
        {upload_file:file {label \#file-storage.Upload_a_file\#} {html "size 30"}}
        {leave_entitlement_name:text(text) {label "[_ intranet-timesheet2.Absence_Name]"} {html {size 40}}}
        {leave_entitlement_type_id:text(im_category_tree) {label "[_ intranet-timesheet2.Type]"} {custom {category_type "Intranet Absence Type"}}}
        {booking_date:text(text) {label "[_ intranet-timesheet2.Start_Date]"} {value "$booking_date"} {html {size 10}} {after_html {<input type="button" style="height:20px; width:20px; background: url('/resources/acs-templating/calendar.gif');" onclick ="return showCalendar('booking_date', 'y-m-d');" >}}}
        {description:text(textarea),optional {label "[_ intranet-timesheet2.Description]"} {html {cols 40}}}
} -on_request {
    set booking_date [lindex [split [ns_localsqltimestamp] " "] 0]
} -on_submit {

    # ---------------------------------------------------------------
    # Get the uploaded file
    # ---------------------------------------------------------------

    # number_of_bytes is the upper-limit
    set max_n_bytes [ad_parameter -package_id [im_package_filestorage_id] MaxNumberOfBytes "" 0]
    set tmp_filename [ns_queryget upload_file.tmpfile]
    im_security_alert_check_tmpnam -location "upload-contacts-2.tcl" -value $tmp_filename
    if { $max_n_bytes && ([file size $tmp_filename] > $max_n_bytes) } {
        ad_return_complaint 1 "Your file is larger than the maximum permissible upload size:  [util_commify_number $max_n_bytes] bytes"
        return
    }

    # strip off the C:\directories... crud and just get the file name
    if ![regexp {([^//\\]+)$} $upload_file match company_filename] {
        # couldn't find a match
        set company_filename $upload_file
    }

    if {[regexp {\.\.} $company_filename]} {
        ad_return_complaint 1 "Filename contains forbidden characters"
    }

    if {![file readable $tmp_filename]} {
        ad_return_complaint 1 "Unable to read the file '$tmp_filename'. 
    Please check the file permissions or contact your system administrator.\n"
        ad_script_abort
    }


    # ---------------------------------------------------------------
    # Extract CSV contents
    # ---------------------------------------------------------------

    set csv_files_content [fileutil::cat $tmp_filename]
    set csv_files [split $csv_files_content "\n"]
    set csv_files_len [llength $csv_files]

    set separator [im_csv_guess_separator $csv_files]

    # Split the header into its fields
    set csv_header [string trim [lindex $csv_files 0]]
    set csv_header_fields [im_csv_split $csv_header $separator]
    set csv_header_len [llength $csv_header_fields]
    set values_list_of_lists [im_csv_get_values $csv_files_content $separator]

#    set booking_date [lindex $csv_header_fields 1]
#    set leave_entitlement_name "Annual Leave"
    set leave_entitlement_status_id "16000"
    set booking_date_sql [template::util::date get_property sql_timestamp $booking_date]
    
#    set leave_entitlement_type_id "5000"
#    set description "Automatically generated"

    # ---------------------------------------------------------------
    # Render Page Header
    # ---------------------------------------------------------------

    # This page is a "streaming page" without .adp template,
    # because this page can become very, very long and take
    # quite some time.

    ad_return_top_of_page "
            [im_header]
            [im_navbar]
    "


    # ---------------------------------------------------------------
    # Start parsing the CSV
    # ---------------------------------------------------------------
    
    set linecount 0
    foreach csv_line_fields $values_list_of_lists {
        incr linecount
    
        # -------------------------------------------------------
        # Extract variables from the CSV file
        # Loop through all columns of the CSV file and set 
        # local variables according to the column header (1st row).
    
        set personnel_number [string trimleft [lindex $csv_line_fields 0] "0"]
        set employee_id [db_string employee "select employee_id from im_employees where personnel_number = :personnel_number" -default ""]
        if {$employee_id eq ""} {
            ns_write "No Employee with personnel_number $personnel_number"
            continue
        }
        set entitlement_days [lindex $csv_line_fields 1]
        regsub -all {,} $entitlement_days {.} entitlement_days
    
        # Check if we have already booked entitlements for that date for this employee and delete them
        set leave_entitlement_ids [db_list entitlement "select leave_entitlement_id from im_user_leave_entitlements
             where booking_date = $booking_date_sql and owner_id = :employee_id and leave_entitlement_type_id = :leave_entitlement_type_id"]

        if {[llength $leave_entitlement_ids]>1} {
            # We have more than one entitlement on that date, delete it.
            db_dml delete "delete from im_user_leave_entitlements
                where booking_date = $booking_date_sql and owner_id = :employee_id and leave_entitlement_type_id = :leave_entitlement_type_id"
                ns_write "<li>Entitlements deleted for [im_name_from_user_id $employee_id] :: $employee_id</li>"
        }
    
        if {[llength $leave_entitlement_ids] == 1} {
            set leave_entitlement_id [lindex $leave_entitlement_ids 0]
            db_dml update "update im_user_leave_entitlements set entitlement_days = :entitlement_days where leave_entitlement_id = :leave_entitlement_id"
            ns_write "<li>Entitlement updated for [im_name_from_user_id $employee_id] :: $employee_id with $entitlement_days</li>"
        } else {

            set leave_entitlement_id [db_nextval acs_object_id_seq]
    
            db_transaction {            
    	        set absence_id [db_string new_absence "
    	    	    SELECT im_user_leave_entitlement__new(
                    :leave_entitlement_id,
                    'im_user_leave_entitlement',
                    now(),
                    :user_id,
                    '[ns_conn peeraddr]',
                    null,
                    :leave_entitlement_name,
                    :employee_id,
                    $booking_date_sql,
                    :entitlement_days,
                    :leave_entitlement_status_id,
                    :leave_entitlement_type_id,
                    :description
                    )"]

                db_dml update_object "
    	            update acs_objects set
    			    last_modified = now()
                    where object_id = :absence_id"
	
                # Audit the action
                im_audit -object_type im_user_leave_entitlement -action after_create -object_id $leave_entitlement_id -status_id $leave_entitlement_status_id -type_id $leave_entitlement_type_id
                ns_write "<li>Entitlement created for [im_name_from_user_id $employee_id] :: $employee_id with $entitlement_days</li>"
            }
        }
    }

    # Remove all permission related entries in the system cache
    im_permission_flush


    # ------------------------------------------------------------
    # Render Report Footer

    ns_write [im_footer]
} -after_submit {
    ad_script_abort
}