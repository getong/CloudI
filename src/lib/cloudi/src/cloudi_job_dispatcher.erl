%%% -*- coding: utf-8; Mode: erlang; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*-
%%% ex: set softtabstop=4 tabstop=4 shiftwidth=4 expandtab fileencoding=utf-8:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==Cloudi Job Dispatcher==
%%% Parent process for each cloudi_job behaviour process.
%%% @end
%%%
%%% BSD LICENSE
%%% 
%%% Copyright (c) 2011, Michael Truog <mjtruog at gmail dot com>
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%% 
%%%     * Redistributions of source code must retain the above copyright
%%%       notice, this list of conditions and the following disclaimer.
%%%     * Redistributions in binary form must reproduce the above copyright
%%%       notice, this list of conditions and the following disclaimer in
%%%       the documentation and/or other materials provided with the
%%%       distribution.
%%%     * All advertising materials mentioning features or use of this
%%%       software must display the following acknowledgment:
%%%         This product includes software developed by Michael Truog
%%%     * The name of the author may not be used to endorse or promote
%%%       products derived from this software without specific prior
%%%       written permission
%%% 
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
%%% CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
%%% INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
%%% OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
%%% CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
%%% NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
%%% DAMAGE.
%%%
%%% @author Michael Truog <mjtruog [at] gmail (dot) com>
%%% @copyright 2011 Michael Truog
%%% @version 0.1.0 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_job_dispatcher).
-author('mjtruog [at] gmail (dot) com').

-behaviour(gen_server).

%% external interface
-export([start_link/9]).

%% gen_server callbacks
-export([init/1,
         handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("cloudi_logger.hrl").
-include("cloudi_constants.hrl").

-record(state,
    {
        job,             % job pid
        prefix,          % subscribe/unsubscribe name prefix
        timeout_async,   % default timeout for send_async
        timeout_sync,    % default timeout for send_sync
        send_timeouts = dict:new(),    % tracking for timeouts
        async_responses = dict:new(),  % tracking for async messages
        uuid_generator,  % transaction id generator
        dest_refresh,    % immediate_closest |
                         % lazy_closest |
                         % immediate_random |
                         % lazy_random, destination pid refresh
        list_pg_data = list_pg_data:get_empty_groups(), % dest_refresh lazy
        dest_deny,       % is the socket denied from sending to a destination
        dest_allow       % is the socket allowed to send to a destination
    }).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

start_link(Module, Args, Timeout, Prefix,
           TimeoutAsync, TimeoutSync, DestRefresh, DestDeny, DestAllow)
    when is_atom(Module), is_list(Args), is_integer(Timeout), is_list(Prefix),
         is_integer(TimeoutAsync), is_integer(TimeoutSync) ->
    true = (DestRefresh == immediate_closest) or
           (DestRefresh == lazy_closest) or
           (DestRefresh == immediate_random) or
           (DestRefresh == lazy_random),
    gen_server:start_link(?MODULE, [Module, Args, Timeout, Prefix, TimeoutAsync,
                                    TimeoutSync, DestRefresh,
                                    DestDeny, DestAllow], []).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

init([Module, Args, Timeout, Prefix, TimeoutAsync, TimeoutSync,
      DestRefresh, DestDeny, DestAllow]) ->
    case cloudi_job:start_link(Module, Args, Timeout) of
        {ok, Job} ->
            destination_refresh_start(DestRefresh),
            {ok, #state{job = Job,
                        prefix = Prefix,
                        timeout_async = TimeoutAsync,
                        timeout_sync = TimeoutSync,
                        uuid_generator = uuid:new(Job),
                        dest_refresh = DestRefresh,
                        dest_deny = DestDeny,
                        dest_allow = DestAllow}};
        ignore ->
            ignore;
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call({'send_async', Name, Request}, Client,
            #state{timeout_async = TimeoutAsync} = State) ->
    handle_call({'send_async', Name, Request, TimeoutAsync}, Client, State);

handle_call({'send_async', Name, Request, Timeout}, {Exclude, _} = Client,
            #state{uuid_generator = UUID,
                   dest_refresh = DestRefresh,
                   list_pg_data = Groups,
                   dest_deny = DestDeny,
                   dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            case destination_get(DestRefresh, Name, Exclude, Groups) of
                {error, _} when Timeout >= ?SEND_ASYNC_INTERVAL ->
                    erlang:send_after(?SEND_ASYNC_INTERVAL, self(),
                                      {'send_async', Name, Request,
                                       Timeout - ?SEND_ASYNC_INTERVAL,
                                       Client}),
                    {noreply, State};
                {error, _} ->
                    {reply, {error, timeout}, State};
                Pid ->
                    TransId = uuid:get_v1(UUID),
                    Pid ! {'send_async', Name, Request,
                           Timeout, TransId, self()},
                    {reply, {ok, TransId},
                     send_async_timeout_start(Timeout, TransId, State)}
                    
            end;
        false ->
            {reply, {error, timeout}, State}
    end;

handle_call({'send_sync', Name, Request}, Client,
            #state{timeout_sync = TimeoutSync} = State) ->
    handle_call({'send_sync', Name, Request, TimeoutSync}, Client, State);

handle_call({'send_sync', Name, Request, Timeout}, {Exclude, _} = Client,
            #state{uuid_generator = UUID,
                   dest_refresh = DestRefresh,
                   list_pg_data = Groups,
                   dest_deny = DestDeny,
                   dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            case destination_get(DestRefresh, Name, Exclude, Groups) of
                {error, _} when Timeout >= ?SEND_SYNC_INTERVAL ->
                    erlang:send_after(?SEND_SYNC_INTERVAL, self(),
                                      {'send_sync', Name, Request,
                                       Timeout - ?SEND_SYNC_INTERVAL,
                                       Client}),
                    {noreply, State};
                {error, _} ->
                    {reply, {error, timeout}, State};
                Pid ->
                    TransId = uuid:get_v1(UUID),
                    Self = self(),
                    Pid ! {'send_sync', Name, Request,
                           Timeout - ?TIMEOUT_DELTA, TransId, Self},
                    receive
                        {'return_sync', Name, Response, _, TransId, Self} ->
                            {reply, {ok, Response}, State}
                    after
                        Timeout ->
                            {reply, {error, timeout}, State}
                    end
            end;
        false ->
            {reply, {error, timeout}, State}
    end;

handle_call({'recv_async', Timeout, TransId}, Client,
            #state{async_responses = AsyncResponses} = State) ->
    if
        TransId == <<0:128>> ->
            case dict:to_list(AsyncResponses) of
                [] when Timeout >= ?RECV_ASYNC_INTERVAL ->
                    erlang:send_after(?RECV_ASYNC_INTERVAL, self(),
                                      {'recv_async',
                                       Timeout - ?RECV_ASYNC_INTERVAL,
                                       TransId, Client}),
                    {noreply, State};
                [] ->
                    {reply, {error, timeout}, State};
                [{TransIdUsed, Response} | _] ->
                    NewAsyncResponses = dict:erase(TransIdUsed, AsyncResponses),
                    {reply, {ok, Response},
                     State#state{async_responses = NewAsyncResponses}}
            end;
        true ->
            case dict:find(TransId, AsyncResponses) of
                error when Timeout >= ?RECV_ASYNC_INTERVAL ->
                    erlang:send_after(?RECV_ASYNC_INTERVAL, self(),
                                      {'recv_async',
                                       Timeout - ?RECV_ASYNC_INTERVAL,
                                       TransId, Client}),
                    {noreply, State};
                error ->
                    {reply, {error, timeout}, State};
                {ok, Response} ->
                    NewAsyncResponses = dict:erase(TransId, AsyncResponses),
                    {reply, {ok, Response},
                     State#state{async_responses = NewAsyncResponses}}
            end
    end;

handle_call(Request, _, State) ->
    ?LOG_WARNING("Unknown call \"~p\"", [Request]),
    {stop, string2:format("Unknown call \"~p\"", [Request]), error, State}.

handle_cast({'subscribe', Name},
            #state{job = Job,
                   prefix = Prefix} = State) ->
    list_pg:join(Prefix ++ Name, Job),
    {noreply, State};

handle_cast({'unsubscribe', Name},
            #state{job = Job,
                   prefix = Prefix} = State) ->
    list_pg:leave(Prefix ++ Name, Job),
    {noreply, State};

handle_cast(Request, State) ->
    ?LOG_WARNING("Unknown cast \"~p\"", [Request]),
    {noreply, State}.

handle_info({list_pg_data, Groups},
            #state{dest_refresh = DestRefresh} = State) ->
    destination_refresh_start(DestRefresh),
    {noreply, State#state{list_pg_data = Groups}};

handle_info({'send_async', Name, Request, Timeout, {Exclude, _} = Client},
            #state{uuid_generator = UUID,
                   dest_refresh = DestRefresh,
                   list_pg_data = Groups} = State) ->
    case destination_get(DestRefresh, Name, Exclude, Groups) of
        {error, _} when Timeout >= ?SEND_ASYNC_INTERVAL ->
            erlang:send_after(?SEND_ASYNC_INTERVAL, self(),
                              {'send_async', Name, Request,
                               Timeout - ?SEND_ASYNC_INTERVAL,
                               Client}),
            {noreply, State};
        {error, _} ->
            gen_server:reply(Client, {error, timeout}),
            {noreply, State};
        Pid ->
            TransId = uuid:get_v1(UUID),
            Pid ! {'send_async', Name, Request, Timeout, TransId, self()},
            gen_server:reply(Client, {ok, TransId}),
            {noreply, send_async_timeout_start(Timeout,
                                               TransId,
                                               State)}
    end;

handle_info({'send_sync', Name, Request, Timeout, {Exclude, _} = Client},
            #state{uuid_generator = UUID,
                   dest_refresh = DestRefresh,
                   list_pg_data = Groups} = State) ->
    case destination_get(DestRefresh, Name, Exclude, Groups) of
        {error, _} when Timeout >= ?SEND_SYNC_INTERVAL ->
            erlang:send_after(?SEND_SYNC_INTERVAL, self(),
                              {'send_sync', Name, Request,
                               Timeout - ?SEND_SYNC_INTERVAL,
                               Client}),
            {noreply, State};
        {error, _} ->
            gen_server:reply(Client, {error, timeout}),
            {noreply, State};
        Pid ->
            TransId = uuid:get_v1(UUID),
            Self = self(),
            Pid ! {'send_sync', Name, Request, Timeout, TransId, Self},
            receive
                {'return_sync', Name, Response, Timeout, TransId, Self} ->
                    gen_server:reply(Client, {ok, Response})
            after
                Timeout ->
                    gen_server:reply(Client, {error, timeout})
            end,
            {noreply, State}
    end;

handle_info({'forward_async', Name, Request, Timeout, TransId, Pid},
            #state{dest_refresh = DestRefresh,
                   list_pg_data = Groups,
                   dest_deny = DestDeny,
                   dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            case destination_get(DestRefresh, Name, Pid, Groups) of
                {error, _} when Timeout >= ?FORWARD_ASYNC_INTERVAL ->
                    erlang:send_after(?FORWARD_ASYNC_INTERVAL, self(),
                                      {'forward_async', Name, Request,
                                       Timeout - ?FORWARD_ASYNC_INTERVAL,
                                       TransId, Pid}),
                    ok;
                {error, _} ->
                    ok;
                NextPid ->
                    NextPid ! {'send_async', Name, Request,
                               Timeout, TransId, Pid}
            end;
        false ->
            ok
    end,
    {noreply, State};

handle_info({'forward_sync', Name, Request, Timeout, TransId, Pid},
            #state{dest_refresh = DestRefresh,
                   list_pg_data = Groups,
                   dest_deny = DestDeny,
                   dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            case destination_get(DestRefresh, Name, Pid, Groups) of
                {error, _} when Timeout >= ?FORWARD_SYNC_INTERVAL ->
                    erlang:send_after(?FORWARD_SYNC_INTERVAL, self(),
                                      {'forward_sync', Name, Request,
                                       Timeout - ?FORWARD_SYNC_INTERVAL,
                                       TransId, Pid}),
                    ok;
                {error, _} ->
                    ok;
                NextPid ->
                    NextPid ! {'send_sync', Name, Request,
                               Timeout, TransId, Pid}
            end;
        false ->
            ok
    end,
    {noreply, State};

handle_info({'recv_async', Timeout, TransId, Client},
            #state{async_responses = AsyncResponses} = State) ->
    if
        TransId == <<0:128>> ->
            case dict:to_list(AsyncResponses) of
                [] when Timeout >= ?RECV_ASYNC_INTERVAL ->
                    erlang:send_after(?RECV_ASYNC_INTERVAL, self(),
                                      {'recv_async',
                                       Timeout - ?RECV_ASYNC_INTERVAL,
                                       TransId, Client}),
                    {noreply, State};
                [] ->
                    gen_server:reply(Client, {error, timeout}),
                    {noreply, State};
                [{TransIdUsed, Response} | _] ->
                    NewAsyncResponses = dict:erase(TransIdUsed, AsyncResponses),
                    gen_server:reply(Client, {ok, Response}),
                    {noreply, State#state{async_responses = NewAsyncResponses}}
            end;
        true ->
            case dict:find(TransId, AsyncResponses) of
                error when Timeout >= ?RECV_ASYNC_INTERVAL ->
                    erlang:send_after(?RECV_ASYNC_INTERVAL, self(),
                                      {'recv_async',
                                       Timeout - ?RECV_ASYNC_INTERVAL,
                                       TransId, Client}),
                    {noreply, State};
                error ->
                    gen_server:reply(Client, {error, timeout}),
                    {noreply, State};
                {ok, Response} ->
                    NewAsyncResponses = dict:erase(TransId, AsyncResponses),
                    gen_server:reply(Client, {ok, Response}),
                    {noreply, State#state{async_responses = NewAsyncResponses}}
            end
    end;

handle_info({'return_async', _Name, Response, Timeout, TransId, Pid},
            State) ->
    true = Pid == self(),
    case send_timeout_check(TransId, State) of
        error ->
            % send_async timeout already occurred
            {noreply, State};
        {ok, Tref} ->
            erlang:cancel_timer(Tref),
            {noreply,
             recv_async_timeout_start(Response, Timeout, TransId,
                                      send_timeout_end(TransId, State))}
    end;

handle_info({'return_sync', _Name, _Response, _Timeout, _TransId, _Pid},
            State) ->
    % a response after a timeout is discarded
    {noreply, State};

handle_info({'send_async_timeout', TransId},
            State) ->
    case send_timeout_check(TransId, State) of
        error ->
            % should never happen, timer should have been cancelled
            % if the send_async already returned
            %XXX
            {noreply, State};
        {ok, _} ->
            {noreply, send_timeout_end(TransId, State)}
    end;

handle_info({'recv_async_timeout', TransId},
            State) ->
    {noreply, recv_async_timeout_end(TransId, State)};

handle_info(Request, State) ->
    ?LOG_WARNING("Unknown info \"~p\"", [Request]),
    {noreply, State}.

terminate(_, _) ->
    ok.

code_change(_, State, _) ->
    {ok, State}.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

destination_allowed(_, undefined, undefined) ->
    true;

destination_allowed(Name, undefined, DestAllow) ->
    Prefix = string2:beforer($/, Name),
    trie:is_prefix(Prefix, DestAllow);

destination_allowed(Name, DestDeny, undefined) ->
    Prefix = string2:beforer($/, Name),
    not trie:is_prefix(Prefix, DestDeny);

destination_allowed(Name, DestDeny, DestAllow) ->
    Prefix = string2:beforer($/, Name),
    case trie:is_prefix(Prefix, DestDeny) of
        true ->
            false;
        false ->
            trie:is_prefix(Prefix, DestAllow)
    end.

destination_refresh_start(lazy_closest) ->
    list_pg_data:get_groups(?DEST_REFRESH_SLOW);

destination_refresh_start(lazy_random) ->
    list_pg_data:get_groups(?DEST_REFRESH_SLOW);

destination_refresh_start(immediate_closest) ->
    ok;

destination_refresh_start(immediate_random) ->
    ok.

destination_get(lazy_closest, Name, Pid, Groups)
    when is_list(Name) ->
    list_pg_data:get_closest_pid(Name, Pid, Groups);

destination_get(lazy_random, Name, Pid, Groups)
    when is_list(Name) ->
    list_pg_data:get_random_pid(Name, Pid, Groups);

destination_get(immediate_closest, Name, Pid, _)
    when is_list(Name) ->
    list_pg:get_closest_pid(Name, Pid);

destination_get(immediate_random, Name, Pid, _)
    when is_list(Name) ->
    list_pg:get_random_pid(Name, Pid).

send_async_timeout_start(Timeout, TransId,
                         #state{send_timeouts = Ids} = State)
    when is_integer(Timeout), is_binary(TransId) ->
    Tref = erlang:send_after(Timeout, self(), {'send_async_timeout', TransId}),
    State#state{send_timeouts = dict:store(TransId, Tref, Ids)}.

send_timeout_check(TransId, #state{send_timeouts = Ids})
    when is_binary(TransId) ->
    dict:find(TransId, Ids).

send_timeout_end(TransId, #state{send_timeouts = Ids} = State)
    when is_binary(TransId) ->
    State#state{send_timeouts = dict:erase(TransId, Ids)}.

recv_async_timeout_start(Response, Timeout, TransId,
                         #state{async_responses = Ids} = State)
    when is_binary(Response), is_integer(Timeout), is_binary(TransId) ->
    erlang:send_after(Timeout, self(), {'recv_async_timeout', TransId}),
    State#state{async_responses = dict:store(TransId, Response, Ids)}.

recv_async_timeout_end(TransId,
                       #state{async_responses = Ids} = State)
    when is_binary(TransId) ->
    State#state{async_responses = dict:erase(TransId, Ids)}.

