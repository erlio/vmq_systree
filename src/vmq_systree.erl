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
-export([start/0,
         stop/0,
         change_config/1]).

-define(REPORTER, vmq_report_systree).


start() ->
    {ok, _} = application:ensure_all_started(vmq_systree),
    SystreeConfig = application:get_all_env(vmq_systree),
    init_systree(SystreeConfig),
    vmq_systree_cli:register(),
    ok.

stop() ->
    exometer_report:disable_reporter(?REPORTER),
    exometer_report:remove_reporter(?REPORTER),
    application:stop(vmq_systree).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Hooks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
change_config(Config) ->
    case lists:keyfind(vmq_systree, 1, application:which_applications()) of
        false ->
            %% vmq_systree app is loaded but not started
            ok;
        _ ->
            %% vmq_systree app is started
            {vmq_systree, SystreeConfig} = lists:keyfind(vmq_systree, 1, Config),
            init_systree(SystreeConfig)
    end.

init_systree(SystreeConfig) ->
    Interval = proplists:get_value(sys_interval, SystreeConfig),
    IntervalInSecs = Interval * 1000,
    exometer_report:disable_reporter(?REPORTER),
    exometer_report:remove_reporter(?REPORTER),
    exometer_report:add_reporter(?REPORTER, []),
    %% TODO: kind of a hack
    {ok, {apply, M, F, A}} = application:get_env(vmq_server,
                                                 exometer_predefined),
    {ok, Entries} = apply(M, F, A),
    ok = subscribe(Entries, IntervalInSecs),
    exometer_report:enable_reporter(?REPORTER).


subscribe([{Metric, histogram, _}|Rest], Interval) ->
    exometer_report:subscribe(?REPORTER, Metric, value, Interval),
    exometer_report:subscribe(?REPORTER, Metric, max, Interval),
    exometer_report:subscribe(?REPORTER, Metric, min, Interval),
    exometer_report:subscribe(?REPORTER, Metric, mean, Interval),
    exometer_report:subscribe(?REPORTER, Metric, median, Interval),
    subscribe(Rest, Interval);
subscribe([{Metric, _, _}|Rest], Interval) ->
    exometer_report:subscribe(?REPORTER, Metric, value, Interval),
    subscribe(Rest, Interval);
subscribe([], _) -> ok.

