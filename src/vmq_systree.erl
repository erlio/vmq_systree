%% Copyright 2014 Erlio GmbH Basel Switzerland (http://erl.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(vmq_systree).

-behaviour(gen_server).

%% API
-export([start_link/0,
         change_config_now/3,
         summary/0]).

-export([incr_bytes_received/1,
         incr_bytes_sent/1,
         incr_inactive_clients/0,
         decr_inactive_clients/0,
         incr_expired_clients/0,
         incr_messages_received/1,
         incr_messages_sent/1,
         incr_publishes_dropped/1,
         incr_publishes_received/1,
         incr_publishes_sent/1,
         incr_subscription_count/0,
         decr_subscription_count/0,
         incr_socket_count/0,
         incr_connect_received/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {interval=10000,
                registerfun,
                publishfun,
                server_utils,
                ref}).
-define(TABLE, vmq_systree).

-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec change_config_now(_, [any()], _) -> 'ok'.
change_config_now(_New, Changed, _Deleted) ->
    %% we are only interested if the config changes
    {_, NewInterval} = proplists:get_value(sys_interval,
                                           Changed, {undefined,10}),
    gen_server:cast(?MODULE, {new_interval, NewInterval}).

incr_bytes_received(V) ->
    incr_item(local_bytes_received, V).

incr_bytes_sent(V) ->
    incr_item(local_bytes_sent, V).

incr_expired_clients() ->
    update_item({local_expired_clients, counter}, {2, 1}).

incr_inactive_clients() ->
    update_item({local_inactive_clients, counter}, {2, 1}).

decr_inactive_clients() ->
    update_item({local_inactive_clients, counter}, {2, -1, 0, 0}).

incr_messages_received(V) ->
    incr_item(local_messages_received, V).

incr_messages_sent(V) ->
    incr_item(local_messages_sent, V).

incr_publishes_dropped(V) ->
    incr_item(local_publishes_dropped, V).

incr_publishes_received(V) ->
    incr_item(local_publishes_received, V).

incr_publishes_sent(V) ->
    incr_item(local_publishes_sent, V).

incr_subscription_count() ->
    update_item({local_subscription_count, counter}, {2, 1}).

decr_subscription_count() ->
    update_item({local_subscription_count, counter}, {2, -1, 0, 0}).

incr_socket_count() ->
    incr_item(local_socket_count).

incr_connect_received() ->
    incr_item(local_connect_received).

summary() ->
    gen_server:call(?MODULE, summary).

items() ->
    [{local_bytes_received,     mavg},
     {local_bytes_sent,         mavg},
     {local_active_clients,     gauge},
     {local_inactive_clients,   counter},
     {local_expired_clients,    counter},
     {local_messages_received,  mavg},
     {local_messages_sent,      mavg},
     {local_publishes_dropped,  mavg},
     {local_publishes_received, mavg},
     {local_publishes_sent,     mavg},
     {local_subscription_count, counter},
     {local_socket_count,       mavg},
     {local_connect_received,   mavg},
     {global_clients_total,     gauge},
     {erlang_vm_metrics,        gauge},
     {local_inflight_count,     gauge},
     {local_retained_count,     gauge},
     {local_stored_count,       gauge}].

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

-spec init([integer()]) -> {'ok', state()}.
init([]) ->
    Interval = application:get_env(vmq_systree, interval, 10),
    {ok, {M, F, A}} = application:get_env(vmq_systree, registry_mfa),
    {ok, ServerUtils} = application:get_env(vmq_systree, server_utils),
    {RegisterFun, PublishFun, _SubscribeFun} = apply(M,F,A),
    true = is_function(RegisterFun, 0),
    true = is_function(PublishFun, 2),
    ets:new(?TABLE, [public, named_table, {write_concurrency, true}]),
    init_table(items()),
    IntervalMS =
        case Interval of
            0 -> undefined;
            _ ->
                Interval * 1000
    end,
    erlang:send_after(1000, self(), shift),
    {ok, #state{interval=IntervalMS,
                registerfun=RegisterFun, publishfun=PublishFun,
                server_utils=ServerUtils}, 1000}.

-spec handle_call(_, _, state()) -> {reply, ok | list(), state()}.
handle_call(summary, _From, State) ->
    {reply, summary(State), State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

-spec handle_cast(_, state()) -> {noreply, state()}.
handle_cast({new_interval, Interval}, State) ->
    IntervalMS = Interval * 1000,
    case State#state.ref of
        undefined -> ok;
        OldRef -> erlang:cancel_timer(OldRef)
    end,
    TRef =
    case Interval of
        0 -> undefined;
        _ ->
            erlang:send_after(IntervalMS, self(), publish)
    end,
    {noreply, State#state{interval=IntervalMS, ref=TRef}}.

-spec handle_info(_, _) -> {'noreply', _}.
handle_info(timeout, #state{registerfun=RegisterFun, interval=I} = State) ->
    ok = RegisterFun(),
    NewState =
    case I of
        undefined ->
            State;
        _ ->
            TRef = erlang:send_after(I, self(), publish),
            State#state{ref=TRef}
    end,
    {noreply, NewState};
handle_info(publish, State) ->
    #state{interval=Interval} = State,
    Snapshots = averages(items(), []),
    publish(State, Snapshots),
    TRef = erlang:send_after(Interval, self(), publish),
    {noreply, State#state{ref=TRef}};
handle_info(shift, State) ->
    shift(now_epoch(), items()),
    erlang:send_after(1000, self(), shift),
    {noreply, State}.

-spec terminate(_, state()) -> 'ok'.
terminate(_Reason, _State) ->
    ok.

-spec code_change(_, _, _) -> {'ok', _}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


summary(State) ->
    Snapshots = averages(items(), []),
    summary(State, Snapshots, []).

summary(_, [], Acc) -> Acc;
summary(#state{server_utils=Utils} = State, [{local_active_clients, gauge}|Rest], Acc) ->
    V = apply(Utils, active_clients, []),
    summary(State, Rest, [{active_clients, V}|Acc]);
summary(State, [{local_inactive_clients, V}|Rest], Acc) ->
    summary(State,Rest, [{inactive_clients, V}|Acc]);
summary(State, [{local_subscription_count, V}|Rest], Acc) ->
    summary(State, Rest, [{subscription_count, V}|Acc]);
summary(State, [{local_bytes_received, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{total_bytes_received, All},
                   {bytes_recv_avg_1min, Min1},
                   {bytes_recv_avg_5min, Min5 div 5},
                   {bytes_recv_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_bytes_sent, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{total_bytes_sent, All},
                   {bytes_send_avg_1min, Min1},
                   {bytes_send_avg_5min, Min5 div 5},
                   {bytes_send_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_messages_received, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{total_messages_received, All},
                   {messages_recv_avg_1min, Min1},
                   {messages_recv_avg_5min, Min5 div 5},
                   {messages_recv_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_messages_sent, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{total_messages_sent, All},
                   {messages_send_avg_1min, Min1},
                   {messages_send_avg_5min, Min5 div 5},
                   {messages_send_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_publishes_received, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State,Rest, [{total_publishes_received, All},
                   {publishes_recv_avg_1min, Min1},
                   {publishes_recv_avg_5min, Min5 div 5},
                   {publishes_recv_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_publishes_sent, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{total_publishes_sent, All},
                   {publishes_send_avg_1min, Min1},
                   {publishes_send_avg_5min, Min5 div 5},
                   {publishes_send_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_publishes_dropped, All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{total_publishes_dropped, All},
                   {publishes_drop_avg_1min, Min1},
                   {publishes_drop_avg_5min, Min5 div 5},
                   {publishes_drop_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_connect_received, _All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{connect_recv_avg_1min, Min1},
                   {connect_recv_avg_5min, Min5 div 5},
                   {connect_recv_avg_15min, Min15 div 15}|Acc]);
summary(State, [{local_socket_count, _All, Min1, Min5, Min15}|Rest], Acc) ->
    summary(State, Rest, [{socket_count_avg_1min, Min1},
                   {socket_count_avg_5min, Min5 div 5},
                   {socket_count_avg_15min, Min15 div 15}|Acc]);
summary(#state{server_utils=Utils} = State, [{global_clients_total, gauge}|Rest], Acc) ->
    Total = apply(Utils, total_clients, []),
    summary(State, Rest, [{total_clients, Total}|Acc]);
summary(#state{server_utils=Utils} = State, [{local_inflight_count, gauge}|Rest], Acc) ->
    V = apply(Utils, in_flight, []),
    summary(State, Rest, [{inflight, V}|Acc]);
summary(#state{server_utils=Utils} = State, [{local_retained_count, gauge}|Rest], Acc) ->
    V = apply(Utils, retained, []),
    summary(State, Rest, [{retained, V}|Acc]);
summary(#state{server_utils=Utils} = State, [{local_stored_count, gauge}|Rest], Acc) ->
    V = apply(Utils, stored, []),
    summary(State, Rest, [{stored, V}|Acc]);
summary(State, [_|Rest], Acc) ->
    summary(State, Rest, Acc).


%%%===================================================================
%%% Internal functions
%%%===================================================================
publish(_, []) -> ok;
publish(#state{server_utils=Utils} = State, [{local_active_clients, gauge}|Rest]) ->
    V = apply(Utils, active_clients, []),
    publish(State, "clients/active", V),
    publish(State, Rest);
publish(State, [{local_inactive_clients, V}|Rest]) ->
    publish(State, "clients/inactive", V),
    publish(State, Rest);
publish(State, [{local_subscription_count, V}|Rest]) ->
    publish(State, "subscriptions/count", V),
    publish(State, Rest);
publish(State, [{local_bytes_received, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "bytes/received", All),
    publish(State, "load/bytes/received/1min", Min1),
    publish(State, "load/bytes/received/5min", Min5 div 5),
    publish(State, "load/bytes/received/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_bytes_sent, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "bytes/sent", All),
    publish(State, "load/bytes/sent/1min", Min1),
    publish(State, "load/bytes/sent/5min", Min5 div 5),
    publish(State, "load/bytes/sent/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_messages_received, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "messages/received", All),
    publish(State, "load/messages/received/1min", Min1),
    publish(State, "load/messages/received/5min", Min5 div 5),
    publish(State, "load/messages/received/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_messages_sent, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "messages/sent", All),
    publish(State, "load/messages/sent/1min", Min1),
    publish(State, "load/messages/sent/5min", Min5 div 5),
    publish(State, "load/messages/sent/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_publishes_received, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "publish/messages/received", All),
    publish(State, "load/publish/received/1min", Min1),
    publish(State, "load/publish/received/5min", Min5 div 5),
    publish(State, "load/publish/received/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_publishes_sent, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "publish/messages/sent", All),
    publish(State, "load/publish/sent/1min", Min1),
    publish(State, "load/publish/sent/5min", Min5 div 5),
    publish(State, "load/publish/sent/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_publishes_dropped, All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "publish/messages/dropped", All),
    publish(State, "load/publish/dropped/1min", Min1),
    publish(State, "load/publish/dropped/5min", Min5 div 5),
    publish(State, "load/publish/dropped/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_connect_received, _All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "load/connections/1min", Min1),
    publish(State, "load/connections/5min", Min5 div 5),
    publish(State, "load/connections/15min", Min15 div 15),
    publish(State, Rest);
publish(State, [{local_socket_count, _All, Min1, Min5, Min15}|Rest]) ->
    publish(State, "load/sockets/1min", Min1),
    publish(State, "load/sockets/5min", Min5 div 5),
    publish(State, "load/sockets/15min", Min15 div 15),
    publish(State, Rest);
publish(#state{server_utils=Utils} = State, [{global_clients_total, gauge}|Rest]) ->
    Total = apply(Utils, total_clients, []),
    publish(State, "clients/total", Total),
    publish(State, Rest);
publish(State, [{erlang_vm_metrics, gauge}|Rest]) ->
    publish(State, "vm/memory", erlang:memory(total)),
    publish(State, "vm/port_count", erlang:system_info(port_count)),
    publish(State, "vm/process_count", erlang:system_info(process_count)),
    publish(State, Rest);
publish(#state{server_utils=Utils} = State, [{local_inflight_count, gauge}|Rest]) ->
    publish(State, "messages/inflight", apply(Utils, in_flight, [])),
    publish(State, Rest);
publish(#state{server_utils=Utils} = State, [{local_retained_count, gauge}|Rest]) ->
    publish(State, "retained messages/count", apply(Utils, retained, [])),
    publish(State, Rest);
publish(#state{server_utils=Utils} = State, [{local_stored_count, gauge}|Rest]) ->
    publish(State, "messages/stored", apply(Utils, stored, [])),
    publish(State, Rest);
publish(State, [_|Rest]) ->
    publish(State, Rest).

publish(#state{publishfun=PubFun}, Topic, Val) ->
    PubFun(lists:flatten(["$SYS/", atom_to_list(node()), "/", Topic]),
           erlang:integer_to_binary(Val)).

init_table([]) -> ok;
init_table([{MetricName, mavg}|Rest]) ->
    Epoch = now_epoch(),
    ets:insert_new(?TABLE, {{MetricName, total}, 0, Epoch}),
    Min1 = list_to_tuple([{MetricName, min1} | [0 || _ <- lists:seq(1, 61)]]),
    ets:insert_new(?TABLE, Min1),
    Min5 = list_to_tuple([{MetricName, min5} | [0 || _ <- lists:seq(1, 301)]]),
    ets:insert_new(?TABLE, Min5),
    Min15 = list_to_tuple([{MetricName, min15} |
                           [0 || _ <- lists:seq(1, 901)]]),
    ets:insert_new(?TABLE, Min15),
    init_table(Rest);
init_table([{MetricName, counter}|Rest]) ->
    ets:insert(?TABLE, {{MetricName, counter}, 0}),
    init_table(Rest);
init_table([_|Rest]) ->
    init_table(Rest).

incr_item(MetricName) ->
    incr_item(MetricName, 1).
incr_item(MetricName, V) ->
    Epoch = now_epoch(),
    PosMin1 = 2 + (Epoch rem 61),
    PosMin5 = 2 + (Epoch rem 301),
    PosMin15 = 2 + (Epoch rem 901),
    update_item({MetricName, total}, [{2, V}, {3, 1, 0, Epoch}]),
    update_item({MetricName, min1}, [{PosMin1, V}, {PosMin1 + 1, 1, 0, 0}]),
    update_item({MetricName, min5}, [{PosMin5, V}, {PosMin5 + 1, 1, 0, 0}]),
    update_item({MetricName, min15}, [{PosMin15, V}, {PosMin15 + 1, 1, 0, 0}]).

shift(_, []) -> ok;
shift(Now, [{Key, mavg}|Rest]) ->
    [{_, _, LastIncr}] = ets:lookup(?TABLE, {Key, total}),
    case Now - LastIncr of
        0 -> shift(Now, Rest);
        Diff ->
            Diffs = [Now + I || I <- lists:seq(1, Diff)],
            ets:update_element(?TABLE, {Key, total}, {3, Now}),
            ets:update_element(?TABLE, {Key, min1},
                               [{2 + (I rem 61), 0} || I <- Diffs]),
            ets:update_element(?TABLE, {Key, min5},
                               [{2 + (I rem 301), 0} || I <- Diffs]),
            ets:update_element(?TABLE, {Key, min15},
                               [{2 + (I rem 901), 0} || I <- Diffs]),
            shift(Now, Rest)
    end;
shift(Now, [_|Rest]) ->
    shift(Now, Rest).

update_item(Key, UpdateOp) ->
    try
        ets:update_counter(?TABLE, Key, UpdateOp)
    catch error:badarg -> error
    end.

averages([], Acc) -> Acc;
averages([{Key, counter}|Rest], Acc) ->
    %% nothing to move, but we accumulate the item
    [{_, Val}] = ets:lookup(?TABLE, {Key, counter}),
    averages(Rest, [{Key, Val}|Acc]);
averages([{Key, mavg}|Rest], Acc) ->
    [{_, Count, _}] = ets:lookup(?TABLE, {Key, total}),
    Item = {Key, Count,
            sum({Key, min1}),
            sum({Key, min5}) div 5,
            sum({Key, min15}) div 15},
    averages(Rest, [Item|Acc]);
averages([{Key, gauge}|Rest], Acc) ->
    averages(Rest, [{Key, gauge}|Acc]).



sum(Key) ->
    [Item] = ets:lookup(?TABLE, Key),
    [_|Vals] = tuple_to_list(Item),
    lists:sum(Vals).

now_epoch() ->
    {Mega, Sec, _} = os:timestamp(),
    (Mega * 1000000 + Sec).
