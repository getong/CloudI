%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI Filesystem==
%%% A service that caches filesystem data for quick responses.
%%% @end
%%%
%%% BSD LICENSE
%%% 
%%% Copyright (c) 2011-2014, Michael Truog <mjtruog at gmail dot com>
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
%%% @copyright 2011-2014 Michael Truog
%%% @version 1.3.3 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_service_filesystem).
-author('mjtruog [at] gmail (dot) com').

-behaviour(cloudi_service).

%% external interface
-export([notify_all/3,
         notify_all/4,
         notify_all/5,
         notify_one/3,
         notify_one/4,
         notify_one/5,
         notify_clear/2]).

%% cloudi_service callbacks
-export([cloudi_service_init/3,
         cloudi_service_handle_request/11,
         cloudi_service_handle_info/3,
         cloudi_service_terminate/2]).

-include_lib("cloudi_core/include/cloudi_logger.hrl").
-include_lib("kernel/include/file.hrl").

-define(DEFAULT_DIRECTORY,           undefined). % required argument, string
-define(DEFAULT_REFRESH,             undefined). % seconds, see below:
        % How often to refresh the in-memory copy of the file data
-define(DEFAULT_CACHE,               undefined). % seconds, see below:
        % If defined, the request is treated as an HTTP request with the
        % modification time checked to determine if the file has changed
        % since it was last requested, allowing the HTTP client to
        % possibly reuse its cached copy.  HTTP headers are added to the
        % ResponseInfo to provide the modification time.
        % Use the value 'refresh' to assign (0.5 * refresh).
-define(DEFAULT_WRITE_TRUNCATE,             []). % see below:
        % A list of file service names (provided by this service) that
        % will overwrite the file contents with the service request data
-define(DEFAULT_WRITE_APPEND,               []). % see below:
        % A list of file service names (provided by this service) that
        % will append to the file contents with the service request data
-define(DEFAULT_NOTIFY_ONE,                 []). % see below:
        % A list of {Name, NotifyName} entries that provide a mapping from
        % a file service name (provided by this service) to a
        % notification service name which will receive the file's data
        % in a service request sent with send_async.
-define(DEFAULT_NOTIFY_ALL,                 []). % see below:
        % A list of {Name, NotifyName} entries that provide a mapping from
        % a file service name (provided by this service) to a
        % notification service name which will receive the file's data
        % in a service request sent with mcast_async.
-define(DEFAULT_NOTIFY_ON_START,          true). % send notify in init
-define(DEFAULT_USE_HTTP_GET_SUFFIX,      true). % see below:
        % Uses the "/get" suffix on service name patterns used for
        % subscriptions as would be used from HTTP related senders like
        % cloudi_service_http_cowboy.  Required for write-related
        % functionality and reading ranges.

-record(state,
    {
        prefix :: string(),
        directory :: string(),
        directory_length :: non_neg_integer(),
        refresh :: undefined | pos_integer(),
        cache :: undefined | pos_integer(),
        use_http_get_suffix :: boolean(),
        toggle :: boolean(),
        files :: cloudi_x_trie:cloudi_x_trie()
    }).

-record(file_notify,
    {
        send :: mcast_async | send_async,
        service_name :: cloudi_service:service_name(),
        timeout :: cloudi_service:timeout_milliseconds(),
        priority :: cloudi_service:priority()
    }).

-record(file,
    {
        contents :: binary(),
        path :: string(),
        mtime :: calendar:datetime(),
        access :: 'read' | 'write' | 'read_write' | 'none',
        toggle :: boolean(),
        notify = [] :: list(#file_notify{}),
        write = [] :: list(truncate | append),
        write_appends = [] :: list()
    }).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% @doc
%% ===Subscribe all service processes to be notified of file updates.===
%% The current file contents is returned, if the file is found.
%% @end
%%-------------------------------------------------------------------------

-spec notify_all(Dispatcher :: cloudi_service:dispatcher() |
                               cloudi:context(),
                 Name :: cloudi_service:service_name(),
                 NotifyName :: cloudi_service:service_name()) ->
    {ok, binary()} | {error, any()}.

notify_all(Dispatcher, Name, NotifyName) ->
    notify_all(Dispatcher, Name,
               NotifyName, undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Subscribe all service processes to be notified of file updates.===
%% The current file contents is returned, if the file is found.
%% @end
%%-------------------------------------------------------------------------

-spec notify_all(Dispatcher :: cloudi_service:dispatcher() |
                               cloudi:context(),
                 Name :: cloudi_service:service_name(),
                 NotifyName :: cloudi_service:service_name(),
                 NotifyTimeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, binary()} | {error, any()}.

notify_all(Dispatcher, Name, NotifyName, NotifyTimeout) ->
    notify_all(Dispatcher, Name,
               NotifyName, NotifyTimeout, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Subscribe all service processes to be notified of file updates.===
%% The current file contents is returned, if the file is found.
%% @end
%%-------------------------------------------------------------------------

-spec notify_all(Dispatcher :: cloudi_service:dispatcher() |
                               cloudi:context(),
                 Name :: cloudi_service:service_name(),
                 NotifyName :: cloudi_service:service_name(),
                 NotifyTimeout :: cloudi_service:timeout_milliseconds(),
                 NotifyPriority :: cloudi_service:priority()) ->
    {ok, binary()} | {error, any()}.

notify_all(Dispatcher, Name, NotifyName, NotifyTimeout, NotifyPriority) ->
    notify(Dispatcher, Name,
           NotifyName, NotifyTimeout, NotifyPriority, mcast_async).

%%-------------------------------------------------------------------------
%% @doc
%% ===Subscribe to have a service process notified of file updates.===
%% The current file contents is returned, if the file is found.
%% @end
%%-------------------------------------------------------------------------

-spec notify_one(Dispatcher :: cloudi_service:dispatcher() |
                               cloudi:context(),
                 Name :: cloudi_service:service_name(),
                 NotifyName :: cloudi_service:service_name()) ->
    {ok, binary()} | {error, any()}.

notify_one(Dispatcher, Name, NotifyName) ->
    notify_one(Dispatcher, Name,
               NotifyName, undefined, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Subscribe to have a service process notified of file updates.===
%% The current file contents is returned, if the file is found.
%% @end
%%-------------------------------------------------------------------------

-spec notify_one(Dispatcher :: cloudi_service:dispatcher() |
                               cloudi:context(),
                 Name :: cloudi_service:service_name(),
                 NotifyName :: cloudi_service:service_name(),
                 NotifyTimeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, binary()} | {error, any()}.

notify_one(Dispatcher, Name, NotifyName, NotifyTimeout) ->
    notify_one(Dispatcher, Name,
               NotifyName, NotifyTimeout, undefined).

%%-------------------------------------------------------------------------
%% @doc
%% ===Subscribe to have a service process notified of file updates.===
%% The current file contents is returned, if the file is found.
%% @end
%%-------------------------------------------------------------------------

-spec notify_one(Dispatcher :: cloudi_service:dispatcher() |
                               cloudi:context(),
                 Name :: cloudi_service:service_name(),
                 NotifyName :: cloudi_service:service_name(),
                 NotifyTimeout :: cloudi_service:timeout_milliseconds(),
                 NotifyPriority :: cloudi_service:priority()) ->
    {ok, binary()} | {error, any()}.

notify_one(Dispatcher, Name, NotifyName, NotifyTimeout, NotifyPriority) ->
    notify(Dispatcher, Name,
           NotifyName, NotifyTimeout, NotifyPriority, send_async).

%%-------------------------------------------------------------------------
%% @doc
%% ===Clear all notification subscriptions for a file.===
%% @end
%%-------------------------------------------------------------------------

-spec notify_clear(Dispatcher :: cloudi_service:dispatcher() |
                                 cloudi:context(),
                   Name :: cloudi_service:service_name()) ->
    ok | {error, any()}.

notify_clear(Dispatcher, Name) ->
    case cloudi:send_sync(Dispatcher, Name, notify_clear) of
        {error, _} = Error ->
            Error;
        {ok, {error, _} = Error} ->
            Error;
        {ok, ok} ->
            ok
    end.

%%%------------------------------------------------------------------------
%%% Callback functions from cloudi_service
%%%------------------------------------------------------------------------

cloudi_service_init(Args, Prefix, Dispatcher) ->
    Defaults = [
        {directory,              ?DEFAULT_DIRECTORY},
        {refresh,                ?DEFAULT_REFRESH},
        {cache,                  ?DEFAULT_CACHE},
        {write_truncate,         ?DEFAULT_WRITE_TRUNCATE},
        {write_append,           ?DEFAULT_WRITE_APPEND},
        {notify_one,             ?DEFAULT_NOTIFY_ONE},
        {notify_all,             ?DEFAULT_NOTIFY_ALL},
        {notify_on_start,        ?DEFAULT_NOTIFY_ON_START},
        {use_http_get_suffix,    ?DEFAULT_USE_HTTP_GET_SUFFIX}],
    [DirectoryRaw, Refresh, Cache0, WriteTruncateL, WriteAppendL,
     NotifyOneL, NotifyAllL, NotifyOnStart, UseHttpGetSuffix] =
        cloudi_proplists:take_values(Defaults, Args),
    true = is_list(DirectoryRaw),
    true = (Refresh =:= undefined) orelse
           (is_integer(Refresh) andalso
            (Refresh > 0) andalso (Refresh =< 4294967)),
    CacheN = if
        Cache0 =:= undefined ->
            undefined;
        Cache0 =:= refresh, is_integer(Refresh) ->
            erlang:max(Refresh div 2, 1);
        is_integer(Cache0), is_integer(Refresh),
        Cache0 > 0, Cache0 =< 31536000 ->
            Cache0
    end,
    true = is_list(NotifyOneL),
    true = is_list(NotifyAllL),
    true = is_boolean(NotifyOnStart),
    true = (UseHttpGetSuffix =:= true) orelse
           ((UseHttpGetSuffix =:= false) andalso
            (WriteTruncateL == []) andalso (WriteAppendL == [])),
    false = lists:member($*, Prefix),
    PrefixLength = erlang:length(Prefix),
    Directory = cloudi_service:environment_transform(DirectoryRaw),
    DirectoryLength = erlang:length(Directory),
    Toggle = true,
    Files1 = fold_files(Directory, fun(FilePath, FileName, FileInfo, Files0) ->
        case lists:member($*, FileName) of
            false ->
                #file_info{access = Access,
                           mtime = MTime} = FileInfo,
                case file_read_data(FileInfo, FilePath) of
                    {ok, Contents} ->
                        File = #file{contents = Contents,
                                     path = FilePath,
                                     mtime = MTime,
                                     access = Access,
                                     toggle = Toggle},
                        file_add_read(FileName, File, Files0,
                                      UseHttpGetSuffix, Prefix, Dispatcher);
                    {error, Reason} ->
                        ?LOG_ERROR("file read ~s error: ~p",
                                   [FilePath, Reason]),
                        Files0
                end;
            true ->
                ?LOG_ERROR("file name ~s error: '*' character invalid",
                           [FilePath]),
                Files0
        end
    end, cloudi_x_trie:new()),
    MTimeFake = calendar:now_to_universal_time(os:timestamp()),
    Files3 = lists:foldl(fun(Name, Files2) ->
        true = is_list(Name) andalso is_integer(hd(Name)),
        FileName = lists:nthtail(PrefixLength, Name),
        case cloudi_x_trie:find(Name, Files2) of
            {ok, #file{access = Access,
                       write = []} = File}
                when Access =:= read_write ->
                file_add_write_truncate(FileName,
                                        File#file{write = [truncate]},
                                        Files2, Prefix, Dispatcher);
            {ok, #file{path = FilePath}} ->
                erlang:exit({eacces, FilePath}),
                Files2;
            error ->
                FilePath = filename:join(Directory, FileName),
                file_add_write_new(FileName,
                                   #file{contents = <<>>,
                                         path = FilePath,
                                         mtime = MTimeFake,
                                         toggle = Toggle,
                                         write = [truncate]},
                                   Files2, Prefix, Dispatcher)
        end
    end, Files1, WriteTruncateL),
    Files5 = lists:foldl(fun(Name, Files4) ->
        true = is_list(Name) andalso is_integer(hd(Name)),
        FileName = lists:nthtail(PrefixLength, Name),
        case cloudi_x_trie:find(Name, Files4) of
            {ok, #file{access = Access,
                       write = Write} = File}
                when Access =:= read_write ->
                file_add_write_append(FileName,
                                      File#file{write = [append | Write]},
                                      Files4, Prefix, Dispatcher);
            {ok, #file{path = FilePath}} ->
                erlang:exit({eacces, FilePath}),
                Files4;
            error ->
                FilePath = filename:join(Directory, FileName),
                file_add_write_new(FileName,
                                   #file{contents = <<>>,
                                         path = FilePath,
                                         mtime = MTimeFake,
                                         toggle = Toggle,
                                         write = [append]},
                                   Files4, Prefix, Dispatcher)
        end
    end, Files3, WriteAppendL),
    Timeout = cloudi_service:timeout_async(Dispatcher),
    Priority = cloudi_service:priority_default(Dispatcher),
    Files8 = lists:foldl(fun({NameOne, NotifyNameOne}, Files6) ->
        true = is_list(NameOne) andalso is_integer(hd(NameOne)),
        true = is_list(NotifyNameOne) andalso is_integer(hd(NotifyNameOne)),
        true = lists:prefix(Prefix, NameOne),
        case files_notify(#file_notify{send = send_async,
                                       service_name = NotifyNameOne},
                          NameOne, Files6, Timeout, Priority,
                          Prefix, DirectoryLength, UseHttpGetSuffix) of
            {ok, _, Files7} ->
                Files7;
            {error, Reason} ->
                erlang:exit({Reason, NameOne}),
                Files6
        end
    end, Files5, NotifyOneL),
    FilesN = lists:foldl(fun({NameAll, NotifyNameAll}, Files9) ->
        true = is_list(NameAll) andalso is_integer(hd(NameAll)),
        true = is_list(NotifyNameAll) andalso is_integer(hd(NotifyNameAll)),
        true = lists:prefix(Prefix, NameAll),
        case files_notify(#file_notify{send = mcast_async,
                                       service_name = NotifyNameAll},
                          NameAll, Files9, Timeout, Priority,
                          Prefix, DirectoryLength, UseHttpGetSuffix) of
            {ok, _, Files10} ->
                Files10;
            {error, Reason} ->
                erlang:exit({Reason, NameAll}),
                Files9
        end
    end, Files8, NotifyAllL),
    if
        NotifyOnStart =:= true ->
            cloudi_x_trie:foreach(fun(Name,
                                      #file{contents = Contents,
                                            path = FilePath,
                                            notify = NotifyL}) ->
                FileName = lists:nthtail(DirectoryLength, FilePath),
                case lists:prefix(Prefix ++ FileName, Name) of
                    true ->
                        file_notify_send(NotifyL, Contents, Dispatcher);
                    false ->
                        ok
                end
            end, FilesN);
        true ->
            ok
    end,
    if
        is_integer(Refresh) ->
            erlang:send_after(Refresh * 1000,
                              cloudi_service:self(Dispatcher), refresh);
        true ->
            ok
    end,
    {ok, #state{prefix = Prefix,
                directory = Directory,
                directory_length = DirectoryLength,
                refresh = Refresh,
                cache = CacheN,
                toggle = Toggle,
                files = FilesN,
                use_http_get_suffix = UseHttpGetSuffix}}.

cloudi_service_handle_request(_Type, _Name, Pattern, _RequestInfo,
                              #file_notify{} = Notify,
                              Timeout, Priority, _TransId, _Pid,
                              #state{prefix = Prefix,
                                     directory_length = DirectoryLength,
                                     files = Files,
                                     use_http_get_suffix = UseHttpGetSuffix
                                     } = State, _Dispatcher) ->
    case files_notify(Notify, Pattern, Files, Timeout, Priority,
                      Prefix, DirectoryLength, UseHttpGetSuffix) of
        {ok, Contents, NewFiles} ->
            {reply, Contents, State#state{files = NewFiles}};
        {error, _} = Error ->
            {reply, Error, State}
    end;
cloudi_service_handle_request(_Type, _Name, Pattern, _RequestInfo,
                              notify_clear,
                              _Timeout, _Priority, _TransId, _Pid,
                              #state{prefix = Prefix,
                                     directory_length = DirectoryLength,
                                     files = Files,
                                     use_http_get_suffix = UseHttpGetSuffix
                                     } = State, _Dispatcher) ->
    case cloudi_x_trie:find(Pattern, Files) of
        {ok, #file{path = FilePath} = File} ->
            FileName = lists:nthtail(DirectoryLength, FilePath),
            NewFiles = file_refresh(FileName, File#file{notify = []},
                                    Files, UseHttpGetSuffix, Prefix),
            {reply, ok, State#state{files = NewFiles}};
        error ->
            {reply, {error, not_found}, State}
    end;
cloudi_service_handle_request(_Type, _Name, Pattern, RequestInfo, Request,
                              _Timeout, _Priority, _TransId, _Pid,
                              #state{files = Files,
                                     use_http_get_suffix = UseHttpGetSuffix
                                     } = State, _Dispatcher) ->
    case cloudi_x_trie:find(Pattern, Files) of
        {ok, #file{mtime = MTime,
                   contents = Contents} = File} ->
            if
                UseHttpGetSuffix =:= true ->
                    case cloudi_string:afterr($/, Pattern) of
                        "options" ->
                            {reply,
                             [{<<"allow">>,
                               <<"HEAD, GET, PUT, POST, OPTIONS">>} |
                              contents_ranges_headers(true)],
                             <<>>, State};
                        "head" ->
                            request_header(MTime, Contents, RequestInfo, State);
                        "get" ->
                            request_read(MTime, Contents, RequestInfo, State);
                        "put" ->
                            request_truncate(File, RequestInfo, Request, State);
                        "post" ->
                            request_append(File, RequestInfo, Request, State)
                    end;
                UseHttpGetSuffix =:= false ->
                    request_read(MTime, Contents, RequestInfo, State)
            end;
        error ->
            % possible if a sending service has stale service name lookup data
            % with a file that was removed during a refresh
            {reply,
             [{<<"status">>, erlang:integer_to_binary(404)}],
             <<>>, State}
    end.

cloudi_service_handle_info(refresh,
                           #state{prefix = Prefix,
                                  directory = Directory,
                                  refresh = Refresh,
                                  toggle = Toggle,
                                  files = Files,
                                  use_http_get_suffix =
                                      UseHttpGetSuffix} = State,
                           Dispatcher) ->
    NewToggle = not Toggle,
    NewFiles = files_refresh(Directory, NewToggle,
                             Files, UseHttpGetSuffix, Prefix, Dispatcher),
    erlang:send_after(Refresh * 1000,
                      cloudi_service:self(Dispatcher), refresh),
    {noreply, State#state{toggle = NewToggle,
                          files = NewFiles}};

cloudi_service_handle_info(Request, State, _) ->
    ?LOG_WARN("Unknown info \"~p\"", [Request]),
    {noreply, State}.

cloudi_service_terminate(_, #state{}) ->
    ok.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

request_header(MTime, Contents, RequestInfo,
               #state{cache = undefined,
                      use_http_get_suffix = true} = State) ->
    KeyValues = cloudi_service:request_info_key_value_parse(RequestInfo),
    NowTime = calendar:now_to_universal_time(os:timestamp()),
    ETag = cache_header_etag(MTime),
    case contents_ranges_read(ETag, KeyValues, MTime) of
        {206, RangeList} ->
            case content_range_list_check(RangeList, Contents) of
                {206, Headers} ->
                    {reply,
                     Headers ++
                     cacheless_headers_data(NowTime, MTime, ETag, true),
                     <<>>, State};
                {416, Headers} ->
                    {reply, Headers, <<>>, State}
            end;
        {200, undefined} ->
            {reply,
             cacheless_headers_data(NowTime, MTime, ETag, true),
             <<>>, State};
        {400, undefined} ->
            {reply, [{<<"status">>, <<"400">>}], <<>>, State}
    end;
request_header(MTime, Contents, RequestInfo,
               #state{cache = Cache,
                      use_http_get_suffix = true} = State) ->
    KeyValues = cloudi_service:request_info_key_value_parse(RequestInfo),
    NowTime = calendar:now_to_universal_time(os:timestamp()),
    ETag = cache_header_etag(MTime),
    case cache_status(ETag, KeyValues, MTime) of
        200 ->
            case contents_ranges_read(ETag, KeyValues, MTime) of
                {206, RangeList} ->
                    case content_range_list_check(RangeList, Contents) of
                        {206, Headers} ->
                            {reply,
                             Headers ++
                             cache_headers_data(NowTime, MTime,
                                                ETag, Cache, true),
                             <<>>, State};
                        {416, Headers} ->
                            {reply, Headers, <<>>, State}
                    end;
                {200, undefined} ->
                    {reply,
                     cache_headers_data(NowTime, MTime, ETag, Cache, true),
                     <<>>, State};
                {400, undefined} ->
                    {reply, [{<<"status">>, <<"400">>}], <<>>, State}
            end;
        Status ->
            % not modified due to caching
            {reply,
             [{<<"status">>, erlang:integer_to_binary(Status)} |
              cache_headers_empty(NowTime, MTime, true)],
             <<>>, State}
    end.

request_read(MTime, Contents, RequestInfo,
             #state{cache = undefined,
                    use_http_get_suffix = UseHttpGetSuffix} = State) ->
    KeyValues = cloudi_service:request_info_key_value_parse(RequestInfo),
    if
        UseHttpGetSuffix =:= true ->
            NowTime = calendar:now_to_universal_time(os:timestamp()),
            ETag = cache_header_etag(MTime),
            case contents_ranges_read(ETag, KeyValues, MTime) of
                {206, RangeList} ->
                    case content_range_read(RangeList, Contents) of
                        {206, Headers, Response} ->
                            {reply,
                             Headers ++
                             cacheless_headers_data(NowTime, MTime, ETag,
                                                    UseHttpGetSuffix),
                             Response, State};
                        {416, Headers, Response} ->
                            {reply, Headers, Response, State}
                    end;
                {200, undefined} ->
                    {reply,
                     cacheless_headers_data(NowTime, MTime, ETag,
                                            UseHttpGetSuffix),
                     Contents, State};
                {400, undefined} ->
                    {reply, [{<<"status">>, <<"400">>}], <<>>, State}
            end;
        UseHttpGetSuffix =:= false ->
            {reply, Contents, State}
    end;
request_read(MTime, Contents, RequestInfo,
             #state{cache = Cache,
                    use_http_get_suffix = UseHttpGetSuffix} = State) ->
    KeyValues = cloudi_service:request_info_key_value_parse(RequestInfo),
    NowTime = calendar:now_to_universal_time(os:timestamp()),
    ETag = cache_header_etag(MTime),
    case cache_status(ETag, KeyValues, MTime) of
        200 ->
            if
                UseHttpGetSuffix =:= true ->
                    case contents_ranges_read(ETag, KeyValues, MTime) of
                        {206, RangeList} ->
                            case content_range_read(RangeList, Contents) of
                                {206, Headers, Response} ->
                                    {reply,
                                     Headers ++
                                     cache_headers_data(NowTime, MTime,
                                                        ETag, Cache,
                                                        UseHttpGetSuffix),
                                     Response, State};
                                {416, Headers, Response} ->
                                    {reply, Headers, Response, State}
                            end;
                        {200, undefined} ->
                            {reply,
                             cache_headers_data(NowTime, MTime,
                                                ETag, Cache, UseHttpGetSuffix),
                             Contents, State};
                        {400, undefined} ->
                            {reply, [{<<"status">>, <<"400">>}], <<>>, State}
                    end;
                UseHttpGetSuffix =:= false ->
                    {reply,
                     cache_headers_data(NowTime, MTime,
                                        ETag, Cache, UseHttpGetSuffix),
                     Contents, State}
            end;
        Status ->
            % not modified due to caching
            {reply,
             [{<<"status">>, erlang:integer_to_binary(Status)} |
              cache_headers_empty(NowTime, MTime, UseHttpGetSuffix)],
             <<>>, State}
    end.

request_truncate(#file{path = FilePath,
                       write = Write} = File,
                 RequestInfo, Request,
                 #state{use_http_get_suffix = true} = State) ->
    case lists:member(truncate, Write) of
        true ->
            KeyValues = cloudi_service:
                        request_info_key_value_parse(RequestInfo),
            case cloudi_service:key_value_find(<<"range">>, KeyValues) of
                {ok, _} ->
                    {reply, [{<<"status">>, <<"400">>}], <<>>, State};
                error ->
                    NewContents = if
                        is_binary(Request) ->
                            Request;
                        is_list(Request) ->
                            erlang:iolist_to_binary(Request)
                    end,
                    NowTime = calendar:now_to_universal_time(os:timestamp()),
                    case file:write_file(FilePath, NewContents) of
                        ok ->
                            NewFile = File#file{contents = NewContents,
                                                mtime = NowTime},
                            request_truncate_file(NewFile, State);
                        {error, Reason} ->
                            ?LOG_ERROR("file write ~s error: ~p",
                                       [FilePath, Reason]),
                            {reply,
                             [{<<"status">>, <<"500">>}],
                             <<>>, State}
                    end
            end;
        false ->
            {reply,
             [{<<"status">>, <<"400">>}],
             <<>>, State}
    end.

request_truncate_file(#file{contents = Contents,
                            path = FilePath,
                            mtime = MTime} = File,
                      #state{prefix = Prefix,
                             directory_length = DirectoryLength,
                             cache = Cache,
                             files = Files,
                             use_http_get_suffix = true} = State) ->
    FileName = lists:nthtail(DirectoryLength, FilePath),
    ETag = cache_header_etag(MTime),
    NewFiles = file_refresh(FileName, File, Files, true, Prefix),
    Headers = if
        Cache =:= undefined ->
            cacheless_headers_data(MTime, MTime, ETag, true);
        true ->
            cache_headers_data(MTime, MTime, ETag, Cache, true)
    end,
    {reply,
     Headers, Contents,
     State#state{files = NewFiles}}.

request_append(#file{mtime = MTime,
                     write = Write,
                     write_appends = _Appends} = _File,
               RequestInfo, _Request,
               #state{} = State) ->
    case lists:member(append, Write) of
        true ->
            KeyValues = cloudi_service:
                        request_info_key_value_parse(RequestInfo),
            ETag = cache_header_etag(MTime),
            case contents_ranges_append(ETag, KeyValues, MTime) of
                {206, {_Range, _, true, 0}} ->
                    %XXX
                    {reply,
                     [{<<"status">>, <<"501">>}],
                     <<>>, State};
                {206, {_Range, _Id, true, _Index}} ->
                    %XXX
                    {reply,
                     [{<<"status">>, <<"501">>}],
                     <<>>, State};
                {206, {_Range, _Id, false, _Index}} ->
                    %XXX
                    {reply,
                     [{<<"status">>, <<"501">>}],
                     <<>>, State};
                {Status, undefined}
                    when Status == 400;
                         Status == 410 ->
                    {reply,
                     [{<<"status">>, erlang:integer_to_binary(Status)}],
                     <<>>, State}
            end;
        false ->
            {reply,
             [{<<"status">>, <<"400">>}],
             <<>>, State}
    end.

notify(Dispatcher, Name, [I | _] = NotifyName,
       NotifyTimeout, NotifyPriority, Send)
    when is_list(NotifyName), is_integer(I),
         ((is_integer(NotifyTimeout) andalso NotifyTimeout >= 0 andalso
           NotifyTimeout =< 4294967295) orelse
          (NotifyTimeout =:= undefined) orelse (NotifyTimeout =:= immediate)),
         ((is_integer(NotifyPriority) andalso NotifyPriority >= -128 andalso
           NotifyPriority =< 127) orelse (NotifyPriority =:= undefined)) ->
    case cloudi:send_sync(Dispatcher, Name,
                          #file_notify{send = Send,
                                       service_name = NotifyName,
                                       timeout = NotifyTimeout,
                                       priority = NotifyPriority}) of
        {error, _} = Error ->
            Error;
        {ok, {error, _} = Error} ->
            Error;
        {ok, Contents} = Success when is_binary(Contents) ->
            Success
    end.

files_notify(#file_notify{timeout = NotifyTimeout,
                          priority = NotifyPriority} = Notify,
             Name, Files, Timeout, Priority,
             Prefix, DirectoryLength, UseHttpGetSuffix) ->
    case cloudi_x_trie:find(Name, Files) of
        {ok, #file{contents = Contents,
                   path = FilePath,
                   notify = NotifyL} = File} ->
            NewNotifyTimeout = if
                is_integer(NotifyTimeout) ->
                    NotifyTimeout;
                true ->
                    Timeout
            end,
            NewNotifyPriority = if
                is_integer(NotifyPriority) ->
                    NotifyPriority;
                true ->
                    Priority
            end,
            NewNotify = Notify#file_notify{timeout = NewNotifyTimeout,
                                           priority = NewNotifyPriority},
            FileName = lists:nthtail(DirectoryLength, FilePath),
            NewFiles = file_refresh(FileName,
                                    File#file{notify = [NewNotify | NotifyL]},
                                    Files, UseHttpGetSuffix, Prefix),
            {ok, Contents, NewFiles};
        error ->
            {error, enoent}
    end.

service_name_suffix_read_root_file("index.htm") ->
    true;
service_name_suffix_read_root_file("index.html") ->
    true;
service_name_suffix_read_root_file(_) ->
    false.

service_name_suffix_read_root(FileName) ->
    [File | PathParts] = lists:reverse(filename:split(FileName)),
    case service_name_suffix_read_root_file(File) of
        true ->
            if
                PathParts == [] ->
                    "";
                true ->
                    filename:join(lists:reverse(PathParts)) ++ "/"
            end;
        false ->
            undefined
    end.

service_name_suffix_options(FileName) ->
    FileName ++ "/options".

service_name_suffix_header(FileName) ->
    FileName ++ "/head".

service_name_suffix_read(FileName, true) ->
    FileName ++ "/get";
service_name_suffix_read(FileName, false) ->
    FileName.

service_name_suffix_write_truncate(FileName) ->
    FileName ++ "/put".

service_name_suffix_write_append(FileName) ->
    FileName ++ "/post".

file_add_read(FileName, File,
              Files0, UseHttpGetSuffix, Prefix, Dispatcher) ->
    Files3 = case service_name_suffix_read_root(FileName) of
        undefined ->
            Files0;
        SuffixRead ->
            Files2 = if
                UseHttpGetSuffix =:= true ->
                    Suffix0 = service_name_suffix_options(SuffixRead),
                    cloudi_service:subscribe(Dispatcher, Suffix0),
                    Files1 = cloudi_x_trie:store(Prefix ++ Suffix0,
                                                 File, Files0),
                    Suffix1 = service_name_suffix_header(SuffixRead),
                    cloudi_service:subscribe(Dispatcher, Suffix1),
                    cloudi_x_trie:store(Prefix ++ Suffix1, File, Files1);
                UseHttpGetSuffix =:= false ->
                    Files0
            end,
            Suffix2 = service_name_suffix_read(SuffixRead, UseHttpGetSuffix),
            cloudi_service:subscribe(Dispatcher, Suffix2),
            cloudi_x_trie:store(Prefix ++ Suffix2, File, Files2)
    end,
    Suffix3 = service_name_suffix_read(FileName, UseHttpGetSuffix),
    cloudi_service:subscribe(Dispatcher, Suffix3),
    Files4 = cloudi_x_trie:store(Prefix ++ Suffix3, File, Files3),
    if
        UseHttpGetSuffix =:= true ->
            Suffix4 = service_name_suffix_options(FileName),
            cloudi_service:subscribe(Dispatcher, Suffix4),
            Files5 = cloudi_x_trie:store(Prefix ++ Suffix4,
                                         File, Files4),
            Suffix5 = service_name_suffix_header(FileName),
            cloudi_service:subscribe(Dispatcher, Suffix5),
            cloudi_x_trie:store(Prefix ++ Suffix5, File, Files5);
        UseHttpGetSuffix =:= false ->
            Files4
    end.

file_add_write_new(FileName, #file{write = Write} = File,
                   Files0, Prefix, Dispatcher) ->
    Files1 = file_add_read(FileName, File,
                           Files0, true, Prefix, Dispatcher),
    case Write of
        [truncate] ->
            file_add_write_truncate(FileName, File,
                                    Files1, Prefix, Dispatcher);
        [append] ->
            file_add_write_append(FileName, File,
                                  Files1, Prefix, Dispatcher)
    end.

file_add_write_truncate(FileName, #file{write = [truncate]} = File,
                        Files0, Prefix, Dispatcher) ->
    Suffix0 = service_name_suffix_write_truncate(FileName),
    cloudi_service:subscribe(Dispatcher, Suffix0),
    cloudi_x_trie:store(Prefix ++ Suffix0, File, Files0).

file_add_write_append(FileName, #file{write = Write} = File,
                      Files0, Prefix, Dispatcher) ->
    Suffix0 = service_name_suffix_write_append(FileName),
    cloudi_service:subscribe(Dispatcher, Suffix0),
    case lists:delete(append, Write) of
        [] ->
            cloudi_x_trie:store(Prefix ++ Suffix0, File, Files0);
        [truncate] ->
            file_refresh(FileName, File,
                         Files0, true, Prefix)
    end.

file_refresh(FileName, #file{write = Write} = File,
             Files0, UseHttpGetSuffix, Prefix) ->
    Files3 = case service_name_suffix_read_root(FileName) of
        undefined ->
            Files0;
        SuffixRead ->
            Files2 = if
                UseHttpGetSuffix =:= true ->
                    Suffix0 = service_name_suffix_options(SuffixRead),
                    Files1 = cloudi_x_trie:store(Prefix ++ Suffix0,
                                                 File, Files0),
                    Suffix1 = service_name_suffix_header(SuffixRead),
                    cloudi_x_trie:store(Prefix ++ Suffix1, File, Files1);
                UseHttpGetSuffix =:= false ->
                    Files0
            end,
            Suffix2 = service_name_suffix_read(SuffixRead, UseHttpGetSuffix),
            cloudi_x_trie:store(Prefix ++ Suffix2, File, Files2)
    end,
    Suffix3 = service_name_suffix_read(FileName, UseHttpGetSuffix),
    Files4 = cloudi_x_trie:store(Prefix ++ Suffix3, File, Files3),
    if
        UseHttpGetSuffix =:= true ->
            Suffix4 = service_name_suffix_options(FileName),
            Files5 = cloudi_x_trie:store(Prefix ++ Suffix4,
                                         File, Files4),
            Suffix5 = service_name_suffix_header(FileName),
            Files6 = cloudi_x_trie:store(Prefix ++ Suffix5, File, Files5),
            Files7 = case lists:member(truncate, Write) of
                true ->
                    Suffix6 = service_name_suffix_write_truncate(FileName),
                    cloudi_x_trie:store(Prefix ++ Suffix6, File, Files6);
                false ->
                    Files6
            end,
            case lists:member(append, Write) of
                true ->
                    Suffix7 = service_name_suffix_write_append(FileName),
                    cloudi_x_trie:store(Prefix ++ Suffix7, File, Files7);
                false ->
                    Files7
            end;
        UseHttpGetSuffix =:= false ->
            Files4
    end.

file_remove_read(FileName, Files0, UseHttpGetSuffix, Prefix, Dispatcher) ->
    Files3 = case service_name_suffix_read_root(FileName) of
        undefined ->
            Files0;
        SuffixRead ->
            Files2 = if
                UseHttpGetSuffix =:= true ->
                    Suffix0 = service_name_suffix_options(SuffixRead),
                    cloudi_service:unsubscribe(Dispatcher, Suffix0),
                    Files1 = cloudi_x_trie:erase(Prefix ++ Suffix0, Files0),
                    Suffix1 = service_name_suffix_header(SuffixRead),
                    cloudi_service:unsubscribe(Dispatcher, Suffix1),
                    cloudi_x_trie:erase(Prefix ++ Suffix1, Files1);
                UseHttpGetSuffix =:= false ->
                    Files0
            end,
            Suffix2 = service_name_suffix_read(SuffixRead, UseHttpGetSuffix),
            cloudi_service:unsubscribe(Dispatcher, Suffix2),
            cloudi_x_trie:erase(Prefix ++ Suffix2, Files2)
    end,
    Suffix3 = service_name_suffix_read(FileName, UseHttpGetSuffix),
    cloudi_service:unsubscribe(Dispatcher, Suffix3),
    Files4 = cloudi_x_trie:erase(Prefix ++ Suffix3, Files3),
    if
        UseHttpGetSuffix =:= true ->
            Suffix4 = service_name_suffix_options(FileName),
            cloudi_service:unsubscribe(Dispatcher, Suffix4),
            Files5 = cloudi_x_trie:erase(Prefix ++ Suffix4, Files4),
            Suffix5 = service_name_suffix_header(FileName),
            cloudi_service:unsubscribe(Dispatcher, Suffix5),
            cloudi_x_trie:erase(Prefix ++ Suffix5, Files5);
        UseHttpGetSuffix =:= false ->
            Files4
    end.

file_exists(FileName, Files, UseHttpGetSuffix, Prefix) ->
    Suffix = service_name_suffix_read(FileName, UseHttpGetSuffix),
    cloudi_x_trie:find(Prefix ++ Suffix, Files).

% allow it to read from any non-directory/link type (device, other, regular)
file_read_data(#file_info{access = Access}, FilePath)
    when Access =:= read; Access =:= read_write ->
    file:read_file(FilePath);
file_read_data(_, _) ->
    {error, enoent}.

file_notify_send([], _, _) ->
    ok;
file_notify_send([#file_notify{send = Send,
                               service_name = Name,
                               timeout = Timeout,
                               priority = Priority} | NotifyL],
                 Contents, Dispatcher) ->
    cloudi_service:Send(Dispatcher, Name, <<>>, Contents, Timeout, Priority),
    file_notify_send(NotifyL, Contents, Dispatcher).

files_refresh(Directory, Toggle,
              Files0, UseHttpGetSuffix, Prefix, Dispatcher) ->
    Files2 = fold_files(Directory, fun(FilePath, FileName, FileInfo, Files1) ->
        #file_info{access = Access,
                   mtime = MTime} = FileInfo,
        case file_exists(FileName, Files1, UseHttpGetSuffix, Prefix) of
            {ok, #file{mtime = MTime} = File0} ->
                File1 = File0#file{toggle = Toggle},
                file_refresh(FileName, File1, Files1,
                             UseHttpGetSuffix, Prefix);
            {ok, #file{notify = NotifyL,
                       write = Write} = File0} ->
                case file_read_data(FileInfo, FilePath) of
                    {ok, Contents} ->
                        file_notify_send(NotifyL, Contents, Dispatcher),
                        File1 = File0#file{contents = Contents,
                                           mtime = MTime,
                                           access = Access,
                                           toggle = Toggle},
                        file_refresh(FileName, File1, Files1,
                                     UseHttpGetSuffix, Prefix);
                    {error, _} when Write =:= [] ->
                        % file was removed during traversal
                        file_remove_read(FileName, Files1,
                                         UseHttpGetSuffix, Prefix,
                                         Dispatcher);
                    {error, _} ->
                        File1 = File0#file{access = Access,
                                           toggle = Toggle},
                        file_refresh(FileName, File1, Files1,
                                     UseHttpGetSuffix, Prefix)
                end;
            error ->
                case file_read_data(FileInfo, FilePath) of
                    {ok, Contents} ->
                        File = #file{contents = Contents,
                                     path = FilePath,
                                     mtime = MTime,
                                     access = Access,
                                     toggle = Toggle},
                        file_add_read(FileName, File, Files1,
                                      UseHttpGetSuffix, Prefix, Dispatcher);
                    {error, _} ->
                        % file was removed during traversal
                        file_remove_read(FileName, Files1,
                                         UseHttpGetSuffix, Prefix,
                                         Dispatcher)
                end
        end
    end, Files0),
    PrefixLength = erlang:length(Prefix),
    cloudi_x_trie:foldl(fun(Pattern,
                            #file{toggle = FileToggle,
                                  write = Write} = File, Files3) ->
        if
            FileToggle =/= Toggle ->
                if
                    Write =:= [] ->
                        Suffix = lists:nthtail(PrefixLength, Pattern),
                        cloudi_service:unsubscribe(Dispatcher, Suffix),
                        cloudi_x_trie:erase(Pattern, Files3);
                    true ->
                        cloudi_x_trie:store(Pattern,
                                            File#file{toggle = Toggle}, Files3)
                end;
            true ->
                Files3
        end
    end, Files2, Files2).

-spec fold_files(Directory :: string() | binary(),
                 F :: fun((string(), string(), #file_info{}, any()) -> any()),
                 A :: any()) ->
    any().

% similar to filelib:fold_files/5 but
% with recursive always true, with a regex of ".*",
% with links included, and with both the filename and file_info provided to F
fold_files(Directory, F, A)
    when is_function(F, 4) ->
    case file:list_dir_all(Directory) of
        {ok, FileNames} ->
            fold_files_directory(FileNames, Directory, F, A);
        {error, Reason} ->
            ?LOG_WARN("directory ~s error: ~p", [Directory, Reason]),
            A
    end.

fold_files(Directory, Path, F, A)
    when is_function(F, 4) ->
    case file:list_dir_all(filename:join(Directory, Path)) of
        {ok, FileNames} ->
            fold_files_directory([filename:join(Path, FileName) ||
                                  FileName <- FileNames],
                                 Directory, F, A);
        {error, Reason} ->
            ?LOG_WARN("directory ~s path ~s error: ~p",
                      [Directory, Path, Reason]),
            A
    end.

fold_files_f(FilePath, FileName, FileInfo, F, A) ->
    FilePathString = if
        is_binary(FilePath) ->
            erlang:binary_to_list(FilePath);
        is_list(FilePath) ->
            FilePath
    end,
    FileNameString = if
        is_binary(FileName) ->
            erlang:binary_to_list(FileName);
        is_list(FileName) ->
            FileName
    end,
    F(FilePathString, FileNameString, FileInfo, A).

fold_files_directory([], _, _, A) ->
    A;
fold_files_directory([FileName | FileNames], Directory, F, A) ->
    FilePath = filename:join(Directory, FileName),
    case file:read_file_info(FilePath, [{time, universal}]) of
        {ok, #file_info{type = directory}} ->
            fold_files_directory(FileNames, Directory, F,
                                 fold_files(Directory, FileName, F, A));
        {ok, FileInfo} ->
            fold_files_directory(FileNames, Directory, F,
                                 fold_files_f(FilePath, FileName, FileInfo,
                                              F, A));
        {error, Reason} ->
            ?LOG_WARN("file ~s error: ~p", [FilePath, Reason]),
            fold_files_directory(FileNames, Directory, F, A)
    end.

cache_status(ETag, KeyValues, MTime) ->
    cache_status_0(ETag, KeyValues, MTime).

cache_status_0(ETag, KeyValues, MTime) ->
    case cloudi_service:key_value_find(<<"if-none-match">>, KeyValues) of
        {ok, <<"*">>} ->
            cache_status_1(ETag, KeyValues, MTime);
        error ->
            cache_status_1(ETag, KeyValues, MTime);
        {ok, IfNoneMatch} ->
            case binary:match(IfNoneMatch, ETag) of
                nomatch ->
                    cache_status_1(ETag, KeyValues, MTime);
                _ ->
                    304
            end
    end.

cache_status_1(ETag, KeyValues, MTime) ->
    case cloudi_service:key_value_find(<<"if-match">>, KeyValues) of
        {ok, <<"*">>} ->
            cache_status_2(KeyValues, MTime);
        error ->
            cache_status_2(KeyValues, MTime);
        {ok, IfMatch} ->
            case binary:match(IfMatch, ETag) of
                nomatch ->
                    412;
                _ ->
                    cache_status_2(KeyValues, MTime)
            end
    end.

cache_status_2(KeyValues, MTime) ->
    case cloudi_service:key_value_find(<<"if-modified-since">>, KeyValues) of
        {ok, DateTimeBinary} ->
            case cloudi_service_filesystem_datetime:parse(DateTimeBinary) of
                {error, _} ->
                    cache_status_3(KeyValues, MTime);
                DateTime when MTime > DateTime ->
                    200;
                _ ->
                    304
            end;
        error ->
            cache_status_3(KeyValues, MTime)
    end.

cache_status_3(KeyValues, MTime) ->
    case cloudi_service:key_value_find(<<"if-unmodified-since">>, KeyValues) of
        {ok, DateTimeBinary} ->
            case cloudi_service_filesystem_datetime:parse(DateTimeBinary) of
                {error, _} ->
                    200;
                DateTime when MTime =< DateTime ->
                    412;
                _ ->
                    200
            end;
        error ->
            200
    end.

cache_header_etag(MTime) ->
    Output = io_lib:format("\"~.16b\"",
                           [calendar:datetime_to_gregorian_seconds(MTime)]),
    erlang:iolist_to_binary(Output).

cache_header_control(Cache) ->
    Output = io_lib:format("public,max-age=~w", [Cache]),
    erlang:iolist_to_binary(Output).

cache_header_expires(ATime, Cache) ->
    Seconds = calendar:datetime_to_gregorian_seconds(ATime),
    Expires = calendar:gregorian_seconds_to_datetime(Seconds + Cache),
    rfc1123_format(Expires).

cache_headers_data(NowTime, MTime, ETag, Cache, UseHttpGetSuffix) ->
    [{<<"etag">>, ETag},
     {<<"cache-control">>, cache_header_control(Cache)},
     {<<"expires">>, cache_header_expires(NowTime, Cache)},
     {<<"last-modified">>, rfc1123_format(MTime)},
     {<<"date">>, rfc1123_format(NowTime)} |
     contents_ranges_headers(UseHttpGetSuffix)].

cache_headers_empty(NowTime, MTime, UseHttpGetSuffix) ->
    [{<<"last-modified">>, rfc1123_format(MTime)},
     {<<"date">>, rfc1123_format(NowTime)} |
     contents_ranges_headers(UseHttpGetSuffix)].

cacheless_headers_data(NowTime, MTime, ETag, UseHttpGetSuffix) ->
    [{<<"etag">>, ETag},
     {<<"last-modified">>, rfc1123_format(MTime)},
     {<<"date">>, rfc1123_format(NowTime)} |
     contents_ranges_headers(UseHttpGetSuffix)].

contents_ranges_headers(true) ->
    [{<<"accept-ranges">>, <<"bytes">>}];
contents_ranges_headers(false) ->
    [].

contents_ranges_read(ETag, KeyValues, MTime) ->
    contents_ranges_read_0(ETag, KeyValues, MTime).

contents_ranges_read_0(ETag, KeyValues, MTime) ->
    case cloudi_service:key_value_find(<<"range">>, KeyValues) of
        {ok, RangeData} ->
            case cloudi_x_cowboy_http:range(RangeData) of
                {error, badarg} ->
                    {400, undefined};
                {<<"bytes">>, RangeList} ->
                    contents_ranges_read_1(RangeList, ETag,
                                           KeyValues, MTime);
                {_, _} ->
                    {200, undefined}
            end;
        error ->
            {200, undefined}
    end.

contents_ranges_read_1(RangeList, ETag, KeyValues, MTime) ->
    case cloudi_service:key_value_find(<<"if-range">>, KeyValues) of
        {ok, ETag} ->
            {206, RangeList};
        {ok, IfRangeData} ->
            case cloudi_service_filesystem_datetime:parse(IfRangeData) of
                {error, _} ->
                    {200, undefined};
                DateTime when MTime == DateTime ->
                    {206, RangeList};
                _ ->
                    {200, undefined}
            end;
        error ->
            {206, RangeList}
    end.

contents_ranges_append(ETag, KeyValues, MTime) ->
    Id = case cloudi_service:key_value_find(<<"x-multipart-id">>,
                                            KeyValues) of
        {ok, MultipartId} ->
            MultipartId;
        error ->
            undefined
    end,
    Last = case cloudi_service:key_value_find(<<"x-multipart-last">>,
                                              KeyValues) of
        {ok, <<"true">>} ->
            true;
        error ->
            false
    end,
    Index = case cloudi_service:key_value_find(<<"x-multipart-index">>,
                                               KeyValues) of
        {ok, IndexBin} ->
            erlang:binary_to_integer(IndexBin);
        error ->
            0
    end,
    case contents_ranges_read(ETag, KeyValues, MTime) of
        {200, undefined} ->
            {410, undefined};
        {206, [Range]} ->
            NewLast = Last orelse (Id =:= undefined),
            {206, {Range, Id, NewLast, Index}};
        {206, [_ | _] = RangeList} ->
            try lists:nth(Index + 1, RangeList) of
                Range ->
                    {206, {Range, Id, Last, Index}}
            catch
                _:_ ->
                    {400, undefined}
            end;
        {400, undefined} = BadRequest ->
            BadRequest
    end.

content_range_read_part(undefined,
                        ByteStart, ByteEnd, ContentLengthBin, Part) ->
    ByteStartBin = erlang:integer_to_binary(ByteStart),
    ByteEndBin = erlang:integer_to_binary(ByteEnd),
    {[{<<"content-range">>,
       <<(<<"bytes ">>)/binary,
         ByteStartBin/binary,(<<"-">>)/binary,
         ByteEndBin/binary,(<<"/">>)/binary,
         ContentLengthBin/binary>>}], Part};
content_range_read_part(Boundary,
                        ByteStart, ByteEnd, ContentLengthBin, Part) ->
    ByteStartBin = erlang:integer_to_binary(ByteStart),
    ByteEndBin = erlang:integer_to_binary(ByteEnd),
    [cloudi_x_cow_multipart:part(Boundary,
                                 [{<<"content-range">>,
                                   <<(<<"bytes ">>)/binary,
                                     ByteStartBin/binary,(<<"-">>)/binary,
                                     ByteEndBin/binary,(<<"/">>)/binary,
                                     ContentLengthBin/binary>>}]),
     Part].

content_range_read([_ | L] = RangeList, Contents) ->
    ContentLength = erlang:byte_size(Contents),
    ContentLengthBin = erlang:integer_to_binary(ContentLength),
    Boundary = if
        L == [] ->
            undefined;
        true ->
            % make a multipart/byteranges response
            cloudi_x_cow_multipart:boundary()
    end,
    content_range_read(RangeList, [], Boundary,
                       ContentLengthBin, ContentLength, Contents).

content_range_read([], [{Headers, Response}], undefined, _, _, _) ->
    {206, [{<<"status">>, <<"206">>} | Headers], Response};
content_range_read([], Output, Boundary, _, _, _) ->
    {206,
     [{<<"status">>, <<"206">>},
      {<<"content-type">>,
       <<(<<"multipart/byteranges; boundary=">>)/binary, Boundary/binary>>}],
     lists:reverse([cloudi_x_cow_multipart:close(Boundary) | Output])};
content_range_read([{I, infinity} | RangeList], Output, Boundary,
                   ContentLengthBin, ContentLength, Contents) ->
    ByteStart = if
        I < 0 ->
            ContentLength + I;
        I >= 0 ->
            I
    end,
    ByteEnd = ContentLength - 1,
    if
        ByteStart =< ByteEnd ->
            Part = binary:part(Contents, ByteStart, ByteEnd - ByteStart + 1),
            Entry = content_range_read_part(Boundary, ByteStart, ByteEnd,
                                            ContentLengthBin, Part),
            content_range_read(RangeList, [Entry | Output], Boundary,
                               ContentLengthBin, ContentLength, Contents);
        true ->
            {416,
             [{<<"status">>, <<"416">>},
              {<<"content-range">>,
               <<(<<"bytes */">>)/binary, ContentLengthBin/binary>>}], <<>>}
    end;
content_range_read([{IStart, IEnd} | RangeList], Output, Boundary,
                   ContentLengthBin, ContentLength, Contents) ->
    ByteStart = if
        IStart < 0 ->
            ContentLength + IStart;
        IStart >= 0 ->
            IStart
    end,
    ByteEnd = IEnd,
    if
        ByteStart =< ByteEnd ->
            Part = binary:part(Contents, ByteStart, ByteEnd - ByteStart + 1),
            Entry = content_range_read_part(Boundary, ByteStart, ByteEnd,
                                            ContentLengthBin, Part),
            content_range_read(RangeList, [Entry | Output], Boundary,
                               ContentLengthBin, ContentLength, Contents);
        true ->
            {416,
             [{<<"status">>, <<"416">>},
              {<<"content-range">>,
               <<(<<"bytes */">>)/binary, ContentLengthBin/binary>>}], <<>>}
    end;
content_range_read([I | RangeList], Output, Boundary,
                   ContentLengthBin, ContentLength, Contents)
    when is_integer(I) ->
    content_range_read([{I, infinity} | RangeList], Output, Boundary,
                       ContentLengthBin, ContentLength, Contents).
    
content_range_list_check([_ | L] = RangeList, Contents) ->
    ContentLength = erlang:byte_size(Contents),
    ContentLengthBin = erlang:integer_to_binary(ContentLength),
    Boundary = if
        L == [] ->
            undefined;
        true ->
            % make a multipart/byteranges response
            cloudi_x_cow_multipart:boundary()
    end,
    content_range_list_check(RangeList, Boundary,
                             ContentLengthBin, ContentLength).

content_range_list_check([], undefined, _, _) ->
    {206, [{<<"status">>, <<"206">>}]};
content_range_list_check([], _, _, _) ->
    {206,
     [{<<"status">>, <<"206">>},
      {<<"content-type">>, <<"multipart/byteranges">>}]};
content_range_list_check([{I, infinity} | RangeList], Boundary,
                         ContentLengthBin, ContentLength) ->
    ByteStart = if
        I < 0 ->
            ContentLength + I;
        I >= 0 ->
            I
    end,
    ByteEnd = ContentLength - 1,
    if
        ByteStart =< ByteEnd ->
            content_range_list_check(RangeList, Boundary,
                                     ContentLengthBin, ContentLength);
        true ->
            {416,
             [{<<"status">>, <<"416">>},
              {<<"content-range">>,
               <<(<<"bytes */">>)/binary, ContentLengthBin/binary>>}]}
    end;
content_range_list_check([{IStart, IEnd} | RangeList], Boundary,
                         ContentLengthBin, ContentLength) ->
    ByteStart = if
        IStart < 0 ->
            ContentLength + IStart;
        IStart >= 0 ->
            IStart
    end,
    ByteEnd = IEnd,
    if
        ByteStart =< ByteEnd ->
            content_range_list_check(RangeList, Boundary,
                                     ContentLengthBin, ContentLength);
        true ->
            {416,
             [{<<"status">>, <<"416">>},
              {<<"content-range">>,
               <<(<<"bytes */">>)/binary, ContentLengthBin/binary>>}]}
    end;
content_range_list_check([I | RangeList], Boundary,
                         ContentLengthBin, ContentLength)
    when is_integer(I) ->
    content_range_list_check([{I, infinity} | RangeList], Boundary,
                             ContentLengthBin, ContentLength).

rfc1123_format_day(1) ->
    "Mon";
rfc1123_format_day(2) ->
    "Tue";
rfc1123_format_day(3) ->
    "Wed";
rfc1123_format_day(4) ->
    "Thu";
rfc1123_format_day(5) ->
    "Fri";
rfc1123_format_day(6) ->
    "Sat";
rfc1123_format_day(7) ->
    "Sun".

rfc1123_format_month(1) ->
    "Jan";
rfc1123_format_month(2) ->
    "Feb";
rfc1123_format_month(3) ->
    "Mar";
rfc1123_format_month(4) ->
    "Apr";
rfc1123_format_month(5) ->
    "May";
rfc1123_format_month(6) ->
    "Jun";
rfc1123_format_month(7) ->
    "Jul";
rfc1123_format_month(8) ->
    "Aug";
rfc1123_format_month(9) ->
    "Sep";
rfc1123_format_month(10) ->
    "Oct";
rfc1123_format_month(11) ->
    "Nov";
rfc1123_format_month(12) ->
    "Dec".

rfc1123_format({{Year, Month, Day}, {Hour, Minute, Second}}) ->
    % e.g., Sun, 06 Nov 1994 08:49:37 GMT
    %       Mon, 29 Apr 2013 21:44:55 GMT
    DayStr = rfc1123_format_day(calendar:day_of_the_week(Year, Month, Day)),
    MonthStr = rfc1123_format_month(Month),
    Output = io_lib:format("~s, ~2..0w ~s ~4..0w ~2..0w:~2..0w:~2..0w GMT",
                           [DayStr, Day, MonthStr, Year, Hour, Minute, Second]),
    erlang:iolist_to_binary(Output).

