%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et nomod:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI Service API Module==
%%% A module that exposes dynamic configuration of CloudI.
%%% @end
%%%
%%% MIT License
%%%
%%% Copyright (c) 2011-2020 Michael Truog <mjtruog at protonmail dot com>
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a
%%% copy of this software and associated documentation files (the "Software"),
%%% to deal in the Software without restriction, including without limitation
%%% the rights to use, copy, modify, merge, publish, distribute, sublicense,
%%% and/or sell copies of the Software, and to permit persons to whom the
%%% Software is furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in
%%% all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
%%% DEALINGS IN THE SOFTWARE.
%%%
%%% @author Michael Truog <mjtruog at protonmail dot com>
%%% @copyright 2011-2020 Michael Truog
%%% @version 1.8.1 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_service_api).
-author('mjtruog at protonmail dot com').

%% external interface
-export([acl_add/2,
         acl_remove/2,
         acl/1,
         service_subscriptions/2,
         services_add/2,
         services_remove/2,
         services_restart/2,
         services_suspend/2,
         services_resume/2,
         services_search/2,
         services_status/2,
         services_update/2,
         services/1,
         nodes_set/2,
         nodes_get/1,
         nodes_add/2,
         nodes_remove/2,
         nodes_alive/1,
         nodes_dead/1,
         nodes_status/2,
         nodes/1,
         logging_set/2,
         logging_file_set/2,
         logging_level_set/2,
         logging_stdout_set/2,
         logging_syslog_set/2,
         logging_formatters_set/2,
         logging_redirect_set/2,
         logging/1,
         code_path_add/2,
         code_path_remove/2,
         code_path/1,
         code_status/1]).

-include("cloudi_service_api.hrl").
-include("cloudi_core_i_constants.hrl").

-type dest_refresh() ::
    lazy_closest | immediate_closest |
    lazy_furthest | immediate_furthest |
    lazy_random | immediate_random |
    lazy_local | immediate_local |
    lazy_remote | immediate_remote |
    lazy_newest | immediate_newest |
    lazy_oldest | immediate_oldest |
    none.
-export_type([dest_refresh/0]).

-type priority() ::
    ?PRIORITY_HIGH..?PRIORITY_LOW.
-export_type([priority/0]).

-type dest_refresh_delay_milliseconds() ::
    ?DEST_REFRESH_DELAY_MIN..?DEST_REFRESH_DELAY_MAX.
-export_type([dest_refresh_delay_milliseconds/0]).

-type timeout_initialize_value_milliseconds() ::
    ?TIMEOUT_INITIALIZE_MIN..?TIMEOUT_INITIALIZE_MAX.
-type timeout_initialize_milliseconds() ::
    limit_min | limit_max | timeout_initialize_value_milliseconds().
-export_type([timeout_initialize_value_milliseconds/0,
              timeout_initialize_milliseconds/0]).

-type timeout_send_async_value_milliseconds() ::
    ?TIMEOUT_SEND_ASYNC_MIN..?TIMEOUT_SEND_ASYNC_MAX.
-type timeout_send_async_milliseconds() ::
    limit_min | limit_max | timeout_send_async_value_milliseconds().
-export_type([timeout_send_async_value_milliseconds/0,
              timeout_send_async_milliseconds/0]).

-type timeout_send_sync_value_milliseconds() ::
    ?TIMEOUT_SEND_SYNC_MIN..?TIMEOUT_SEND_SYNC_MAX.
-type timeout_send_sync_milliseconds() ::
    limit_min | limit_max | timeout_send_sync_value_milliseconds().
-export_type([timeout_send_sync_value_milliseconds/0,
              timeout_send_sync_milliseconds/0]).

-type timeout_terminate_value_milliseconds() ::
    ?TIMEOUT_TERMINATE_MIN..?TIMEOUT_TERMINATE_MAX.
-type timeout_terminate_milliseconds() ::
    limit_min | limit_max | timeout_terminate_value_milliseconds().
-export_type([timeout_terminate_value_milliseconds/0,
              timeout_terminate_milliseconds/0]).

-type request_timeout_immediate_max_value_milliseconds() ::
    0..?TIMEOUT_MAX_ERLANG.
-type request_timeout_immediate_max_milliseconds() ::
    limit_min | limit_max | request_timeout_immediate_max_value_milliseconds().
-export_type([request_timeout_immediate_max_value_milliseconds/0,
              request_timeout_immediate_max_milliseconds/0]).

-type response_timeout_immediate_max_value_milliseconds() ::
    0..?TIMEOUT_MAX_ERLANG.
-type response_timeout_immediate_max_milliseconds() ::
    limit_min | limit_max | response_timeout_immediate_max_value_milliseconds().
-export_type([response_timeout_immediate_max_value_milliseconds/0,
              response_timeout_immediate_max_milliseconds/0]).

-type restart_delay_value_milliseconds() ::
    0..?TIMEOUT_MAX_ERLANG.
-type restart_delay_milliseconds() ::
    limit_min | limit_max | restart_delay_value_milliseconds().
-export_type([restart_delay_value_milliseconds/0,
              restart_delay_milliseconds/0]).

-type latency_mean_time_value_milliseconds() ::
    0..?TIMEOUT_MAX_ERLANG.
-type latency_mean_time_milliseconds() ::
    limit_min | limit_max | latency_mean_time_value_milliseconds().
-type latency_min_time_value_milliseconds() ::
    0..?TIMEOUT_MAX_ERLANG.
-type latency_min_time_milliseconds() ::
    limit_min | limit_max | latency_min_time_value_milliseconds().
-type latency_max_time_value_milliseconds() ::
    1..?TIMEOUT_MAX_ERLANG.
-type latency_max_time_milliseconds() ::
    limit_min | limit_max | latency_max_time_value_milliseconds().
-type latency_time_value_milliseconds() ::
    1..?TIMEOUT_MAX_ERLANG.
-type latency_time_milliseconds() ::
    limit_min | limit_max | latency_time_value_milliseconds().
-export_type([latency_mean_time_value_milliseconds/0,
              latency_mean_time_milliseconds/0,
              latency_min_time_value_milliseconds/0,
              latency_min_time_milliseconds/0,
              latency_max_time_value_milliseconds/0,
              latency_max_time_milliseconds/0,
              latency_time_value_milliseconds/0,
              latency_time_milliseconds/0]).

-type acl() ::
    list(atom() | cloudi:service_name_pattern()).
-export_type([acl/0]).

-type dest_list() ::
    acl() | undefined.
-export_type([dest_list/0]).

-type seconds() ::
    non_neg_integer().
-export_type([seconds/0]).

-type period_seconds() ::
    1..(?TIMEOUT_MAX_ERLANG div 1000).
-export_type([period_seconds/0]).

-type aspect_init_after_internal_f() ::
    fun((Args :: list(),
         Prefix :: cloudi_service:service_name_pattern(),
         Timeout :: timeout_initialize_value_milliseconds(),
         State :: any(),
         Dispatcher :: cloudi_service:dispatcher()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_init_after_external_f() ::
    fun((CommandLine :: list(string()),
         Prefix :: cloudi:service_name_pattern(),
         Timeout :: timeout_initialize_value_milliseconds(),
         State :: any()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_init_after_internal() ::
    aspect_init_after_internal_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_init_after_external() ::
    aspect_init_after_external_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-export_type([aspect_init_after_internal_f/0,
              aspect_init_after_external_f/0,
              aspect_init_after_internal/0,
              aspect_init_after_external/0]).
-type aspect_request_before_internal_f() ::
    fun((RequestType :: cloudi_service:request_type(),
         Name :: cloudi_service:service_name(),
         Pattern :: cloudi_service:service_name_pattern(),
         RequestInfo :: cloudi_service:request_info(),
         Request :: cloudi_service:request(),
         Timeout :: cloudi_service:timeout_value_milliseconds(),
         Priority :: cloudi_service:priority(),
         TransId :: cloudi_service:trans_id(),
         Source :: cloudi_service:source(),
         State :: any(),
         Dispatcher :: cloudi_service:dispatcher()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_request_before_external_f() ::
    fun((RequestType :: cloudi_service:request_type(),
         Name :: cloudi_service:service_name(),
         Pattern :: cloudi_service:service_name_pattern(),
         RequestInfo :: cloudi_service:request_info(),
         Request :: cloudi_service:request(),
         Timeout :: cloudi_service:timeout_value_milliseconds(),
         Priority :: cloudi_service:priority(),
         TransId :: cloudi_service:trans_id(),
         Source :: cloudi_service:source(),
         State :: any()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_request_after_internal_f() ::
    fun((RequestType :: cloudi_service:request_type(),
         Name :: cloudi_service:service_name(),
         Pattern :: cloudi_service:service_name_pattern(),
         RequestInfo :: cloudi_service:request_info(),
         Request :: cloudi_service:request(),
         Timeout :: cloudi_service:timeout_value_milliseconds(),
         Priority :: cloudi_service:priority(),
         TransId :: cloudi_service:trans_id(),
         Source :: cloudi_service:source(),
         Result :: cloudi_service:request_result(),
         State :: any(),
         Dispatcher :: cloudi_service:dispatcher()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_request_after_external_f() ::
    fun((RequestType :: cloudi_service:request_type(),
         Name :: cloudi_service:service_name(),
         Pattern :: cloudi_service:service_name_pattern(),
         RequestInfo :: cloudi_service:request_info(),
         Request :: cloudi_service:request(),
         Timeout :: cloudi_service:timeout_value_milliseconds(),
         Priority :: cloudi_service:priority(),
         TransId :: cloudi_service:trans_id(),
         Source :: cloudi_service:source(),
         Result :: cloudi_service:request_result(),
         State :: any()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_request_before_internal() ::
    aspect_request_before_internal_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_request_before_external() ::
    aspect_request_before_external_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_request_after_internal() ::
    aspect_request_after_internal_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_request_after_external() ::
    aspect_request_after_external_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-export_type([aspect_request_before_internal_f/0,
              aspect_request_before_external_f/0,
              aspect_request_after_internal_f/0,
              aspect_request_after_external_f/0,
              aspect_request_before_internal/0,
              aspect_request_before_external/0,
              aspect_request_after_internal/0,
              aspect_request_after_external/0]).
-type aspect_info_internal_f() ::
    fun((Request :: any(),
         State :: any(),
         Dispatcher :: cloudi_service:dispatcher()) ->
        {ok, StateNew :: any()} |
        {stop, Reason :: any(), StateNew :: any()}).
-type aspect_info_internal() ::
    aspect_info_internal_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_info_before_internal_f() ::
    aspect_info_internal_f().
-type aspect_info_after_internal_f() ::
    aspect_info_internal_f().
-type aspect_info_before_internal() ::
    aspect_info_internal().
-type aspect_info_after_internal() ::
    aspect_info_internal().
-export_type([aspect_info_before_internal_f/0,
              aspect_info_after_internal_f/0,
              aspect_info_before_internal/0,
              aspect_info_after_internal/0]).
-type aspect_terminate_f() ::
    fun((Reason :: any(),
         Timeout :: timeout_terminate_value_milliseconds(),
         State :: any()) ->
        {ok, State :: any()}).
-type aspect_terminate_before_internal_f() ::
    aspect_terminate_f().
-type aspect_terminate_before_external_f() ::
    aspect_terminate_f().
-type aspect_terminate_before_internal() ::
    aspect_terminate_before_internal_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_terminate_before_external() ::
    aspect_terminate_before_external_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-export_type([aspect_terminate_before_internal_f/0,
              aspect_terminate_before_external_f/0,
              aspect_terminate_before_internal/0,
              aspect_terminate_before_external/0]).

-type max_heap_size_options() ::
    non_neg_integer() |
    #{size => non_neg_integer(),
      kill => boolean(),
      error_logger => boolean()}.
-export_type([max_heap_size_options/0]).

-type limit_external_key() ::
    as | core | cpu | data | fsize | memlock | msgqueue | nice | nofile |
    nproc | rss | rtprio | rttime | sigpending | stack | vmem.
-type limit_external_value() ::
    undefined |
    non_neg_integer() | infinity | % sets current
    list({current, non_neg_integer() | infinity} |
         {maximum, non_neg_integer() | infinity}).
-type limit_external() ::
    system |
    list({limit_external_key(), limit_external_value()}).
-type owner_external() ::
    list({user, pos_integer() | string()} |
         {group, pos_integer() | string()}).
-type nice_external() ::
    -20..20.
-type cgroup_external() ::
    undefined |
    list({name, nonempty_string()} |
         {parameters, list({nonempty_string(), string()})} |
         {update_or_create, boolean()}).
-type chroot_external() ::
    file:filename() | undefined.
-type directory_external() ::
    file:filename() | undefined.
-export_type([limit_external_key/0,
              limit_external_value/0,
              limit_external/0,
              owner_external/0,
              nice_external/0,
              cgroup_external/0,
              chroot_external/0,
              directory_external/0]).

-type service_options_internal() ::
    list({priority_default, priority()} |
         {queue_limit, undefined | non_neg_integer()} |
         {queue_size, undefined | pos_integer()} |
         {rate_request_max,
          list({period, period_seconds()} |
               {value, number()}) | number() | undefined} |
         {dest_refresh_start, dest_refresh_delay_milliseconds()} |
         {dest_refresh_delay, dest_refresh_delay_milliseconds()} |
         {request_name_lookup, sync | async} |
         {request_timeout_adjustment, boolean()} |
         {request_timeout_immediate_max,
          request_timeout_immediate_max_milliseconds()} |
         {response_timeout_adjustment, boolean()} |
         {response_timeout_immediate_max,
          response_timeout_immediate_max_milliseconds()} |
         {count_process_dynamic,
          list({period, period_seconds()} |
               {rate_request_max, number()} |
               {rate_request_min, number()} |
               {count_max, number()} |
               {count_min, number()}) | false} |
         {timeout_terminate,
          undefined | timeout_terminate_milliseconds()} |
         {restart_all, boolean()} |
         {restart_delay,
          list({time_exponential_min, restart_delay_milliseconds()} |
               {time_exponential_max, restart_delay_milliseconds()} |
               {time_linear_min, restart_delay_milliseconds()} |
               {time_linear_slope, restart_delay_milliseconds()} |
               {time_linear_max, restart_delay_milliseconds()} |
               {time_absolute, restart_delay_milliseconds()}) | false} |
         {scope, atom()} |
         {monkey_latency,
          list({time_uniform_min, latency_min_time_milliseconds()} |
               {time_uniform_max, latency_max_time_milliseconds()} |
               {time_gaussian_mean, latency_mean_time_milliseconds()} |
               {time_gaussian_stddev, float() | pos_integer()} |
               {time_absolute, latency_time_milliseconds()}) | system | false} |
         {monkey_chaos,
          list({probability_request, float()} |
               {probability_day, float()}) | system | false} |
         {automatic_loading, boolean()} |
         {dispatcher_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {aspects_init_after, list(aspect_init_after_internal())} |
         {aspects_request_before, list(aspect_request_before_internal())} |
         {aspects_request_after, list(aspect_request_after_internal())} |
         {aspects_info_before, list(aspect_info_before_internal())} |
         {aspects_info_after, list(aspect_info_after_internal())} |
         {aspects_terminate_before, list(aspect_terminate_before_internal())} |
         {application_name, undefined | atom()} |
         {init_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {request_pid_uses, infinity | pos_integer()} |
         {request_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {info_pid_uses, infinity | pos_integer()} |
         {info_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {duo_mode, boolean()} |
         {hibernate,
          list({period, period_seconds()} |
               {rate_request_min, number()}) | boolean()} |
         {reload, boolean()}).
-type service_options_external() ::
    list({priority_default, ?PRIORITY_HIGH..?PRIORITY_LOW} |
         {queue_limit, undefined | non_neg_integer()} |
         {queue_size, undefined | pos_integer()} |
         {rate_request_max,
          list({period, period_seconds()} |
               {value, number()}) | number() | undefined} |
         {dest_refresh_start, dest_refresh_delay_milliseconds()} |
         {dest_refresh_delay, dest_refresh_delay_milliseconds()} |
         {request_name_lookup, sync | async} |
         {request_timeout_adjustment, boolean()} |
         {request_timeout_immediate_max,
          request_timeout_immediate_max_milliseconds()} |
         {response_timeout_adjustment, boolean()} |
         {response_timeout_immediate_max,
          response_timeout_immediate_max_milliseconds()} |
         {count_process_dynamic,
          list({period, period_seconds()} |
               {rate_request_max, number()} |
               {rate_request_min, number()} |
               {count_max, number()} |
               {count_min, number()}) | false} |
         {timeout_terminate,
          undefined | timeout_terminate_milliseconds()} |
         {restart_all, boolean()} |
         {restart_delay,
          list({time_exponential_min, restart_delay_milliseconds()} |
               {time_exponential_max, restart_delay_milliseconds()} |
               {time_linear_min, restart_delay_milliseconds()} |
               {time_linear_slope, restart_delay_milliseconds()} |
               {time_linear_max, restart_delay_milliseconds()} |
               {time_absolute, restart_delay_milliseconds()}) | false} |
         {scope, atom()} |
         {monkey_latency,
          list({time_uniform_min, latency_min_time_milliseconds()} |
               {time_uniform_max, latency_max_time_milliseconds()} |
               {time_gaussian_mean, latency_mean_time_milliseconds()} |
               {time_gaussian_stddev, float() | pos_integer()} |
               {time_absolute, latency_time_milliseconds()}) | system | false} |
         {monkey_chaos,
          list({probability_request, float()} |
               {probability_day, float()}) | system | false} |
         {automatic_loading, boolean()} |
         {dispatcher_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {aspects_init_after, list(aspect_init_after_external())} |
         {aspects_request_before, list(aspect_request_before_external())} |
         {aspects_request_after, list(aspect_request_after_external())} |
         {aspects_terminate_before, list(aspect_terminate_before_external())} |
         {limit, limit_external()} |
         {owner, owner_external()} |
         {nice, nice_external()} |
         {cgroup, cgroup_external()} |
         {chroot, chroot_external()} |
         {directory, directory_external()}).
-export_type([service_options_internal/0,
              service_options_external/0]).

-type service_id() :: <<_:128>>. % version 1 UUID (service instance id)
-type service_internal() :: #internal{}.
-type service_external() :: #external{}.
-type service_proplist() ::
    nonempty_list({type, internal | external} |
                  {prefix, cloudi:service_name_pattern()} |
                  {module, atom() | file:filename()} |
                  {file_path, file:filename()} |
                  {args, list()} |
                  {env, list({string(), string()})} |
                  {dest_refresh, dest_refresh()} |
                  {protocol, 'default' | 'local' | 'tcp' | 'udp'} |
                  {buffer_size, 'default' | pos_integer()} |
                  {timeout_init, timeout_initialize_value_milliseconds()} |
                  {timeout_async, timeout_send_async_value_milliseconds()} |
                  {timeout_sync, timeout_send_sync_value_milliseconds()} |
                  {dest_list_deny, dest_list()} |
                  {dest_list_allow, dest_list()} |
                  {count_process, pos_integer() | float()} |
                  {count_thread, pos_integer() | float()} |
                  {max_r, non_neg_integer()} |
                  {max_t, seconds()} |
                  {options, service_options_internal() |
                            service_options_external()}).
-type service() :: #internal{} | #external{}.
-type service_status_internal() ::
    nonempty_list({type, internal} |
                  {prefix, cloudi:service_name_pattern()} |
                  {module, atom()} |
                  {count_process, pos_integer()} |
                  {suspended, boolean()} |
                  {uptime_total, nonempty_string()} |
                  {uptime_running, nonempty_string()} |
                  {uptime_processing, nonempty_string()} |
                  {uptime_restarts, nonempty_string()} |
                  {downtime_day_restarting, nonempty_string()} |
                  {downtime_week_restarting, nonempty_string()} |
                  {downtime_month_restarting, nonempty_string()} |
                  {downtime_year_restarting, nonempty_string()} |
                  {interrupt_day_updating, nonempty_string()} |
                  {interrupt_week_updating, nonempty_string()} |
                  {interrupt_month_updating, nonempty_string()} |
                  {interrupt_year_updating, nonempty_string()} |
                  {interrupt_day_suspended, nonempty_string()} |
                  {interrupt_week_suspended, nonempty_string()} |
                  {interrupt_month_suspended, nonempty_string()} |
                  {interrupt_year_suspended, nonempty_string()} |
                  {availability_day_total, nonempty_string()} |
                  {availability_day_running, nonempty_string()} |
                  {availability_day_updated, nonempty_string()} |
                  {availability_day_processing, nonempty_string()} |
                  {availability_week_total, nonempty_string()} |
                  {availability_week_running, nonempty_string()} |
                  {availability_week_updated, nonempty_string()} |
                  {availability_week_processing, nonempty_string()} |
                  {availability_month_total, nonempty_string()} |
                  {availability_month_running, nonempty_string()} |
                  {availability_month_updated, nonempty_string()} |
                  {availability_month_processing, nonempty_string()} |
                  {availability_year_total, nonempty_string()} |
                  {availability_year_running, nonempty_string()} |
                  {availability_year_updated, nonempty_string()} |
                  {availability_year_processing, nonempty_string()}).
-type service_status_external() ::
    nonempty_list({type, external} |
                  {prefix, cloudi:service_name_pattern()} |
                  {file_path, file:filename()} |
                  {count_process, pos_integer()} |
                  {count_thread, pos_integer()} |
                  {suspended, boolean()} |
                  {uptime_total, nonempty_string()} |
                  {uptime_running, nonempty_string()} |
                  {uptime_processing, nonempty_string()} |
                  {uptime_restarts, nonempty_string()} |
                  {downtime_day_restarting, nonempty_string()} |
                  {downtime_week_restarting, nonempty_string()} |
                  {downtime_month_restarting, nonempty_string()} |
                  {downtime_year_restarting, nonempty_string()} |
                  {interrupt_day_updating, nonempty_string()} |
                  {interrupt_week_updating, nonempty_string()} |
                  {interrupt_month_updating, nonempty_string()} |
                  {interrupt_year_updating, nonempty_string()} |
                  {interrupt_day_suspended, nonempty_string()} |
                  {interrupt_week_suspended, nonempty_string()} |
                  {interrupt_month_suspended, nonempty_string()} |
                  {interrupt_year_suspended, nonempty_string()} |
                  {availability_day_total, nonempty_string()} |
                  {availability_day_running, nonempty_string()} |
                  {availability_day_updated, nonempty_string()} |
                  {availability_day_processing, nonempty_string()} |
                  {availability_week_total, nonempty_string()} |
                  {availability_week_running, nonempty_string()} |
                  {availability_week_updated, nonempty_string()} |
                  {availability_week_processing, nonempty_string()} |
                  {availability_month_total, nonempty_string()} |
                  {availability_month_running, nonempty_string()} |
                  {availability_month_updated, nonempty_string()} |
                  {availability_month_processing, nonempty_string()} |
                  {availability_year_total, nonempty_string()} |
                  {availability_year_running, nonempty_string()} |
                  {availability_year_updated, nonempty_string()} |
                  {availability_year_processing, nonempty_string()}).
-type service_status() ::
    service_status_internal() | service_status_external().
-export_type([service_id/0,
              service_internal/0,
              service_external/0,
              service_proplist/0,
              service/0,
              service_status_internal/0,
              service_status_external/0,
              service_status/0]).

-type module_version() :: list(any()).
-type module_state_internal_f() ::
    fun((ModuleVersionOld :: module_version(),
         ModuleVersionNew :: module_version(),
         StateOld :: any()) ->
        {ok, StateNew :: any()} |
        {error, Reason :: any()}).
-type module_state_internal() ::
    module_state_internal_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type service_update_plan_internal() ::
    nonempty_list({type, internal} |
                  {module, atom()} |
                  {module_state, module_state_internal()} |
                  {sync, boolean()} |
                  {modules_load, list(atom())} |
                  {modules_unload, list(atom())} |
                  {code_paths_add, list(string())} |
                  {code_paths_remove, list(string())} |
                  {dest_refresh, dest_refresh()} |
                  {timeout_init, timeout_initialize_milliseconds()} |
                  {timeout_async, timeout_send_async_milliseconds()} |
                  {timeout_sync, timeout_send_sync_milliseconds()} |
                  {dest_list_deny, dest_list()} |
                  {dest_list_allow, dest_list()} |
                  {options, service_update_plan_options_internal()}).
-type service_update_plan_external() ::
    nonempty_list({type, external} |
                  {file_path, file:filename()} |
                  {args, string()} |
                  {env, list({string(), string()})} |
                  {sync, boolean()} |
                  {modules_load, list(atom())} |
                  {modules_unload, list(atom())} |
                  {code_paths_add, list(string())} |
                  {code_paths_remove, list(string())} |
                  {dest_refresh, dest_refresh()} |
                  {timeout_init, timeout_initialize_milliseconds()} |
                  {timeout_async, timeout_send_async_milliseconds()} |
                  {timeout_sync, timeout_send_sync_milliseconds()} |
                  {dest_list_deny, dest_list()} |
                  {dest_list_allow, dest_list()} |
                  {options, service_update_plan_options_external()}).
-type service_update_plan_options_internal() ::
    list({priority_default, priority()} |
         {queue_limit, undefined | non_neg_integer()} |
         {queue_size, undefined | pos_integer()} |
         {rate_request_max,
          list({period, period_seconds()} |
               {value, number()}) | number() | undefined} |
         {dest_refresh_start, dest_refresh_delay_milliseconds()} |
         {dest_refresh_delay, dest_refresh_delay_milliseconds()} |
         {request_name_lookup, sync | async} |
         {request_timeout_adjustment, boolean()} |
         {request_timeout_immediate_max,
          request_timeout_immediate_max_milliseconds()} |
         {response_timeout_adjustment, boolean()} |
         {response_timeout_immediate_max,
          response_timeout_immediate_max_milliseconds()} |
         {monkey_latency,
          list({time_uniform_min, latency_min_time_milliseconds()} |
               {time_uniform_max, latency_max_time_milliseconds()} |
               {time_gaussian_mean, latency_mean_time_milliseconds()} |
               {time_gaussian_stddev, float() | pos_integer()} |
               {time_absolute, latency_time_milliseconds()}) | system | false} |
         {monkey_chaos,
          list({probability_request, float()} |
               {probability_day, float()}) | system | false} |
         {dispatcher_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {aspects_init_after, list(aspect_init_after_internal())} |
         {aspects_request_before, list(aspect_request_before_internal())} |
         {aspects_request_after, list(aspect_request_after_internal())} |
         {aspects_info_before, list(aspect_info_before_internal())} |
         {aspects_info_after, list(aspect_info_after_internal())} |
         {aspects_terminate_before, list(aspect_terminate_before_internal())} |
         {init_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {request_pid_uses, infinity | pos_integer()} |
         {request_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {info_pid_uses, infinity | pos_integer()} |
         {info_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {hibernate,
          list({period, period_seconds()} |
               {rate_request_min, number()}) | boolean()} |
         {reload, boolean()}).
-type service_update_plan_options_external() ::
    list({priority_default, ?PRIORITY_HIGH..?PRIORITY_LOW} |
         {queue_limit, undefined | non_neg_integer()} |
         {queue_size, undefined | pos_integer()} |
         {rate_request_max,
          list({period, period_seconds()} |
               {value, number()}) | number() | undefined} |
         {dest_refresh_start, dest_refresh_delay_milliseconds()} |
         {dest_refresh_delay, dest_refresh_delay_milliseconds()} |
         {request_name_lookup, sync | async} |
         {request_timeout_adjustment, boolean()} |
         {request_timeout_immediate_max,
          request_timeout_immediate_max_milliseconds()} |
         {response_timeout_adjustment, boolean()} |
         {response_timeout_immediate_max,
          response_timeout_immediate_max_milliseconds()} |
         {monkey_latency,
          list({time_uniform_min, latency_min_time_milliseconds()} |
               {time_uniform_max, latency_max_time_milliseconds()} |
               {time_gaussian_mean, latency_mean_time_milliseconds()} |
               {time_gaussian_stddev, float() | pos_integer()} |
               {time_absolute, latency_time_milliseconds()}) | system | false} |
         {monkey_chaos,
          list({probability_request, float()} |
               {probability_day, float()}) | system | false} |
         {dispatcher_pid_options,
          list({priority, low | normal | high} |
               {fullsweep_after, non_neg_integer()} |
               {min_heap_size, non_neg_integer()} |
               {min_bin_vheap_size, non_neg_integer()} |
               {max_heap_size, max_heap_size_options()} |
               {sensitive, boolean()} |
               {message_queue_data, off_heap | on_heap | mixed})} |
         {aspects_init_after, list(aspect_init_after_external())} |
         {aspects_request_before, list(aspect_request_before_external())} |
         {aspects_request_after, list(aspect_request_after_external())} |
         {aspects_terminate_before, list(aspect_terminate_before_external())} |
         {limit, limit_external()}).
-type service_update_plan() ::
    service_update_plan_internal() |
    service_update_plan_external().
-export_type([module_version/0,
              module_state_internal_f/0,
              module_state_internal/0,
              service_update_plan/0]).

-type node_reconnect_delay_seconds() ::
    period_seconds().
-export_type([node_reconnect_delay_seconds/0]).
-type nodes_properties() ::
    node() |
    {nodes, list(node())} |
    {reconnect_start, node_reconnect_delay_seconds()} |
    {reconnect_delay, node_reconnect_delay_seconds()} |
    {listen, visible | all} |
    {connect, visible | hidden} |
    {timestamp_type, erlang | os | warp} |
    {discovery,
     list({ec2, list({address, inet:ip_address()} |
                     {port, inet:port_number()} |
                     {ttl, non_neg_integer()})} |
          {multicast, list({access_key_id, string()} |
                           {secret_access_key, string()} |
                           {ec2_host, string()} |
                           {groups, list(string())} |
                           {tags, list({string(), string()} |
                                       string())})})} |
    {cost, list({node() | default, float()})} |
    {cost_precision, 0..253} |
    {log_reconnect, loglevel()}.
-type nodes_proplist() ::
    list(nodes_properties()).
-type nodes_set_proplist() ::
    nonempty_list({set, all | local} |
                  nodes_properties()).
-type node_status() ::
    nonempty_list(% local node
                  {uptime, nonempty_string()} |
                  {uptime_cost_total, nonempty_string()} |
                  {uptime_cost_day, nonempty_string()} |
                  {uptime_cost_week, nonempty_string()} |
                  {uptime_cost_month, nonempty_string()} |
                  {uptime_cost_year, nonempty_string()} |
                  % remote node
                  {tracked, nonempty_string()} |
                  {tracked_cost_total, nonempty_string()} |
                  {tracked_cost_day, nonempty_string()} |
                  {tracked_cost_week, nonempty_string()} |
                  {tracked_cost_month, nonempty_string()} |
                  {tracked_cost_year, nonempty_string()} |
                  {connection, visible | hidden} |
                  {tracked_disconnects, nonempty_string()} |
                  {disconnected, boolean()} |
                  {downtime_day_disconnected, nonempty_string()} |
                  {downtime_week_disconnected, nonempty_string()} |
                  {downtime_month_disconnected, nonempty_string()} |
                  {downtime_year_disconnected, nonempty_string()} |
                  % all nodes
                  {availability_day, nonempty_string()} |
                  {availability_week, nonempty_string()} |
                  {availability_month, nonempty_string()} |
                  {availability_year, nonempty_string()}).
-export_type([nodes_proplist/0,
              nodes_set_proplist/0,
              node_status/0]).

-type aspect_log_f() ::
    fun((Level :: loglevel_on(),
         Timestamp :: erlang:timestamp(),
         Node :: node(),
         Pid :: pid(),
         Module :: module(),
         Line :: pos_integer(),
         Function :: atom() | undefined,
         Arity :: arity() | undefined,
         MetaData :: list({atom(), any()}),
         LogMessage :: iodata()) ->
        ok).
-type aspect_log_before() ::
    aspect_log_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-type aspect_log_after() ::
    aspect_log_f() |
    {Module :: module(), Function :: atom()} |
    {{Module :: module(), Function :: atom()}}.
-export_type([aspect_log_f/0,
              aspect_log_before/0,
              aspect_log_after/0]).
-type loglevel() :: loglevel_on() | off.
-type loglevel_on() :: fatal | error | warn | info | debug | trace.
-type logging_syslog_identity() :: nonempty_string().
-type logging_syslog_facility() ::
    kernel | user | mail | daemon | auth0 | syslog |
    print | news | uucp | clock0 | auth1 | ftp | ntp |
    auth2 | auth3 | clock1 | local0 | local1 | local2 |
    local3 | local4 | local5 | local6 | local7 | non_neg_integer() |
    % common aliases
    auth | authpriv | cron | kern | lpr | security.
-type logging_syslog_transport() :: local | udp | tcp | tls.
-type logging_syslog_transport_options() :: list().
-type logging_syslog_protocol() :: rfc3164 | rfc5424.
-type logging_syslog_path() :: nonempty_string().
-type logging_syslog_host() :: inet:ip_address() | inet:hostname().
-type logging_syslog_port() :: undefined | inet:port_number().
-type logging_syslog_set_proplist() ::
    list({identity, logging_syslog_identity()} |
         {facility, logging_syslog_facility()} |
         {level, loglevel() | undefined} |
         {transport, logging_syslog_transport()} |
         {transport_options, logging_syslog_transport_options()} |
         {protocol, logging_syslog_protocol()} |
         {path, logging_syslog_path()} |
         {host, logging_syslog_host()} |
         {port, logging_syslog_port()}).
-type logging_formatters_set_proplist() ::
    list({any | nonempty_list(module()),
          list(fatal | error | warn | info | debug | trace |
               emergency | alert | critical | warning | notice |
               {level, fatal | error | warn | info | debug | trace |
                       emergency | alert | critical | warning | notice} |
               {output, module() | undefined} |
               {output_args, list()} |
               {output_max_r, non_neg_integer()} |
               {output_max_t, cloudi_service_api:seconds()} |
               {formatter, module() | undefined} |
               {formatter_config, list()})}).
-type logging_proplist() ::
    nonempty_list({file, string() | undefined} |
                  {stdout, boolean()} |
                  {level, loglevel()} |
                  {redirect, node() | undefined} |
                  {syslog, logging_syslog_set_proplist() | undefined} |
                  {formatters, logging_formatters_set_proplist() | undefined} |
                  {log_time_offset, loglevel()} |
                  {aspects_log_before, list(aspect_log_before())} |
                  {aspects_log_after, list(aspect_log_after())}).
-export_type([loglevel/0,
              loglevel_on/0,
              logging_syslog_identity/0,
              logging_syslog_facility/0,
              logging_syslog_transport/0,
              logging_syslog_transport_options/0,
              logging_syslog_protocol/0,
              logging_syslog_path/0,
              logging_syslog_host/0,
              logging_syslog_port/0,
              logging_syslog_set_proplist/0,
              logging_formatters_set_proplist/0,
              logging_proplist/0]).

-type code_status() ::
    nonempty_list({build_machine, nonempty_string()} |
                  {build_kernel_version, nonempty_string()} |
                  {build_operating_system, nonempty_string()} |
                  {build_erlang_otp_release, nonempty_string()} |
                  {build_cloudi_time, nonempty_string()} |
                  {build_cloudi_cxx_compiler_version, nonempty_string()} |
                  {build_cloudi_cxx_dependencies_versions, nonempty_string()} |
                  {build_erts_c_compiler_version, nonempty_string()} |
                  {install_erlang_erts_time, nonempty_string()} |
                  {install_erlang_kernel_time, nonempty_string()} |
                  {install_erlang_stdlib_time, nonempty_string()} |
                  {install_erlang_sasl_time, nonempty_string()} |
                  {install_erlang_compiler_time, nonempty_string()} |
                  {install_cloudi_time, nonempty_string()} |
                  {runtime_erlang_erts_version, nonempty_string()} |
                  {runtime_erlang_kernel_version, nonempty_string()} |
                  {runtime_erlang_stdlib_version, nonempty_string()} |
                  {runtime_erlang_sasl_version, nonempty_string()} |
                  {runtime_erlang_compiler_version, nonempty_string()} |
                  {runtime_cloudi_version, nonempty_string()} |
                  {runtime_machine_processors, pos_integer()} |
                  {runtime_start, nonempty_string()} |
                  {runtime_clock, nonempty_string()} |
                  {runtime_clock_offset, nonempty_string()} |
                  {runtime_total, nonempty_string()} |
                  {runtime_cloudi_start, nonempty_string()} |
                  {runtime_cloudi_total, nonempty_string()} |
                  {runtime_cloudi_changes,
                   list(nonempty_list({type, internal | external} |
                                      {file_age, nonempty_string()} |
                                      {file_path, nonempty_string()} |
                                      {service_ids,
                                       nonempty_list(service_id())}))}).
-export_type([code_status/0]).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

% timeout for the functions below
-define(TIMEOUT_SERVICE_API_MIN, ?TIMEOUT_DELTA + 1).
-define(TIMEOUT_SERVICE_API_MAX, ?TIMEOUT_MAX_ERLANG).
-type api_timeout_milliseconds() ::
    ?TIMEOUT_SERVICE_API_MIN..?TIMEOUT_SERVICE_API_MAX | infinity.
-export_type([api_timeout_milliseconds/0]).

%%-------------------------------------------------------------------------
%% @doc
%% ===Add ACL entries.===
%% Add more ACL entries to be later used when starting services. An ACL
%% entry is an Erlang atom() -> list(atom() | string()) relationship which
%% provides a logical grouping of service name patterns
%% (e.g., {api, ["/cloudi/api/"]}). When providing a service name pattern
%% for an ACL entry, a non-pattern will be assumed to be a prefix
%% (i.e., "/cloudi/api/" == "/cloudi/api/*").
%% @end
%%-------------------------------------------------------------------------

-spec acl_add(L :: nonempty_list({atom(), acl()}),
              Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_acl_add()}.

acl_add([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:acl_add(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Remove ACL entries.===
%% Remove ACL entries that are no longer needed. Running services will
%% retain their configuration, so this impacts services that are started
%% in the future.
%% @end
%%-------------------------------------------------------------------------

-spec acl_remove(L :: nonempty_list(atom()),
                 Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_acl_remove()}.

acl_remove([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:acl_remove(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===List all ACL entries.===
%% @end
%%-------------------------------------------------------------------------

-spec acl(Timeout :: api_timeout_milliseconds()) ->
    {ok, list({atom(), list(cloudi_service:service_name_pattern())})} |
    {error, timeout | noproc}.

acl(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:acl(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a list of all service subscriptions.===
%% When a subscription on the same service name pattern occurred
%% multiple times, only a single entry is returned within the list.
%% Service name patterns that are subscriptions of non-service Erlang pids
%% (e.g., cloudi_service_http_cowboy1 websocket connection pids) will not
%% be returned by this function.
%% @end
%%-------------------------------------------------------------------------

-spec service_subscriptions(ServiceId :: binary() | string(),
                            Timeout :: api_timeout_milliseconds()) ->
    {ok, list(cloudi_service:service_name_pattern())} |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} | not_found}.

service_subscriptions(ServiceId, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case service_id_convert(ServiceId) of
        {ok, ServiceIdValid} ->
            cloudi_core_i_configurator:service_subscriptions(ServiceIdValid,
                                                             Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Add service instances.===
%% Provide service configuration using the same syntax found in the
%% configuration file (i.e., /usr/local/etc/cloudi/cloudi.conf).
%% @end
%%-------------------------------------------------------------------------

-spec services_add(L :: nonempty_list({internal,
                                       _, _, _, _, _, _, _, _, _, _, _, _, _} |
                                      {external,
                                       _, _, _, _, _, _, _, _, _, _, _, _, _,
                                       _, _, _, _} |
                                      service_proplist()),
                   Timeout :: api_timeout_milliseconds()) ->
    {ok, nonempty_list(service_id())} |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_services_add()}.

services_add([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:services_add(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Remove service instances.===
%% Provide the Service UUIDs for the services that should be stopped.
%% The Service UUID is shown in the output of services/1. When the
%% service is stopped, its running instance is removed from CloudI, but
%% does not impact any other running instances (even if they are the same
%% service module or binary).
%% @end
%%-------------------------------------------------------------------------

-spec services_remove(L :: nonempty_list(binary() | string()),
                      Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} |
     cloudi_core_i_configuration:error_reason_services_remove()}.

services_remove([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case service_ids_convert(L) of
        {ok, ServiceIdsValid} ->
            cloudi_core_i_configurator:services_remove(ServiceIdsValid,
                                                       Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Restart service instances.===
%% Provide the Service UUIDs for the services that should be restarted.
%% The Service UUID is shown in the output of services/1. When the service
%% is restarted, the old instance is stopped and a new instance is started.
%% During the restart delay, it is possible to lose queued service
%% requests and received asynchronous responses. Keeping the state
%% separate between the service instances is important to prevent failures
%% within the new instance.
%% @end
%%-------------------------------------------------------------------------

-spec services_restart(L :: nonempty_list(binary() | string()),
                       Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} |
     cloudi_core_i_configuration:error_reason_services_restart()}.

services_restart([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case service_ids_convert(L) of
        {ok, ServiceIdsValid} ->
            cloudi_core_i_configurator:services_restart(ServiceIdsValid,
                                                        Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Suspend service instances.===
%% Provide the Service UUIDs for the services that should be suspended.
%% The Service UUID is shown in the output of services/1.
%% @end
%%-------------------------------------------------------------------------

-spec services_suspend(L :: nonempty_list(binary() | string()),
                       Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} |
     cloudi_core_i_configuration:error_reason_services_suspend()}.

services_suspend([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case service_ids_convert(L) of
        {ok, ServiceIdsValid} ->
            cloudi_core_i_configurator:services_suspend(ServiceIdsValid,
                                                        Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Resume service instances.===
%% Provide the Service UUIDs for the services that should be resumed.
%% The Service UUID is shown in the output of services/1.
%% @end
%%-------------------------------------------------------------------------

-spec services_resume(L :: nonempty_list(binary() | string()),
                      Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} |
     cloudi_core_i_configuration:error_reason_services_resume()}.

services_resume([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case service_ids_convert(L) of
        {ok, ServiceIdsValid} ->
            cloudi_core_i_configurator:services_resume(ServiceIdsValid,
                                                       Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Search service instances for matches on the provided service name.===
%% Multiple services may be returned for a single service name.  Only service
%% instances on the local Erlang node are searched.  Service names that match
%% subscriptions of non-service Erlang pids only
%% (e.g., cloudi_service_http_cowboy1 websocket connection pids) will not
%% return the service's configuration with this function.  Provide a scope
%% within a 2 element tuple with the service name to check a custom scope.
%% @end
%%-------------------------------------------------------------------------

-spec services_search(Name :: {atom(), cloudi:service_name()} |
                              cloudi:service_name(),
                      Timeout :: api_timeout_milliseconds()) ->
    {ok, list({service_id(), service_internal()} |
              {service_id(), service_external()})} |
    {error,
     timeout | noproc |
     service_name_invalid |
     cloudi_core_i_configuration:error_reason_services_search()}.

services_search(Name, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    {Scope, ServiceName} = case Name of
        {ScopeValue, [_ | _] = ServiceNameValue} when is_atom(ScopeValue) ->
            {?SCOPE_ASSIGN(ScopeValue), ServiceNameValue};
        [_ | _] = ServiceNameValue ->
            {?SCOPE_DEFAULT, ServiceNameValue}
    end,
    try cloudi_x_trie:is_pattern2(ServiceName) of
        false ->
            cloudi_core_i_configurator:services_search(Scope, ServiceName,
                                                       Timeout);
        true ->
            {error, service_name_invalid}
    catch
        exit:badarg ->
            {error, service_name_invalid}
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===List the current status of specific services.===
%% @end
%%-------------------------------------------------------------------------

-spec services_status(L :: list(binary() | string()),
                      Timeout :: api_timeout_milliseconds()) ->
    {ok, nonempty_list({service_id(), service_status()})} |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} |
     {service_not_found, any()}}.

services_status(L, Timeout)
    when is_list(L),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    ServiceIdsResult = case service_ids_convert(L) of
        {ok, []} ->
            cloudi_core_i_configurator:service_ids(Timeout);
        ServiceIdsResultValue ->
            ServiceIdsResultValue
    end,
    case ServiceIdsResult of
        {ok, ServiceIdsValid} ->
            cloudi_core_i_services_monitor:status(ServiceIdsValid, Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Update service instances.===
%% Update service instances without losing service requests and other
%% service-specific data within the Erlang VM.
%% @end
%%-------------------------------------------------------------------------

-spec services_update(L :: nonempty_list({string() | binary(),
                                          service_update_plan()}),
                      Timeout :: api_timeout_milliseconds()) ->
    {ok, ServiceIdsSetsSuccess :: nonempty_list(nonempty_list(service_id()))} |
    {error,
     {ServiceIdsSetError :: nonempty_list(service_id()),
      Reason :: {service_internal_update_failed |
                 service_external_update_failed, any()}},
     ServiceIdsSetsSuccess :: nonempty_list(nonempty_list(service_id()))} |
    {error,
     timeout | noproc |
     {service_id_invalid, any()} |
     cloudi_core_i_configuration:error_reason_services_update()}.

services_update([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case service_ids_convert_update(L) of
        {ok, LNew} ->
            cloudi_core_i_configurator:services_update(LNew, Timeout);
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===List all service instances with each service's UUID.===
%% @end
%%-------------------------------------------------------------------------

-spec services(Timeout :: api_timeout_milliseconds()) ->
    {ok, list({service_id(), service_internal()} |
              {service_id(), service_external()})} |
    {error, timeout | noproc}.

services(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:services(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Set CloudI nodes configuration.===
%% @end
%%-------------------------------------------------------------------------

-spec nodes_set(L :: nodes_set_proplist(),
                Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_nodes_set()}.

nodes_set([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:nodes_set(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Get CloudI nodes configuration.===
%% @end
%%-------------------------------------------------------------------------

-spec nodes_get(Timeout :: api_timeout_milliseconds()) ->
    {ok, nodes_proplist()} |
    {error, timeout | noproc}.

nodes_get(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:nodes_get(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Add CloudI nodes.===
%% Explicitly add a CloudI node name, so that services between all other
%% CloudI nodes and the added nodes can send each other service requests.
%% @end
%%-------------------------------------------------------------------------

-spec nodes_add(L :: nonempty_list(node()),
                Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_nodes_add()}.

nodes_add([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:nodes_add(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Explicitly remove CloudI nodes.===
%% The node must be currently dead to be removed.
%% @end
%%-------------------------------------------------------------------------

-spec nodes_remove(L :: nonempty_list(node()),
                   Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_nodes_remove()}.

nodes_remove([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:nodes_remove(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===List all the CloudI nodes known to be connected.===
%% @end
%%-------------------------------------------------------------------------

-spec nodes_alive(Timeout :: api_timeout_milliseconds()) ->
    {ok, list(node())} |
    {error, timeout | noproc}.

nodes_alive(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_nodes:alive(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===List all the CloudI nodes that are disconnected but expected to reconnect.===
%% @end
%%-------------------------------------------------------------------------

-spec nodes_dead(Timeout :: api_timeout_milliseconds()) ->
    {ok, list(node())} |
    {error, timeout | noproc}.

nodes_dead(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_nodes:dead(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===List the current status of specific nodes.===
%% @end
%%-------------------------------------------------------------------------

-spec nodes_status(L :: list(node()),
                   Timeout :: api_timeout_milliseconds()) ->
    {ok, nonempty_list({node(), node_status()})} |
    {error,
     timeout | noproc |
     {node_not_found, any()}}.

nodes_status(L, Timeout)
    when is_list(L),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_nodes:status(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===List both the connected and disconnected CloudI nodes.===
%% @end
%%-------------------------------------------------------------------------

-spec nodes(Timeout :: api_timeout_milliseconds()) ->
    {ok, list(node())} |
    {error, timeout | noproc}.

nodes(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_nodes:nodes(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Set CloudI logging configuration.===
%% @end
%%-------------------------------------------------------------------------

-spec logging_set(L :: logging_proplist(),
                  Timeout :: api_timeout_milliseconds()) ->
    ok | {error, file:posix() | badarg | system_limit}.

logging_set([_ | _] = L, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_set(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Modify the current log file path.===
%% @end
%%-------------------------------------------------------------------------

-spec logging_file_set(FilePath :: string() | undefined,
                       Timeout :: api_timeout_milliseconds()) ->
    ok | {error, file:posix() | badarg | system_limit}.

logging_file_set(FilePath, Timeout)
    when ((FilePath =:= undefined) orelse
          (is_list(FilePath) andalso is_integer(hd(FilePath)))),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_file_set(FilePath, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Modify the current loglevel.===
%% CloudI uses asynchronous logging with flow control (backpressure
%% handling) to prevent misbehaving services from causing instability.
%% @end
%%-------------------------------------------------------------------------

-spec logging_level_set(Level :: loglevel() | undefined,
                        Timeout :: api_timeout_milliseconds()) ->
    ok.

logging_level_set(Level, Timeout)
    when ((Level =:= fatal) orelse (Level =:= error) orelse
          (Level =:= warn) orelse (Level =:= info) orelse
          (Level =:= debug) orelse (Level =:= trace) orelse
          (Level =:= off) orelse (Level =:= undefined)),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_level_set(Level, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Modify the current log stdout usage.===
%% @end
%%-------------------------------------------------------------------------

-spec logging_stdout_set(Stdout :: boolean(),
                         Timeout :: api_timeout_milliseconds()) ->
    ok.

logging_stdout_set(Stdout, Timeout)
    when is_boolean(Stdout),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_stdout_set(Stdout, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Set the CloudI syslog configuration.===
%% @end
%%-------------------------------------------------------------------------

-spec logging_syslog_set(L :: logging_syslog_set_proplist() |
                              undefined,
                         Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_logging_syslog_set()}.

logging_syslog_set(L, Timeout)
    when is_list(L) orelse (L =:= undefined),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_syslog_set(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Set the CloudI log formatters.===
%% lager backend (gen_event) modules are supported as 'output' modules and
%% lager formatter modules are supported with or without an 'output'
%% module specified.
%% @end
%%-------------------------------------------------------------------------

-spec logging_formatters_set(L :: logging_formatters_set_proplist() |
                                  undefined,
                             Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_logging_formatters_set()}.

logging_formatters_set(L, Timeout)
    when is_list(L) orelse (L =:= undefined),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_formatters_set(L, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Redirect the log output.===
%% Redirect all local log output to a remote CloudI node.
%% Use 'undefined' as the node name to log locally.
%% @end
%%-------------------------------------------------------------------------

-spec logging_redirect_set(Node :: undefined | node(),
                           Timeout :: api_timeout_milliseconds()) ->
    ok.

logging_redirect_set(Node, Timeout)
    when is_atom(Node),
         ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging_redirect_set(Node, Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Provide the current logging configuration.===
%% @end
%%-------------------------------------------------------------------------

-spec logging(Timeout :: api_timeout_milliseconds()) ->
    {ok, logging_proplist()} |
    {error, timeout | noproc}.

logging(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    cloudi_core_i_configurator:logging(Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Add a directory to the CloudI Erlang VM code server's search paths.===
%% The path is always appended to the list of search paths (you should not
%% need to rely on search path order because of unique naming).
%% @end
%%-------------------------------------------------------------------------

-spec code_path_add(Dir :: file:filename(),
                    Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error, bad_directory}.

code_path_add(Dir, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case code:add_pathz(Dir) of
        true ->
            ok;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Remove a directory from the CloudI Erlang VM code server's search paths.===
%% This doesn't impact any running services, only services that will be
%% started in the future.
%% @end
%%-------------------------------------------------------------------------

-spec code_path_remove(Dir :: file:filename(),
                       Timeout :: api_timeout_milliseconds()) ->
    ok |
    {error, does_not_exist | bad_name}.

code_path_remove(Dir, Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    case code:del_path(Dir) of
        true ->
            ok;
        false ->
            {error, does_not_exist};
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===List all the CloudI Erlang VM code server search paths.===
%% The order is the same order the directories are searched.
%% @end
%%-------------------------------------------------------------------------

-spec code_path(Timeout :: api_timeout_milliseconds()) ->
    {ok, nonempty_list(file:filename())}.

code_path(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    {ok, code:get_path()}.

%%-------------------------------------------------------------------------
%% @doc
%% ===Provide the current CloudI Erlang VM code status.===
%% Both build and runtime information is provided with the
%% service files changed after CloudI was started
%% (probably due to service updates).
%% @end
%%-------------------------------------------------------------------------

-spec code_status(Timeout :: api_timeout_milliseconds()) ->
    {ok, code_status()} |
    {error,
     timeout | noproc |
     cloudi_core_i_configuration:error_reason_code_status()}.

code_status(Timeout)
    when ((is_integer(Timeout) andalso
           (Timeout >= ?TIMEOUT_SERVICE_API_MIN) andalso
           (Timeout =< ?TIMEOUT_SERVICE_API_MAX)) orelse
          (Timeout =:= infinity)) ->
    TimeNative = cloudi_timestamp:native_monotonic(),
    TimeOffset = erlang:time_offset(),
    TimeOS = cloudi_timestamp:native_os(),
    TimeNativeStart = erlang:system_info(start_time),
    TimeNativeTotal = TimeNative - TimeNativeStart,
    TimeNativeNow = TimeNative + TimeOffset,
    case cloudi_core_i_configurator:code_status(TimeNative, TimeOffset,
                                                Timeout) of
        {ok, TimeNativeConfig, RuntimeChanges} ->
            MicroSecondsStart = cloudi_timestamp:
                                convert(TimeNativeStart + TimeOffset,
                                        native, microsecond),
            MicroSecondsNow = cloudi_timestamp:
                              convert(TimeNativeNow, native, microsecond),
            NanoSecondsOffset = cloudi_timestamp:
                                convert(TimeOS - TimeNativeNow,
                                        native, nanosecond),
            NanoSecondsTotal = cloudi_timestamp:
                               convert(TimeNativeTotal, native, nanosecond),
            MicroSecondsStartConfig = cloudi_timestamp:
                                      convert(TimeNativeConfig + TimeOffset,
                                              native, microsecond),
            NanoSecondsTotalConfig = cloudi_timestamp:
                                     convert(TimeNative - TimeNativeConfig,
                                             native, nanosecond),
            Status = cloudi_environment:status() ++
                [{runtime_start,
                  cloudi_timestamp:
                  microseconds_epoch_to_string(MicroSecondsStart)},
                 {runtime_clock,
                  cloudi_timestamp:
                  microseconds_epoch_to_string(MicroSecondsNow)},
                 {runtime_clock_offset,
                  cloudi_timestamp:
                  nanoseconds_to_string(NanoSecondsOffset, signed)},
                 {runtime_total,
                  cloudi_timestamp:
                  nanoseconds_to_string(NanoSecondsTotal)},
                 {runtime_cloudi_start,
                  cloudi_timestamp:
                  microseconds_epoch_to_string(MicroSecondsStartConfig)},
                 {runtime_cloudi_total,
                  cloudi_timestamp:
                  nanoseconds_to_string(NanoSecondsTotalConfig)},
                 {runtime_cloudi_changes,
                  RuntimeChanges}],
            {ok, Status};
        {error, _} = Error ->
            Error
    end.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

service_ids_convert_update(L) ->
    service_ids_convert_update(L, []).

service_ids_convert_update([], Output) ->
    {ok, lists:reverse(Output)};
service_ids_convert_update([{<<>>, _} = Entry | L], Output) ->
    service_ids_convert_update(L, [Entry | Output]);
service_ids_convert_update([{"", Plan} | L], Output) ->
    service_ids_convert_update(L, [{<<>>, Plan} | Output]);
service_ids_convert_update([{ServiceId, Plan} | L], Output) ->
    case service_id_convert(ServiceId) of
        {ok, ServiceIdValid} ->
            service_ids_convert_update(L, [{ServiceIdValid, Plan} | Output]);
        {error, _} = Error ->
            Error
    end;
service_ids_convert_update([Entry | _], _) ->
    {error, {update_invalid, Entry}}.

service_ids_convert(ServiceIds) ->
    service_ids_convert(ServiceIds, []).

service_ids_convert([], Output) ->
    {ok, lists:reverse(Output)};
service_ids_convert([ServiceId | ServiceIds], Output) ->
    case service_id_convert(ServiceId) of
        {ok, ServiceIdValid} ->
            service_ids_convert(ServiceIds, [ServiceIdValid | Output]);
        {error, _} = Error ->
            Error
    end.

service_id_convert(ServiceId)
    when is_binary(ServiceId), byte_size(ServiceId) == 16 ->
    {ok, ServiceId};
service_id_convert(ServiceId) ->
    try cloudi_x_uuid:string_to_uuid(ServiceId) of
        ServiceIdValid ->
            {ok, ServiceIdValid}
    catch
        exit:badarg ->
            {error, {service_id_invalid, ServiceId}}
    end.

