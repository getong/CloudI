%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et nomod:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI Service API Batch==
%%% A service that provides batch execution of CloudI services.
%%% @end
%%%
%%% MIT License
%%%
%%% Copyright (c) 2019 Michael Truog <mjtruog at protonmail dot com>
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
%%% @copyright 2019 Michael Truog
%%% @version 1.7.6 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_service_api_batch).
-author('mjtruog at protonmail dot com').

-behaviour(cloudi_service).

%% external interface
-export([services_add/4,
         services_add/5]).

%% cloudi_service callbacks
-export([cloudi_service_init/4,
         cloudi_service_handle_request/11,
         cloudi_service_handle_info/3,
         cloudi_service_terminate/3]).

-include_lib("cloudi_core/include/cloudi_logger.hrl").
-include_lib("cloudi_core/include/cloudi_service_api.hrl").

-define(DEFAULT_PURGE_ON_ERROR,              true).
        % Should the batch queue contents be purged when
        % a queue's currently running service fails
        % with an error and is unable to restart.

-define(NAME_BATCH, "batch").
-define(TIMEOUT_DELTA, 100). % milliseconds
-define(TERMINATE_INTERVAL, 500). % milliseconds

-record(queue,
    {
        count :: non_neg_integer(),
        data :: queue:queue(),
        service_id :: cloudi_service_api:service_id(),
        timeout_init = undefined
          :: undefined |
             cloudi_service_api:timeout_initialize_value_milliseconds(),
        terminate = false :: boolean(),
        terminate_timer = undefined :: undefined | reference()
    }).

-record(state,
    {
        purge_on_error :: boolean(),
        queues = cloudi_x_trie:new()
            :: cloudi_x_trie:cloudi_x_trie(), % queue name -> queue
        service :: cloudi_service:source()
    }).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

-type agent() :: cloudi:agent().
-type service_name() :: cloudi:service_name().
-type service_configurations() ::
    nonempty_list(cloudi_service_api:service_internal() |
                  cloudi_service_api:service_external() |
                  cloudi_service_api:service_proplist()).
-type timeout_milliseconds() :: cloudi:timeout_milliseconds().
-type module_response(Result) ::
    {{ok, Result}, NewAgent :: agent()} |
    {{error, cloudi:error_reason_sync()}, NewAgent :: agent()}.

-spec services_add(Agent :: agent(),
                   Prefix :: service_name(),
                   QueueName :: nonempty_string(),
                   Configs :: service_configurations()) ->
    module_response(CountQueued :: non_neg_integer()).

services_add(Agent, Prefix, [I | _] = QueueName, [_ | _] = Configs)
    when is_integer(I) ->
    cloudi:send_sync(Agent, Prefix ++ ?NAME_BATCH,
                     {services_add, QueueName, Configs}).

-spec services_add(Agent :: agent(),
                   Prefix :: service_name(),
                   QueueName :: nonempty_string(),
                   Configs :: service_configurations(),
                   Timeout :: timeout_milliseconds()) ->
    module_response(CountQueued :: non_neg_integer()).

services_add(Agent, Prefix, [I | _] = QueueName, [_ | _] = Configs, Timeout)
    when is_integer(I) ->
    cloudi:send_sync(Agent, Prefix ++ ?NAME_BATCH,
                     {services_add, QueueName, Configs}, Timeout).

%%%------------------------------------------------------------------------
%%% Callback functions from cloudi_service
%%%------------------------------------------------------------------------

cloudi_service_init(Args, Prefix, _Timeout, Dispatcher) ->
    Defaults = [
        {purge_on_error,               ?DEFAULT_PURGE_ON_ERROR}],
    [PurgeOnError] = cloudi_proplists:take_values(Defaults, Args),
    true = is_boolean(PurgeOnError),
    false = cloudi_service_name:pattern(Prefix),
    1 = cloudi_service:process_count_max(Dispatcher),
    cloudi_service:subscribe(Dispatcher, ?NAME_BATCH),
    Service = cloudi_service:self(Dispatcher),
    {ok, #state{purge_on_error = PurgeOnError,
                service = Service}}.

cloudi_service_handle_request(_Type, _Name, _Pattern, _RequestInfo, Request,
                              _Timeout, _Priority, _TransId, _Pid,
                              State, _Dispatcher) ->
    case Request of
        {services_add, QueueName, Configs} ->
            queue_add(QueueName, Configs, State)
    end.

cloudi_service_handle_info({aspects_init_after, QueueName, TimeoutInit},
                           State, _Dispatcher) ->
    {noreply, running_init(QueueName, TimeoutInit, State)};
cloudi_service_handle_info({aspects_terminate_before,
                            QueueName, Reason, TimeoutTerminate},
                           State, _Dispatcher) ->
    {noreply, running_terminate(QueueName, Reason, TimeoutTerminate, State)};
cloudi_service_handle_info({terminate, QueueName, Reason, Timeout},
                           State, _Dispatcher) ->
    {noreply, running_stopping(QueueName, Reason, Timeout, State)};
cloudi_service_handle_info({terminated, QueueName, Reason},
                           #state{purge_on_error = PurgeOnError} = State,
                           _Dispatcher) ->
    PurgeQueue = if
        PurgeOnError =:= true ->
            case Reason of
                {shutdown, _} ->
                    false;
                shutdown ->
                    false;
                _ ->
                    true
            end;
        PurgeOnError =:= false ->
            false
    end,
    {noreply, running_stopped(PurgeQueue, QueueName, State)}.

cloudi_service_terminate(_Reason, _Timeout, _State) ->
    ok.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

queue_add(QueueName, [Config | ConfigsTail] = Configs,
          #state{queues = Queues,
                 service = Service} = State) ->
    QueueNew = case cloudi_x_trie:find(QueueName, Queues) of
        {ok, #queue{count = Count,
                    data = Data} = Queue} ->
            DataNew = queue:join(Data, queue:from_list(Configs)),
            Queue#queue{count = Count + length(Configs),
                        data = DataNew};
        error ->
            Data = queue:from_list(ConfigsTail),
            ServiceId = service_add(Config, QueueName, Service),
            #queue{count = length(ConfigsTail),
                   data = Data,
                   service_id = ServiceId}
    end,
    #queue{count = CountNew} = QueueNew,
    {reply, CountNew,
     State#state{queues = cloudi_x_trie:store(QueueName, QueueNew, Queues)}}.

running_init(QueueName, TimeoutInit,
             #state{queues = Queues} = State) ->
    Queue = cloudi_x_trie:fetch(QueueName, Queues),
    #queue{terminate_timer = TerminateTimer} = Queue,
    if
        is_reference(TerminateTimer) ->
            erlang:cancel_timer(TerminateTimer);
        TerminateTimer =:= undefined ->
            ok
    end,
    QueueNew = Queue#queue{timeout_init = TimeoutInit,
                           terminate = false,
                           terminate_timer = undefined},
    State#state{queues = cloudi_x_trie:store(QueueName, QueueNew, Queues)}.

running_terminate(QueueName, Reason, TimeoutTerminate,
                  #state{queues = Queues,
                         service = Service} = State) ->
    case cloudi_x_trie:fetch(QueueName, Queues) of
        #queue{terminate = true} ->
            State;
        #queue{timeout_init = TimeoutInit,
               terminate = false} = Queue ->
            Timeout = TimeoutTerminate + TimeoutInit + ?TIMEOUT_DELTA,
            TimeoutNew = Timeout - ?TERMINATE_INTERVAL,
            TerminateTimer = if
                TimeoutNew > 0 ->
                    erlang:send_after(Timeout, Service,
                                      {terminate, QueueName, Reason,
                                       TimeoutNew});
                true ->
                    erlang:send_after(Timeout, Service,
                                      {terminated, QueueName, Reason})
            end,
            QueueNew = Queue#queue{terminate = true,
                                   terminate_timer = TerminateTimer},
            State#state{queues = cloudi_x_trie:store(QueueName,
                                                     QueueNew, Queues)}
    end.

running_stopping(QueueName, Reason, Timeout,
                 #state{queues = Queues,
                        service = Service} = State) ->
    Queue = cloudi_x_trie:fetch(QueueName, Queues),
    #queue{service_id = ServiceId} = Queue,
    case cloudi_service_api:service_subscriptions(ServiceId, infinity) of
        {error, not_found} ->
            Service ! {terminated, QueueName, Reason},
            QueueNew = Queue#queue{terminate = true,
                                   terminate_timer = undefined},
            State#state{queues = cloudi_x_trie:store(QueueName,
                                                     QueueNew, Queues)};
        _ ->
            TimeoutNew = Timeout - ?TERMINATE_INTERVAL,
            TerminateTimer = if
                TimeoutNew > 0 ->
                    erlang:send_after(Timeout, Service,
                                      {terminate, QueueName, Reason,
                                       TimeoutNew});
                true ->
                    erlang:send_after(Timeout, Service,
                                      {terminated, QueueName, Reason})
            end,
            QueueNew = Queue#queue{terminate_timer = TerminateTimer},
            State#state{queues = cloudi_x_trie:store(QueueName,
                                                     QueueNew, Queues)}
    end.

running_stopped(true, QueueName,
                #state{queues = Queues} = State) ->
    #queue{terminate = Terminate} = cloudi_x_trie:fetch(QueueName, Queues),
    QueuesNew = if
        Terminate =:= true ->
            cloudi_x_trie:erase(QueueName, Queues);
        Terminate =:= false ->
            % terminate_timer was cancelled after the message was queued
            Queues
    end,
    State#state{queues = QueuesNew};
running_stopped(false, QueueName,
                #state{queues = Queues,
                       service = Service} = State) ->
    QueuesNew = case cloudi_x_trie:fetch(QueueName, Queues) of
        #queue{terminate = false} ->
            % terminate_timer was cancelled after the message was queued
            Queues;
        #queue{count = 0} ->
            cloudi_x_trie:erase(QueueName, Queues);
        #queue{count = Count,
               data = Data} = Queue ->
            {{value, Config}, DataNew} = queue:out(Data),
            ServiceId = service_add(Config, QueueName, Service),
            cloudi_x_trie:store(QueueName,
                                Queue#queue{count = Count - 1,
                                            data = DataNew,
                                            service_id = ServiceId,
                                            terminate = false,
                                            terminate_timer = undefined},
                                Queues)
    end,
    State#state{queues = QueuesNew}.

service_add(Config, QueueName, Service) ->
    ConfigBatch = service_add_config(Config, QueueName, Service),
    case cloudi_service_api:services_add([ConfigBatch], infinity) of
        {ok, [ServiceId]} ->
            ServiceId;
        {error, _} = Error ->
            erlang:exit({services_add, Error})
    end.

service_add_config(#internal{options = Options} = ServiceConfig,
                   QueueName, Service) ->
    ServiceConfig#internal{options = add_options(internal, Options,
                                                 QueueName, Service)};
service_add_config(#external{options = Options} = ServiceConfig,
                   QueueName, Service) ->
    ServiceConfig#external{options = add_options(external, Options,
                                                 QueueName, Service)};
service_add_config([_ | _] = ServiceConfig, QueueName, Service) ->
    Type = case lists:keyfind(module, 1, ServiceConfig) of
        {_, _} ->
            internal;
        false ->
            external
    end,
    case lists:keytake(options, 1, ServiceConfig) of
        {value, {_, Options}, NextServiceConfig} ->
            [{options, add_options(Type, Options, QueueName, Service)} |
             NextServiceConfig];
        false ->
            [{options, add_options(Type, [], QueueName, Service)} |
             ServiceConfig]
    end.

add_options(internal = Type, Options0, QueueName, Service) ->
    OptionsN = add_option(Type, aspects_init_after,
                          Options0, QueueName, Service),
    add_option(Type, aspects_terminate_before,
               OptionsN, QueueName, Service);
add_options(external = Type, Options0, QueueName, Service) ->
    OptionsN = add_option(Type, aspects_init_after,
                          Options0, QueueName, Service),
    add_option(Type, aspects_terminate_before,
               OptionsN, QueueName, Service).

add_option(Type, Option, Options, QueueName, Service) ->
    Aspect = if
        Option =:= aspects_init_after ->
            if
                Type =:= internal ->
                    fun(_Args, _Prefix, Timeout, State, _Dispatcher) ->
                        Service ! {Option, QueueName, Timeout},
                        {ok, State}
                    end;
                Type =:= external ->
                    fun(_CommandLine, _Prefix, Timeout, State) ->
                        Service ! {Option, QueueName, Timeout},
                        {ok, State}
                    end
            end;
        Option =:= aspects_terminate_before ->
            fun(Reason, Timeout, State) ->
                Service ! {Option, QueueName, Reason, Timeout},
                {ok, State}
            end
    end,
    case lists:keytake(Option, 1, Options) of
        {value, {_, OptionL}, NextOptions} ->
            [{Option, OptionL ++ [Aspect]} | NextOptions];
        false ->
            [{Option, [Aspect]} | Options]
    end.
