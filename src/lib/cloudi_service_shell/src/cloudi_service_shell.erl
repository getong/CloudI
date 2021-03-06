%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et nomod:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI Shell Service==
%%% @end
%%%
%%% MIT License
%%%
%%% Copyright (c) 2019-2020 Michael Truog <mjtruog at protonmail dot com>
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
%%% @copyright 2019-2020 Michael Truog
%%% @version 1.8.1 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_service_shell).
-author('mjtruog at protonmail dot com').

-behaviour(cloudi_service).

%% external interface
-export([exec/3,
         exec/4]).

%% cloudi_service callbacks
-export([cloudi_service_init/4,
         cloudi_service_handle_request/11,
         cloudi_service_terminate/3]).

-include_lib("cloudi_core/include/cloudi_logger.hrl").

-define(DEFAULT_FILE_PATH,              "/bin/sh").
-define(DEFAULT_DIRECTORY,                    "/").
-define(DEFAULT_ENV,                           []).
-define(DEFAULT_USER,                   undefined).
-define(DEFAULT_SU_PATH,                "/bin/su").
-define(DEFAULT_LOGIN,                       true).
-define(DEFAULT_DEBUG,                       true).
-define(DEFAULT_DEBUG_LEVEL,                trace).

-record(state,
    {
        file_path :: nonempty_string(),
        directory :: nonempty_string(),
        env :: list({nonempty_string(), string()}),
        env_port :: boolean(),
        user :: nonempty_string() | undefined,
        su :: nonempty_string(),
        login :: boolean(),
        debug_level :: off | trace | debug | info | warn | error | fatal
    }).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

-type agent() :: cloudi:agent().
-type service_name() :: cloudi:service_name().
-type timeout_milliseconds() :: cloudi:timeout_milliseconds().
-type module_response(Result) ::
    {{ok, Result}, AgentNew :: agent()} |
    {{error, cloudi:error_reason()}, AgentNew :: agent()}.

-spec exec(Agent :: agent(),
           Prefix :: service_name(),
           Command :: nonempty_string() | binary()) ->
    module_response(binary()).

exec(Agent, Prefix, Command) ->
    cloudi:send_sync(Agent, Prefix, Command).

-spec exec(Agent :: agent(),
           Prefix :: service_name(),
           Command :: nonempty_string() | binary(),
           Timeout :: timeout_milliseconds()) ->
    module_response(binary()).

exec(Agent, Prefix, Command, Timeout) ->
    cloudi:send_sync(Agent, Prefix, Command, Timeout).

%%%------------------------------------------------------------------------
%%% Callback functions from cloudi_service
%%%------------------------------------------------------------------------

cloudi_service_init(Args, _Prefix, _Timeout, Dispatcher) ->
    Defaults = [
        {file_path,                    ?DEFAULT_FILE_PATH},
        {directory,                    ?DEFAULT_DIRECTORY},
        {env,                          ?DEFAULT_ENV},
        {user,                         ?DEFAULT_USER},
        {su_path,                      ?DEFAULT_SU_PATH},
        {login,                        ?DEFAULT_LOGIN},
        {debug,                        ?DEFAULT_DEBUG},
        {debug_level,                  ?DEFAULT_DEBUG_LEVEL}],
    [FilePath, Directory, Env, User, SUPath, Login,
     Debug, DebugLevel] = cloudi_proplists:take_values(Defaults, Args),
    [_ | _] = FilePath,
    true = filelib:is_regular(FilePath),
    [_ | _] = Directory,
    true = filelib:is_dir(Directory),
    EnvExpanded = env_expand(Env, cloudi_environment:lookup()),
    case User of
        undefined ->
            ok;
        [_ | _] ->
            true = filelib:is_regular(SUPath)
    end,
    EnvPort = if
        Login =:= true, is_list(User) ->
            false;
        is_boolean(Login) ->
            true
    end,
    EnvExpanded = env_expand(Env, cloudi_environment:lookup()),
    EnvShell = if
        EnvPort =:= true ->
            env_reset(EnvExpanded);
        EnvPort =:= false ->
            EnvExpanded
    end,
    true = is_boolean(Debug),
    true = ((DebugLevel =:= trace) orelse
            (DebugLevel =:= debug) orelse
            (DebugLevel =:= info) orelse
            (DebugLevel =:= warn) orelse
            (DebugLevel =:= error) orelse
            (DebugLevel =:= fatal)),
    DebugLogLevel = if
        Debug =:= false ->
            off;
        Debug =:= true ->
            DebugLevel
    end,
    cloudi_service:subscribe(Dispatcher, ""),
    {ok, #state{file_path = FilePath,
                directory = Directory,
                env = EnvShell,
                env_port = EnvPort,
                user = User,
                su = SUPath,
                login = Login,
                debug_level = DebugLogLevel}}.

cloudi_service_handle_request(_RequestType, _Name, _Pattern,
                              _RequestInfo, Request,
                              _Timeout, _Priority, _TransId, _Pid,
                              #state{debug_level = DebugLogLevel} = State,
                              _Dispatcher) ->
    {Status, Output} = request(Request, State),
    log_output(Status, Output, Request, DebugLogLevel),
    {reply, erlang:integer_to_binary(Status), State}.

cloudi_service_terminate(_Reason, _Timeout, _State) ->
    ok.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

env_expand([] = L, _) ->
    L;
env_expand([{[_ | _] = Key, Value} | L], Lookup)
    when is_list(Value) ->
    [_ | _] = KeyExpanded = cloudi_environment:transform(Key, Lookup),
    [{KeyExpanded, cloudi_environment:transform(Value, Lookup)} |
     env_expand(L, Lookup)].

env_reset(L) ->
    % remove environment variables set by CloudI execution
    [{"BINDIR", false},
     {"EMU", false},
     {"ERL_AFLAGS", false},
     {"ERL_COMPILER_OPTIONS", false},
     {"ERL_CRASH_DUMP", false},
     {"ERL_CRASH_DUMP_SECONDS", false},
     {"ERL_EPMD_ADDRESS", false},
     {"ERL_EPMD_PORT", false},
     {"ERL_FLAGS", false},
     {"ERL_LIBS", false},
     {"ERL_ZFLAGS", false},
     {"ESCRIPT_NAME", false},
     {"HEART_BEAT_TIMEOUT", false},
     {"HEART_COMMAND", false},
     {"HEART_KILL_SIGNAL", false},
     {"HEART_NO_KILL", false},
     {"PROGNAME", false},
     {"ROOTDIR", false},
     {"RUN_ERL_DISABLE_FLOWCNTRL", false},
     {"RUN_ERL_LOG_ACTIVITY_MINUTES", false},
     {"RUN_ERL_LOG_ALIVE_FORMAT", false},
     {"RUN_ERL_LOG_ALIVE_IN_UTC", false},
     {"RUN_ERL_LOG_ALIVE_MINUTES", false},
     {"RUN_ERL_LOG_GENERATIONS", false},
     {"RUN_ERL_LOG_MAXSIZE", false},
     {"TMPDIR", false} | L].

env_set([], Directory, ShellInput) ->
    [["cd ", Directory, $\n] | ShellInput];
env_set([{[_ | _] = Key, Value} | L], Directory, ShellInput) ->
    [[Key, $=, Value, "; export ", Key, $\n] |
     env_set(L, Directory, ShellInput)].

request(Exec, #state{file_path = FilePath,
                     directory = Directory,
                     env = Env,
                     env_port = EnvPort,
                     user = User,
                     su = SUPath,
                     login = Login}) ->
    ShellInput0 = [unicode:characters_to_binary(Exec, utf8), "\n"
                   "exit $?\n"],
    PortOptions0 = [stream, binary, stderr_to_stdout, exit_status],
    {ShellInputN, PortOptionsN} = if
        EnvPort =:= true ->
            {ShellInput0,
             [{env, Env}, {cd, Directory} | PortOptions0]};
        EnvPort =:= false ->
            {env_set(Env, Directory, ShellInput0),
             PortOptions0}
    end,
    {ShellExecutable, ShellArgs} = if
        User =:= undefined ->
            {FilePath,
             if
                 Login =:= true ->
                     ["-"];
                 Login =:= false ->
                     []
             end};
        is_list(User) ->
            {SUPath,
             if
                 Login =:= true ->
                     ["-s", FilePath, "-", User];
                 Login =:= false ->
                     ["-s", FilePath, User]
             end}
    end,
    Shell = erlang:open_port({spawn_executable, ShellExecutable},
                             [{args, ShellArgs} | PortOptionsN]),
    true = erlang:port_command(Shell, ShellInputN),
    request_output(Shell, []).

request_output(Shell, Output) ->
    receive
        {Shell, {data, Data}} ->
            request_output(Shell, [Data | Output]);
        {Shell, {exit_status, Status}} ->
            {Status, lists:reverse(Output)}
    end.

log_output(Status, Output, Request, DebugLogLevel) ->
    Level = if
        Status == 0 ->
            DebugLogLevel;
        true ->
            error
    end,
    if
        Output == [] ->
            ?LOG(Level, "~ts = ~w",
                 [Request, Status]);
        true ->
            ?LOG(Level, "~ts = ~w (stdout/stderr below)~n~ts",
                 [Request, Status, erlang:iolist_to_binary(Output)])
    end.

