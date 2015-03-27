# packages/intranet-cust-nts/tcl/intranet-cust-nts-procs.tcl

## Copyright (c) 2011, cognovis GmbH, Hamburg, Germany
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see
# <http://www.gnu.org/licenses/>.
# 

ad_library {
    
    Custom Prozedures and Callbacks for Neusoft
    
    @author Malte Sussdorff (malte.sussdorff@cognovis.de)
    @creation-date 2014-01-19
    @cvs-id $Id$
}

ad_proc -public im_nts_absence_inform {
    -absence_id
    -type
    {-msg ""}
} {
    Procedure to send out the E-Mail for an absence
} {
    db_1row absence_info "
        select 
            owner_id, 
            to_char(start_date,'YYYY-MM-DD') as start_date,
            to_char(end_date,'YYYY-MM-DD') as end_date,
            duration_days,
            absence_type_id,
            absence_name,
            description, 
            contact_info, 
            vacation_replacement_id
        from im_user_absences 
        where absence_id = :absence_id
    "

    set assignee_ids [db_list wf_assigned_user "
        select ut.user_id as wf_assigned_user_id
        from im_user_absences a
        inner join wf_cases wfc
        on (wfc.object_id=a.absence_id)
        inner join wf_user_tasks ut
        on (ut.case_id=wfc.case_id)
        where absence_id = :absence_id
    "]
    
    if { [catch {
        set pm_ids [planning_item::get_project_managers -user_id $owner_id -start_date $start_date -end_date $end_date]
    } errmsg] } {
        set pm_ids [list]
        ns_log error $errmsg
    }
    
    set supervisor_id [db_string supervisor "select supervisor_id from im_employees where employee_id = :owner_id"  -default ""]
    set hr_ids [group::get_members -group_id [im_hr_group_id]]
    if {[ns_conn isconnected]} {
        set user_id [ad_conn user_id]
    } else {
        set user_id $supervisor_id
    }
    
    if {$user_id eq ""} {set user_id $owner_id}
    
    set cc_addr ""
    
    # Format the project_leads
    set pm_html_parts [list]
    foreach pm_id $pm_ids {
        lappend pm_html_parts "[im_name_from_user_id $pm_id]"
    }
    
    # Get the recipients
    set to_ids $pm_ids
    if {$supervisor_id ne ""} {
        lappend to_ids $supervisor_id
    }
    
    # If it is another absence, have HR involved
    if {[im_sub_categories [im_user_absence_type_personal]] == $absence_type_id} {
        if {$hr_ids ne ""} {
            set to_ids [concat $to_ids $hr_ids]
        }
    }  
        
    if {$owner_id != $user_id} {
        lappend to_ids $owner_id
    }

    set to_ids [lsort -unique [concat $to_ids $assignee_ids]]
    
    set workflow_msg ""
    
    set start_date_pretty [dt_ansi_to_pretty $start_date]
    set end_date_pretty [dt_ansi_to_pretty $end_date]
    
    set from_addr [db_string owner_mail "select email from parties where party_id = $user_id"]
    switch $type {
        new {
            set hr_p [db_string case_id "select 1 from wf_cases where object_id = :absence_id and workflow_key = 'hr_vacation_approval_wf' and state='active' limit 1" -default "0"]
            if {$hr_p && $hr_ids ne ""} {set to_ids [concat $to_ids $hr_ids]}  
            if {$owner_id != $user_id} {
                
                #### This actually does not belong to the notification, but it is convenient to store here.
                # Consider this very bad coding and a quick hack
                #
                # The owner != user_id. Therefore we need to update acs_objects with the owner_id otherwise permissions won't work.
                
                db_dml object_update "update acs_objects set creation_user = :owner_id where object_id = :absence_id"
            }
            set to_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $to_ids])"]
            set cc_addr $from_addr
            set subject "[_ intranet-cust-nts.New_Absence_Request]: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
        }
        edit {
            # Check if the owner edits this
            if {$owner_id ne $user_id} {
                # The supervisor was editing this, change the recipients
                set to_ids [concat $owner_id $pm_ids]
                if {$supervisor_id ne $user_id} {
                    # Someone but the supervisor is changeing this, inform him as well
                    lappend to_ids $supervisor_id
                }
            }
            
            set to_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $to_ids])"]
            set cc_addr $from_addr
            set subject "[_ intranet-cust-nts.lt_Changed_Absence_Reque]: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
        }
        approved {          
            set subject "[_ intranet-cust-nts.lt_Approved_Absence_Requ]: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_string owner_mail "select email from parties where party_id = :owner_id"]
            set cc_addr $from_addr
            set workflow_msg "<br\>[_ intranet-cust-nts.Reason_for_approval]: $msg"
        }
        hr_approved {          
            set subject "[_ intranet-cust-nts.lt_Approved_Absence_Requ] HR: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_string owner_mail "select email from parties where party_id = :owner_id"]
	    # Send to supervisor and HR in CC
	    if {$assignee_ids ne ""} {
		set cc_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $assignee_ids])"]
	    }
            lappend cc_addr $from_addr
            set workflow_msg "<br\>[_ intranet-cust-nts.Reason_for_approval]: $msg"
        }
        rejected {
            set subject "[_ intranet-cust-nts.lt_Rejected_Absence_Requ]: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_string owner_mail "select email from parties where party_id = :owner_id"]
            set cc_addr $from_addr
            set workflow_msg "<br\>[_ intranet-cust-nts.Reason_for_rejection]: $msg"
        }
        hr_rejected {
            set to_ids [list $owner_id]
	        if {$supervisor_id ne $user_id && $supervisor_id ne ""} {
                lappend to_ids $supervisor_id
            }
            set subject "[_ intranet-cust-nts.lt_Rejected_Absence_Requ] by HR: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $to_ids])"]
            set cc_addr $from_addr
            set workflow_msg "<br\>[_ intranet-cust-nts.Reason_for_rejection]: $msg"
        }
        cancelled {
            set subject "[_ intranet-cust-nts.lt_Cancelled_Absence_Req]: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list [list $to_ids]])"]
            if {$pm_ids ne ""} {
                set cc_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $pm_ids])"]
            }
        }
        storno_requested {
	    set to_ids $owner_id
	    if {$supervisor_id ne ""} {
		lappend to_ids $supervisor_id
	    }
            set to_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $to_ids])"]
            set subject "Vacation Storno Requested: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
        }
        storno_approved {          
            set subject "[_ intranet-cust-nts.lt_Approved_Absence_Requ] for Storno: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_string owner_mail "select email from parties where party_id = :owner_id"]
            set cc_addr $from_addr
            set workflow_msg "<br\>[_ intranet-cust-nts.Reason_for_approval]: $msg"
        }
        storno_rejected {
            set subject "[_ intranet-cust-nts.lt_Rejected_Absence_Requ] for Storno: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            set to_addr [db_string owner_mail "select email from parties where party_id = :owner_id"]
            set cc_addr $from_addr
            set workflow_msg "<br\>[_ intranet-cust-nts.Reason_for_rejection]: $msg"
        }
        7_days_over -
        10_days_over {

            set to_ids [db_list wf_assigned_user "
                select ut.user_id as wf_assigned_user_id
                from im_user_absences a
                inner join wf_cases wfc
                on (wfc.object_id=a.absence_id)
                inner join wf_user_tasks ut
                on (ut.case_id=wfc.case_id)
                where absence_id = :absence_id
            "]

            set subject "[_ intranet-cust-nts.lt_${type}_Absence_Req_Reminder_Subject]: [im_name_from_user_id $owner_id], $start_date_pretty, $absence_name"
            if {$to_ids eq ""} {
                set to_addr "[ad_system_owner]"
                set workflow_msg "<br\>COULD NOT FIND AN ASSIGNED USER FOR $absence_id !!!!"
            } else {
                set to_addr [db_list emails "select email from parties where party_id in ([template::util::tcl_to_sql_list $to_ids])"]
                set cc_addr $from_addr
                set workflow_msg "<br\>[_ intranet-cust-nts.lt_${type}_Absence_Req_Reminder_Body]"
            }
        }
    }
    
    set body "Name: <a href='[export_vars -base "[ad_url]intranet-timesheet2/absences/new" -url {absence_id {form_mode "display"}}]'>$absence_name</a><br\>
[_ intranet-cust-nts.Type]: [im_category_from_id -locale [lang::user::site_wide_locale -user_id $owner_id] $absence_type_id]<br\>
[_ intranet-cust-nts.Start_Date]: $start_date_pretty<br\>
[_ intranet-cust-nts.Ende_Date]: $end_date_pretty<br\>
[_ intranet-cust-nts.Duration_Days]: $duration_days<br\>
[_ intranet-cust-nts.Description]: $description<br\>
[_ intranet-cust-nts.Contact_Information]: $contact_info<br\>
[_ intranet-cust-nts.Vacation_Replacement]: [im_name_from_user_id $vacation_replacement_id]
<p\>
[_ intranet-cust-nts.Projectleads]: [join $pm_html_parts ";"]
<p\>
$workflow_msg
    "
    
    if {"ProjectOpen.Hamburg@de.neusoft.com" == "[ad_system_owner]"} {
        # This is the production system, send out E-Mails
        acs_mail_lite::send -to_addr $to_addr -from_addr $from_addr -cc_addr $cc_addr -subject $subject -body $body \
            -send_immediately -mime_type "text/html" -use_sender
    } else {
        append body "
        <p\>
        This E-Mail was supposed to go to $to_addr and have $cc_addr in CC
        "
        acs_mail_lite::send -to_addr "[ad_system_owner]" -from_addr $from_addr -cc_addr "" -subject $subject -body $body \
            -send_immediately -mime_type "text/html" -use_sender
            
    }
    
    ns_log Notice "Workflow mail send from $from_addr to $to_addr and subject $subject"
    if {$type == "new"} {
        # Let's record the initial mail request in the workflow journal
    	set case_id [db_string get_case "select case_id from wf_cases where object_id = :absence_id" -default ""]
        if {$case_id != ""} {
            im_workflow_new_journal -case_id $case_id -action "modify absence" -action_pretty "Modify Absence" -message "[_ intranet-cust-nts.lt_Information_about_req]: $to_addr"
        }
    } 
    return 1
}

ad_proc -public -callback im_user_absence_after_create -impl nts_inform {
    {-object_id:required}
    {-status_id ""}
    {-type_id ""}
} {
    Inform the project managers and supervisors of the created absence
} {
   return [im_nts_absence_inform -absence_id $object_id -type new]
}

ad_proc -public -callback im_user_absence_before_create -impl nts_students {
    {-object_id:required}
    {-status_id ""}
    {-type_id ""}
} {
    Check if the owner is a student and then let the workflow run for HR instead
} {
    if {[group::member_p -group_name "Students"]} {
        upvar wf_key wf_key
        set wf_key "hr_vacation_approval_wf"
    }
}

ad_proc -public -callback im_user_absence_after_update -impl nts_inform {
    {-object_id:required}
    {-status_id ""}
    {-type_id ""}
} {
    Inform the project managers and supervisors of the changed absence
} {
    return [im_nts_absence_inform -absence_id $object_id -type edit] 
}

ad_proc -public -callback im_user_absence_after_delete -impl nts_inform {
    {-object_id:required}
    {-status_id ""}
    {-type_id ""}
} {
    Inform the project managers and supervisors of the cancelled absence
} {
    return [im_nts_absence_inform -absence_id $object_id -type cancelled] 
}

ad_proc -public -callback im_user_absence_before_delete -impl nts_storno_check {
    {-object_id:required}
    {-status_id ""}
    {-type_id ""}
} {
    Check whether we need to start a new workflow or can just let the code continue
} {
    db_1row absence_info "select owner_id, absence_status_id from im_user_absences where absence_id = :object_id"
    if {[im_user_absence_status_requested] != $absence_status_id} {
        # Do not allow this to continue
        ns_log Notice "A new workflow should have been started for cancellation of Absence $object_id"
	
        # Enable support to let HR Pass
        if {[im_user_is_hr_p [ad_conn user_id]]} {
            # Do Nothing
            return 1
        } else  {       
            # Throw an error for now. In the future a new workflow should
            # be started and the user should be redirected somewhere ...
            
            # Check if we have a running workflow already
    	    set context_key ""
            set wf_key "vacation_storno_wf"
            set case_id [db_string case_id "select case_id from wf_cases where object_id = :object_id and workflow_key = :wf_key and state='active' limit 1" -default ""]
            if {$case_id == ""} {
                set case_id [wf_case_new \
    			     $wf_key \
    			     $context_key \
    			     $object_id
    			]
            }

            set task_id [db_string task "select max(task_id) from wf_tasks where case_id = :case_id"]
            
            upvar return_url return_url
            ad_returnredirect [export_vars -base "/acs-workflow/task" -url {task_id return_url}]
            # ad_return_error "[_ intranet-cust-nts.Not_allowed]" "[_ intranet-cust-nts.lt_You_are_not_allowed_t]"
            ad_script_abort
            return 0
        }
    } else {
	    return 1
    }
}


ad_proc -public -callback im_user_absence_on_submit -impl nts_check_for_comment {
    {-object_id:required}
    {-form_id:required}

} {
    Check the lead time and if a comment is needed
} {
    upvar duration_days duration_days
    upvar start_date start_date
    upvar description description
    upvar absence_type_id absence_type_id
    upvar error_field error_field
    upvar error_message error_message
 
    set today [db_string today "select to_char(now(),'YYYY-MM-DD') from dual"]
    set lead_days [im_absence_week_days -start_date "$today" -end_date "[join [template::util::date get_property linear_date_no_time $start_date] "-"]" -week_day_list [list 1 2 3 4 5 6] -type "sum"]
    set lead_days [expr $lead_days "-1"]
    if {$duration_days <6} {
	    if {$lead_days < $duration_days && "" == $description} {
            set error_field "description"
            set error_message "[_ intranet-cust-nts.lt_Your_lead_time_of_lea]"
	    } 
    } else {
        if {$lead_days< [expr $duration_days * 2] && "" == $description} {
            set error_field "description"
            set error_message "[_ intranet-cust-nts.lt_Your_lead_time_of_lea]"
	    }
    }
    
    # Also check if we have a special absence
    if {$absence_type_id == 5002 && $description == ""} {
        set error_field "description"
        set error_message "[_ intranet-cust-nts.lt_Your_request_special]"        
    }
}


ad_proc -public -callback workflow_task_on_submit -impl nts_check_for_msg {
    {-task_id:required}
    {-form_id:required}
    {-workflow_key:required}

} {
    Check the lead time and if a comment is needed
} {
    upvar msg msg
    upvar error_field error_field
    upvar error_message error_message

    
    switch $workflow_key {
        "vacation_approval_wf" {
            upvar attributes(review_reject_p) review_reject_p
            if {[info exists review_reject_p] && $review_reject_p == "f"} {
                # We have a rejection here 
                if {"" == $msg} {
                    # Throw an error
                    set error_field "msg"
                    set error_message "[_ intranet-cust-nts.lt_Please_enter_a_commen]"
                }
            }        
        }
        "hr_vacation_approval_wf" {
            upvar attributes(review_reject_p) review_reject_p
            if {[info exists review_reject_p] && $review_reject_p == "f"} {
                # We have a rejection here 
                if {"" == $msg} {
                    # Throw an error
                    set error_field "msg"
                    set error_message "[_ intranet-cust-nts.lt_Please_enter_a_commen]"
                }
            }
            upvar attributes(hr_review_reject_p) hr_review_reject_p
            if {[info exists hr_review_reject_p] && $hr_review_reject_p == "f"} {
                # We have a rejection here 
                if {"" == $msg} {
                    # Throw an error
                    set error_field "msg"
                    set error_message "[_ intranet-cust-nts.lt_Please_enter_a_commen]"
                }
            }        
        }
        vacation_storno_wf {
            upvar attributes(approve_storno_p) approve_storno_p
            if {[info exists approve_storno_p] && $approve_storno_p == "f"} {
                # We have a rejection here 
                if {"" == $msg} {
                    # Throw an error
                    set error_field "msg"
                    set error_message "[_ intranet-cust-nts.lt_Please_enter_a_commen]"
                }
            } 
            upvar attributes(storno_reason) storno_reason
            if {[info exists storno_reason] && $storno_reason == ""} {
                # Throw an error
                set error_field "attributes.storno_reason"
                set error_message "Please provide a reason"
            }       
        }        
    }
}

ad_proc -public -callback workflow_task_after_update -impl nts_inform {
    {-task_id:required}
    {-action:required}
    {-msg ""}
    {-attributes ""}
} {
    Send the appropriate E-Mails
} {
    array set task [wf_task_info $task_id]
    set absence_id $task(object_id)

    # This workflow should only be executed for absence workflows 
    
    switch $task(workflow_key) {
    
        "vacation_approval_wf" - "hr_vacation_approval_wf" {
            foreach { key value} $attributes {
                set $key $value
            }
    
            if {[info exists review_reject_p]} {
                
                # A supervisor is approving/rejecting the absence            
                if {$review_reject_p == "f"} {
                    # We have a rejection here 
                    return [im_nts_absence_inform -absence_id $absence_id -type rejected -msg $msg] 
                } else {
                    return [im_nts_absence_inform -absence_id $absence_id -type approved -msg $msg] 
                }
            }
            if {[info exists hr_review_reject_p]} {
                if {$hr_review_reject_p == "f"} {
                    return [im_nts_absence_inform -absence_id $absence_id -type hr_rejected -msg $msg] 
                } else {
                    return [im_nts_absence_inform -absence_id $absence_id -type hr_approved -msg $msg] 
                }
            }
        }
        "vacation_storno_wf" {
            foreach { key value} $attributes {
                set $key $value
            }    
            if {[info exists approve_storno_p]} {
                
                # Supervisor is reviewing the task
                if {$approve_storno_p == "f"} {
                    # We have a rejection here 
                    return [im_nts_absence_inform -absence_id $absence_id -type storno_rejected -msg $msg] 
                } else {
                    return [im_nts_absence_inform -absence_id $absence_id -type storno_approved -msg $msg] 
                }
            }
            if {[info exists storno_reason]} {
                # This is a new request
                return [im_nts_absence_inform -absence_id $absence_id -type storno_requested -msg $storno_reason]
            }     
        }
    }
}


ad_proc -public -callback im_user_absence_new_actions -impl nts-storno-workflow {
} {
    Add a link to cancel the storno workflow 
} {
    uplevel {
        if {[info exists absence_id] && $owner_id eq $user_id} {
            set active_storno_workflow_p [db_string wf_control "
            	    select	count(*)
                    from	wf_cases
                    where	object_id = :absence_id
                    and workflow_key = 'vacation_storno_wf'
                    and state = 'active'
                " -default 0]

            if {$active_storno_workflow_p} {
                # Remove the actions and overwrite it with a cancel button for the workflow if the user is the owner
                set actions ""
	            lappend actions [list [lang::message::lookup {} intranet-cust-nts.Cancel_Storno_WF "Cancel the storno workflow"] cancel_storno_wf]
                return 1
            } 
            
            # Check if we have a vacation in the past and then remove the right to change or delete it for the owner
            set active_past_vacation_p [db_string check_vacation "select 1 from im_user_absences where absence_status_id = [im_user_absence_status_active] and start_date < now() and absence_id = :absence_id" -default 0]
            if {$active_past_vacation_p} {
                set actions ""
            }
        }
        if {[acs_user::site_wide_admin_p -user_id $user_id] && $actions == ""} {
	        lappend actions [list [lang::message::lookup {} intranet-timesheet2.Delete Delete] delete]
        }
    }
}

ad_proc -public -callback im_user_absence_info_actions -impl nts-storno-workflow {
} {
    Add a link to cancel the storno workflow 
} {
    uplevel {
        if {[info exists absence_id] && $owner_id eq $current_user_id} {
            set active_storno_workflow_p [db_string wf_control "
            	    select	count(*)
                    from	wf_cases
                    where	object_id = :absence_id
                    and workflow_key = 'vacation_storno_wf'
                    and state = 'active'
                " -default 0]
        
            if {$active_storno_workflow_p} {
                # Remove the actions and overwrite it with a cancel button for the workflow if the user is the owner
                set actions_html ""
                append actions_html "<input type=\"submit\" name=\"formbutton:cancel_storno_wf\" value=\"[lang::message::lookup {} intranet-cust-nts.Cancel_Storno_WF "Cancel the storno workflow"]\">"
                return 1
            } 
            
            # Check if we have a vacation in the past and then remove the right to change or delete it for the owner
            set active_past_vacation_p [db_string check_vacation "select 1 from im_user_absences where absence_status_id = [im_user_absence_status_active] and start_date < now() and absence_id = :absence_id" -default 0]
            if {$active_past_vacation_p} {
                set actions_html ""
            }
        }
    }
}



ad_proc -public -callback im_user_absence_new_button_pressed -impl nts-storno-cancel {
    {-button_pressed:required} 
} {
    Cancel the workflow for the absence and go back to the view page
} {
    if {$button_pressed eq "cancel_storno_wf"} {
        upvar absence_id absence_id
        upvar user_id user_id
        
        set case_id [db_string case "select case_id from wf_cases where object_id = :absence_id and workflow_key = 'vacation_storno_wf' and state = 'active'"]
    
        if {[catch {wf_case_cancel -msg "Storno for Absence was cancelled by [im_name_from_user_id $user_id]" $case_id}]} {
            #Record the change manually, as the workflow did fail (probably because the case is already closed
            im_workflow_new_journal -case_id $case_id -action "cancel storno" -action_pretty "Cancel Storno" -message "Storno for Absence was cancelled by [im_name_from_user_id $user_id]"
        }

	# Update the task and the absence
	db_dml finish_task "update wf_tasks set state = 'finished', finished_date = now() where case_id = :case_id and state <> 'finished'" 
        db_dml activate_absence "update im_user_absences set absence_status_id = [im_user_absence_status_active] where absence_id = :absence_id"
         
        # Return to the absence, now without storno workflow
    	ad_returnredirect [export_vars -base "/intranet-timesheet2/absences/new" -url {absence_id {form_mode "display"}}]
    }
}

ad_proc -public -callback im_user_absence_perm_check -impl nts-view-permissions {
    {-absence_id:required}
} {
    Only allow the owner, supervisor, hr and pms to view the absence
} {
    
    # Check if we are editing
    if {[db_string check_absense "select count(*) from im_user_absences where absence_id = :absence_id"]} {
        db_1row absence_info "select owner_id, vacation_replacement_id,to_char(start_date,'YYYY-MM-DD') as start_date,to_char(end_date,'YYYY-MM-DD') as end_date
        from im_user_absences where absence_id = :absence_id"
    
        set pm_ids [planning_item::get_project_managers -user_id $owner_id -start_date $start_date -end_date $end_date]
        set supervisor_id [db_string supervisor "select supervisor_id from im_employees where employee_id = :owner_id"  -default ""]
        set hr_ids [group::get_members -group_id [im_hr_group_id]]
 
        set viewer_ids [concat $owner_id $vacation_replacement_id $pm_ids $supervisor_id $hr_ids]
        set user_id [ad_conn user_id]

    
        if {[lsearch $viewer_ids $user_id]<0} {
            # Get assigned user and check if he is allowed
            set sql "
                select 1 
                from wf_cases wfc 
                inner join wf_user_tasks ut
                on (ut.case_id=wfc.case_id)
                where wfc.object_id = :absence_id
                and ut.user_id = :user_id
                limit 1
            "
            
            set assigned_to_user_p [db_string assigned_to_user_p $sql -default 0]
            
            if { !$assigned_to_user_p } { 
                # The user should not see this absence
                ad_return_error "Not allowed" "You are not allowed to view this absence"
            }
        }
    }
}

ad_proc -public -callback auth::ldap::batch_import::parse_user_after_update -impl nts-department {
    -user_id:required
    -dn:required
} {
    Import the user into the department based on the first OU entry and add the supervisor as the manager of that department    
} {
    # Find the first OU entry
    foreach dn_entry [split $dn ","] {
        set dn_list [split $dn_entry "="]
        if {[lindex $dn_list 0]=="OU"} {
            set department_name [lindex $dn_list 1]
            break
        }
    }
    
    # KH: Department names 'Country, Dep' and 'Country -Dep' will result in same label, so we have check its existence
	set department_label [string tolower $department_name]
	regsub -all -nocase {[^a-zA-Z0-9]} $department_label "_" department_label

	set department_id [db_string uid "
		select	min(cost_center_id)
		from	im_cost_centers
		where	lower(cost_center_name) = lower(:department_name) OR
			lower(cost_center_label) = lower(:department_name) OR
			lower(cost_center_code) = lower(:department_name) OR 
			lower(cost_center_label) = lower(:department_label)
	" -default 0]
    
	# Create a cost center if it didn't exist yet
	if {"" == $department_id || 0 == $department_id} {

	    set department_name [string trim $department_name]
	    set department_code "Co[string range $department_name 0 0][string range $department_label 1 1]"
	    set exists_p [db_string ccex "select count(*) from im_cost_centers where cost_center_code = :department_code"]
	    set ctr 0
	    while {$exists_p && $ctr < 20} {
		set department_code "Co[expr int(rand() * 10.0)][expr int(rand() * 10.0)]"
		set exists_p [db_string ccex "select count(*) from im_cost_centers where cost_center_code = :department_code"]
		incr ctr
	    }
	    ns_log Notice "auth::ldap::batch_import::parse_user: department_name=$department_name, department_label=$department_label, department_code=$department_code"

	    set department_id [db_string new_dept "
		select im_cost_center__new(
			null,					-- cost_center_id default null
			'im_cost_center',			-- object_type default 'im_cost_center'
			now(),					-- creation_date default now()
			[ad_get_user_id],			-- creation_user default null
			'[ns_conn peeraddr]',			-- creation_ip default null
			null,					-- context_id default null
			:department_name,			-- cost_center_name
			:department_label,			-- cost_center_label
			:department_code,			-- cost_center_code
			[im_cost_center_type_cost_center],	-- type_id
			[im_cost_center_status_active],		-- status_id
			[im_cost_center_company],		-- parent_id
			null,					-- manager_id default null
			't',					-- department_p default 't'
			'Automatically created from LDAP Import',	-- description default null
			null					-- note default null
		)
	    "]
	}
    
    db_dml nts_update_emp_dept "
	    update im_employees set 
		    department_id = :department_id
        where employee_id = :user_id
    "

    # Get the supervisor from the manager of the cost_center
    set supervisor_id [db_string get_manager "select manager_id from im_cost_centers where cost_center_id = :department_id" -default ""]

    if {$user_id eq $supervisor_id} {
        set supervisor_id [db_string get_manager_up "select manager_id from im_cost_centers where cost_center_id = (select parent_id from im_cost_centers where cost_center_id = :department_id)" -default $user_id]
    }
    
    if {$supervisor_id ne "" && $supervisor_id ne $user_id} {
        db_dml nts_update_emp_dept "
		    update im_employees set 
                supervisor_id = :supervisor_id
            where employee_id = :user_id
        "
    } else {
        ds_comment "No Supervisor for $user_id in $department_id"
    }
}

ad_proc -public im_nts_update_from_ldap {
} {
    Update all existing usernames from ldap
} {
    set user_names [db_list users "select distinct username from users"]

    foreach username $user_names {
        set count [db_string count "select count(*) from users where lower(username) = :username"]
        if {$count>1} {
            ds_comment "$username counted $count"
        } else {
            auth::ldap::authentication::Sync $username "LdapURI ldap://172.31.0.10:389 BaseDN dc=NTS,dc=Neusoft,dc=local BindDN {{username}@nts.neusoft.local} SystemBindDN cn=project-open_LDAP,OU=_Service-Accounts,OU=IT,OU=HH,DC=nts,DC=neusoft,DC=local SystemBindPW Offen&porjekt&123 ServerType ad GroupMap {Administrators 459 Users 463 Guests 465} SearchFilter {}" 32162
        }
    }        
}

ad_proc -public im_nts_absence_request_reminder {
} {
    Sends absence request reminders.
} {

    ns_log Notice "Running im_nts_absence_request_reminder"
    set sql "
        select 
            ut.task_id, 
            wfc.case_id, 
            ut.transition_key, 
            a.owner_id, 
            person__name(a.owner_id) as owner_name, 
            o.creation_user, 
            o.creation_ip,
            
            absence_id,
            im_name_from_id(absence_type_id) as absence_type, 
            to_char(start_date,'YYYY-MM-DD') as start_date, 
            to_char(end_date,'YYYY-MM-DD') as end_date, 
            duration_days, 
            description, 
            contact_info, 
            person__name(vacation_replacement_id) as vacation_replacement_name 

        from im_user_absences a 
        inner join wf_cases wfc 
        on (wfc.object_id=a.absence_id) 
        inner join wf_user_tasks ut 
        on (ut.case_id=wfc.case_id) inner join acs_objects o on (o.object_id=absence_id) 
        where wfc.state='active' 
        and enabled_date < now() - '12 days'::interval
        and wfc.workflow_key='vacation_approval_wf'
    "

    # If the workflow is still open after 10 days, set it to approved 
    # (this involves setting the workflow value for the question "approved?") 
    # and finish the workflow.

    set reqs [db_list_of_lists reqs_10_days_over $sql]

    foreach req $reqs {
        foreach {task_id case_id transition_key owner_id owner_name creation_user creation_ip
                 absence_id absence_type start_date end_date duration_days description contact_info
                 vacation_replacement_name} $req break

        # first sends message, then auto-approves (must be done in that order)
        db_transaction {

            # First line will be i18n string of the following:
            # "This request was based on the works council agreement automatically approved 10 days after submitting."
            set msg "Approved automatically after 12 days."

            im_nts_absence_inform -absence_id $absence_id -type "10_days_over"

            db_exec_plsql auto_approve_task "
                select im_workflow__auto_approve_task(
                    :task_id,
                    :case_id,
                    :transition_key,
                    :owner_id,
                    :owner_name,
                    :creation_user,
                    :creation_ip,
                    :transition_key || ' auto_approve_10_days_over ' || :owner_name,
                    'Approved automatically after 12 days.'
                ) 
            "

            ns_log Notice "im_nts_absence_request_reminder automatically approved $absence_id"
        }

    }


    set sql "
        select 
            absence_id,
            ut.case_id,
            task_id,
            transition_key,
            ut.user_id,
            creation_user,
            creation_ip,
            object_type,
            person__name(owner_id) as owner_name, 
            im_name_from_id(absence_type_id) as absence_type, 
            to_char(start_date,'YYYY-MM-DD') as start_date, 
            to_char(end_date,'YYYY-MM-DD') as end_date, 
            duration_days, 
            description, 
            contact_info,
            enabled_date,
            person__name(vacation_replacement_id) as vacation_replacement_name 
        from im_user_absences a 
        inner join wf_cases wfc 
        on (wfc.object_id=a.absence_id) 
        inner join wf_user_tasks ut 
        on (ut.case_id=wfc.case_id) 
        inner join acs_objects o
        on (o.object_id = wfc.case_id)
        where wfc.state='active' 
        and enabled_date + '9 days'::interval < now()
        and enabled_date + '10 days'::interval > now()
        and wfc.workflow_key='vacation_approval_wf'
    "

    db_foreach reqs_8_days_over $sql {
         
        set replacement_p [db_string assign_replacement_if_needed "
            select im_workflow__assign_to_vacation_replacement_if(
                :task_id,
                :case_id,
                :user_id,
                :user_id,
                :transition_key,
                :creation_user,
                :creation_ip,
                :object_type
            )
        " -default 0]
 

        # First line will be i18n string of the following:
        set msg "PLEASE PROCESS this Absence Request. Otherwise it will be automatically approved in 3 days!"

        im_nts_absence_inform -absence_id $absence_id -type "7_days_over"
        ns_log Notice "im_nts_absence_request_reminder automatically reminded for $absence_id"

    }

}

ad_proc -public -impl im_member_add_students -callback im_member_add__extend_form {
    {-object_id:required ""}
    {-role_id:required ""}
    {-select_formVar:required ""}
    {-limit_to_group_id ""}
    {-notify_checked ""}
} {
    Callback that extends the html for selecting employees
    in intranet/member-add.
} {

    upvar $select_formVar select_form

    set students_select [im_student_select_multiple -limit_to_group_id $limit_to_group_id user_id_from_search "" 12 multiple]

    append select_form "
    <td>
    <form method=POST action=/intranet/member-add-2>
    [export_entire_form]
    <input type=hidden name=target value=\"[im_url_stub]/member-add-2\">
    <input type=hidden name=passthrough value=\"object_id role_id return_url also_add_to_object_id\">
    <table cellpadding=0 cellspacing=2 border=0>
      <tr> 
        <td class=rowtitle align=middle>[_ intranet-cust-nts.Student]</td>
      </tr>
      <tr> 
        <td>
    $students_select
        </td>
      </tr>
      <tr> 
        <td>[_ intranet-core.add_as] 
    [im_biz_object_roles_select role_id $object_id $role_id]
        </td>
      </tr>
      <tr> 
        <td>
          <input type=submit value=\"[_ intranet-core.Add]\">
          <input type=checkbox name=notify_asignee value=1 $notify_checked>[_ intranet-core.Notify]
        </td>
      </tr>
    </table>
    </form>
    </td>
    "

}

ad_proc im_nts_absence_new_page_wf_perm_edit_button {
    -absence_id:required
} {
    Should we show the "Edit" button in the AbsenceNewPage?
    The button is visible only for the Owner of the absence
    and the Admin, but nobody else during the course of the WF.
    Also, the Absence should not be changed anymore once it has
    started.
} {
    set perm_table [im_absence_new_page_wf_perm_table]
    set perm_set [im_workflow_object_permissions \
            -object_id $absence_id \
            -perm_table $perm_table
    ]

    # Special check for HR. If the owner is looking at an approved absence
    # Do not allow the edit button.
    db_1row absence_info "select owner_id, absence_status_id from im_user_absences where absence_id = :absence_id"
    set user_id [ad_conn user_id]
    
    if {[lsearch [im_sub_categories [im_user_absence_status_active]] $absence_status_id]>-1 && $owner_id == $user_id} {
        return 0
    } else {
        return [expr [lsearch $perm_set "w"] > -1]        
    }
}

