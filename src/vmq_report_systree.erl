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

-module(vmq_report_systree).
-behaviour(exometer_report).

%% gen_server callbacks
-export(
   [
    exometer_init/1,
    exometer_info/2,
    exometer_cast/2,
    exometer_call/3,
    exometer_report/5,
    exometer_subscribe/5,
    exometer_unsubscribe/4,
    exometer_newentry/2,
    exometer_setopts/4,
    exometer_terminate/2
   ]).

-include_lib("exometer_core/include/exometer.hrl").

-record(st, {
          publish_fun}).


%% Probe callbacks
exometer_init(Opts) ->
    lager:info("Systree Reporter initialized; Opts: ~p~n", [Opts]),
    {ok, {M, F, A}} = application:get_env(vmq_systree, registry_mfa),
    {RegisterFun, PublishFun, _SubscribeFun} = apply(M,F,A),
    true = is_function(RegisterFun, 0),
    true = is_function(PublishFun, 2),
    case RegisterFun() of
        ok ->
            {ok, #st{publish_fun=PublishFun}};
        E ->
            E
    end.

exometer_report(Probe, DataPoint, _Extra, Value, #st{publish_fun=PubFun} = St) ->
    Name = name(Probe, DataPoint),
    BValue = value(Value),
    PubFun(lists:flatten(["$SYS/", atom_to_list(node()), "/", Name]), BValue),
    {ok, St}.

exometer_subscribe(_Metric, _DataPoint, _Extra, _Interval, St) ->
    {ok, St }.

exometer_unsubscribe(_Metric, _DataPoint, _Extra, St) ->
    {ok, St }.

exometer_call(Unknown, From, St) ->
    lager:info("Unknown call ~p from ~p", [Unknown, From]),
    {ok, St}.

exometer_cast(Unknown, St) ->
    lager:info("Unknown cast: ~p", [Unknown]),
    {ok, St}.

exometer_info(Unknown, St) ->
    lager:info("Unknown info: ~p", [Unknown]),
    {ok, St}.

exometer_newentry(_Entry, St) ->
    {ok, St}.

exometer_setopts(_Metric, _Options, _Status, St) ->
    {ok, St}.

exometer_terminate(_, _) ->
    ignore.

%% Add probe and datapoint within probe
name(Probe, DataPoint) ->
    [[[metric_elem_to_list(I), $/] || I <- Probe], datapoint(DataPoint)].

metric_elem_to_list(V) when is_atom(V) -> atom_to_list(V);
metric_elem_to_list(V) when is_binary(V) -> binary_to_list(V);
metric_elem_to_list(V) when is_integer(V) -> integer_to_list(V);
metric_elem_to_list(V) when is_list(V) -> V.

datapoint(V) when is_integer(V) -> integer_to_list(V);
datapoint(V) when is_atom(V) -> atom_to_list(V).

%% Add value, int or float, converted to list
value(V) when is_integer(V) -> integer_to_binary(V);
value(V) when is_float(V)   -> float_to_binary(V);
value(_) -> 0.

